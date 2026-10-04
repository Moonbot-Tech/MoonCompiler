program mm_hotpath_stress_semantic;

{ Cross-thread stress of the hand-laid hot paths of the bundled memory
  manager (GetMem, ReallocMem, FreeMem of tiny, small, medium and large
  blocks).  Each of eight workers fills a set of blocks covering every small
  class plus medium and large sizes with a pattern, reallocates half of them
  up and down, then hands the whole set to the next worker, which verifies
  the patterns and frees the blocks while the others allocate.  So the owner
  path (lock free, nothing pending), the foreign-thread free path (LastFree
  and pending bins), the small upsize/downsize and the medium/large realloc
  run concurrently for many rounds.  The edge contracts (GetMem(0),
  ReallocMem(nil, n), ReallocMem(P, 0), FreeMem(nil), AllocMem) are pinned
  as well, and the leak census at exit must be empty. }

{$mode delphi}{$H+}
{$APPTYPE CONSOLE}
{$Q-}{$R-}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  {$endif UNIX}
  SysUtils,
  Classes;

const
  WorkerCount = 8;
  BlocksPerSet = 2048;
  Rounds = 64;
  MaxSmall = 2592; // MaximumSmallBlockSize - BlockHeaderSize of the MM

type
  TBlockSet = record
    Data: array[0..BlocksPerSet - 1] of Pointer;
    Size: array[0..BlocksPerSet - 1] of SizeInt;
  end;
  PBlockSet = ^TBlockSet;

  TWorker = class(TThread)
  private
    FId: Integer;
    FOwn: PBlockSet;
    FForeign: PBlockSet;
    FForeignId: Integer;
    procedure Fail(Code, Round, Index: Integer);
  protected
    procedure Execute; override;
  public
    ErrorCode: Integer;
    ErrorRound: Integer;
    ErrorIndex: Integer;
    constructor Create(Id: Integer; Own, Foreign: PBlockSet; ForeignId: Integer);
  end;

var
  Sets: array[0..WorkerCount - 1] of TBlockSet;
  Arrived: LongInt;
  Failed: LongInt;

function BlockSize(Round, Index: Integer): SizeInt;
begin
  case Index and 1023 of
    512:
      Result := 300000 + Index * 64 + Round;             // large
    256, 768:
      Result := 3000 + (Index * 97 + Round * 131) mod 200000; // medium
  else
    Result := 1 + (Index * 37 + Round * 11) mod MaxSmall;   // tiny / small
  end;
end;

function Pattern(Owner, Round, Index: Integer): QWord; inline;
begin
  Result := (QWord(Owner + 1) shl 56) or (QWord(Round + 1) shl 40) or
    (QWord($A5) shl 32) or QWord(Index + 1);
end;

procedure Stamp(P: Pointer; Size: SizeInt; Value: QWord);
begin
  If Size >= 8 then
    PQWord(P)^ := Value
  else
    FillChar(P^, Size, Byte(Value));
  If Size >= 9 then
    PByte(P)[Size - 1] := Byte(Value shr 8) xor $5A;
end;

function Verify(P: Pointer; Size: SizeInt; Value: QWord): Boolean;
var
  K: SizeInt;
begin
  Result := False;
  If P = nil then
    Exit;
  If Size >= 8 then begin
    If PQWord(P)^ <> Value then
      Exit;
  end else
    for K := 0 to Size - 1 do
      If PByte(P)[K] <> Byte(Value) then
        Exit;
  If (Size >= 9) and (PByte(P)[Size - 1] <> (Byte(Value shr 8) xor $5A)) then
    Exit;
  Result := True;
end;

// the first Keep bytes of a reallocated block must be preserved: the bytes
// of the stamped QWord when the old block had room for it, else the fill
function VerifyHead(P: Pointer; Keep, OldSize: SizeInt; Value: QWord): Boolean;
var
  K: SizeInt;
begin
  Result := False;
  If P = nil then
    Exit;
  If Keep >= 8 then begin
    If PQWord(P)^ <> Value then
      Exit;
  end else
    for K := 0 to Keep - 1 do
      If OldSize >= 8 then begin
        If PByte(P)[K] <> Byte(Value shr (8 * K)) then
          Exit;
      end else If PByte(P)[K] <> Byte(Value) then
        Exit;
  Result := True;
end;

// every worker waits until all workers reached this phase; a failure
// elsewhere releases the wait so nobody spins forever
function Barrier(Phase: Integer): Boolean;
begin
  InterlockedIncrement(Arrived);
  while InterlockedCompareExchange(Arrived, 0, 0) < Phase * WorkerCount do begin
    If InterlockedCompareExchange(Failed, 0, 0) <> 0 then
      Exit(False);
    Sleep(0);
  end;
  Result := InterlockedCompareExchange(Failed, 0, 0) = 0;
end;

constructor TWorker.Create(Id: Integer; Own, Foreign: PBlockSet; ForeignId: Integer);
begin
  inherited Create(True);
  FId := Id;
  FOwn := Own;
  FForeign := Foreign;
  FForeignId := ForeignId;
end;

procedure TWorker.Fail(Code, Round, Index: Integer);
begin
  ErrorCode := Code;
  ErrorRound := Round;
  ErrorIndex := Index;
  InterlockedExchange(Failed, 1);
end;

procedure TWorker.Execute;
var
  Round, I: Integer;
  Size, NewSize, Keep: SizeInt;
  P: Pointer;
  V: QWord;
begin
  try
    for Round := 0 to Rounds - 1 do begin
      // fill the own set
      for I := 0 to BlocksPerSet - 1 do begin
        Size := BlockSize(Round, I);
        V := Pattern(FId, Round, I);
        GetMem(P, Size);
        If P = nil then begin
          Fail(1, Round, I);
          Exit;
        end;
        Stamp(P, Size, V);
        FOwn^.Data[I] := P;
        FOwn^.Size[I] := Size;
      end;
      // reallocate every other block: up (1 mod 4) or down (3 mod 4)
      I := 1;
      while I < BlocksPerSet do begin
        Size := FOwn^.Size[I];
        V := Pattern(FId, Round, I);
        If (I and 3) = 1 then
          NewSize := Size * 2 + 1
        else
          NewSize := Size div 2 + 1;
        If NewSize < Size then
          Keep := NewSize
        else
          Keep := Size;
        P := FOwn^.Data[I];
        ReallocMem(P, NewSize);
        If not VerifyHead(P, Keep, Size, V) then begin
          Fail(2, Round, I);
          Exit;
        end;
        If (NewSize >= Size) and (Size >= 9) and
           (PByte(P)[Size - 1] <> (Byte(V shr 8) xor $5A)) then begin
          Fail(3, Round, I);
          Exit;
        end;
        Stamp(P, NewSize, V);
        FOwn^.Data[I] := P;
        FOwn^.Size[I] := NewSize;
        Inc(I, 2);
      end;
      If not Barrier(Round * 2 + 1) then
        Exit;
      // verify and free the set of the next worker
      for I := 0 to BlocksPerSet - 1 do begin
        V := Pattern(FForeignId, Round, I);
        If not Verify(FForeign^.Data[I], FForeign^.Size[I], V) then begin
          Fail(4, Round, I);
          Exit;
        end;
        FreeMem(FForeign^.Data[I]);
        FForeign^.Data[I] := nil;
      end;
      If not Barrier(Round * 2 + 2) then
        Exit;
    end;
  except
    on E: Exception do begin
      Fail(9, -1, -1);
      WriteLn('worker ', FId, ' exception: ', E.Message);
    end;
  end;
end;

procedure CheckEdges;
var
  P, Q: Pointer;
  I: Integer;
begin
  // GetMem(0) allocates the smallest block, like the RTL heap and FastMM
  GetMem(P, 0);
  If P = nil then begin
    WriteLn('FAIL GetMem(0) returned nil');
    Halt(1);
  end;
  FreeMem(P);
  // ReallocMem(nil, n) = GetMem(n); ReallocMem(P, 0) = FreeMem(P), P := nil
  P := nil;
  ReallocMem(P, 40);
  If P = nil then begin
    WriteLn('FAIL ReallocMem(nil, 40) returned nil');
    Halt(1);
  end;
  FillChar(P^, 40, $C3);
  ReallocMem(P, 100000);
  If (P = nil) or (PByte(P)[39] <> $C3) then begin
    WriteLn('FAIL ReallocMem small -> medium lost the content');
    Halt(1);
  end;
  ReallocMem(P, 24);
  If (P = nil) or (PByte(P)[23] <> $C3) then begin
    WriteLn('FAIL ReallocMem medium -> small lost the content');
    Halt(1);
  end;
  ReallocMem(P, 0);
  If P <> nil then begin
    WriteLn('FAIL ReallocMem(P, 0) did not clear P');
    Halt(1);
  end;
  If FreeMem(nil) <> 0 then begin
    WriteLn('FAIL FreeMem(nil) returned non-zero');
    Halt(1);
  end;
  // AllocMem is zeroed for every small class
  for I := 1 to MaxSmall do begin
    Q := AllocMem(I);
    If (Q = nil) or (PByte(Q)[0] <> 0) or (PByte(Q)[I - 1] <> 0) then begin
      WriteLn('FAIL AllocMem(', I, ') is not zeroed');
      Halt(1);
    end;
    FreeMem(Q);
  end;
  // every small class in the same thread: allocate, grow in place or move, free
  for I := 1 to MaxSmall do begin
    GetMem(P, I);
    FillChar(P^, I, Byte(I));
    ReallocMem(P, I + 16);
    If (PByte(P)[0] <> Byte(I)) or (PByte(P)[I - 1] <> Byte(I)) then begin
      WriteLn('FAIL ReallocMem(', I, ' -> ', I + 16, ') lost the content');
      Halt(1);
    end;
    FreeMem(P);
  end;
end;

var
  Workers: array[0..WorkerCount - 1] of TWorker;
  W: Integer;
  Ok: Boolean;
begin
  CheckEdges;
  Arrived := 0;
  Failed := 0;
  for W := 0 to WorkerCount - 1 do
    Workers[W] := TWorker.Create(W, @Sets[W], @Sets[(W + 1) mod WorkerCount], (W + 1) mod WorkerCount);
  for W := 0 to WorkerCount - 1 do
    Workers[W].Start;
  Ok := True;
  for W := 0 to WorkerCount - 1 do begin
    Workers[W].WaitFor;
    If Workers[W].ErrorCode <> 0 then begin
      WriteLn('FAIL worker ', W, ' code ', Workers[W].ErrorCode,
        ' round ', Workers[W].ErrorRound, ' index ', Workers[W].ErrorIndex);
      Ok := False;
    end;
    Workers[W].Free;
  end;
  If not Ok then
    Halt(1);
  WriteLn('workers=', WorkerCount, ' rounds=', Rounds,
    ' blocks=', WorkerCount * Rounds * BlocksPerSet);
  WriteLn('MM_HOTPATH_STRESS_PASS');
end.
