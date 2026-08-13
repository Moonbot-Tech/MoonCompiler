program memfuzz;
{ Shadow-model MM fuzzer: every live block is pattern-filled from its
  (slot,generation) seed; on free/realloc the WHOLE pattern is verified
  (overlap or corruption = immediate FAIL with reproducible seed).
  Checks: content integrity, 16-byte alignment, realloc prefix survival.
  Single-threaded pass + 4 worker threads with independent slots/rng. }
{$ifdef FPC}{$mode delphi}{$H+}{$endif}
{$APPTYPE CONSOLE}
{$Q-}{$R-}
uses
{$ifdef USEX64MM} mormot.core.fpcx64mm, {$endif}
{$ifdef FPC} cthreads, {$else} Winapi.Windows, {$endif}
  SysUtils, Classes;

const
  SlotsPerWorker = 512;
type
  TSlot = record
    P: PByte;
    Size: Integer;
    Pat: Byte;
  end;
  TFuzz = class(TThread)
  public
    Id, Ops, Fails: Integer;
    Rng: UInt64;
    Slots: array[0..SlotsPerWorker - 1] of TSlot;
    constructor Create(AId, AOps: Integer);
    procedure Run1;
    procedure Fail(const What: string; Slot: Integer);
  protected
    procedure Execute; override;
  end;

function RndNext(var S: UInt64): UInt64;
begin
  S := S xor (S shr 12);
  S := S xor (S shl 25);
  S := S xor (S shr 27);
  Result := S * UInt64($2545F4914F6CDD1D);
end;

function PickSize(R: UInt64): Integer;
var
  M: Integer;
begin
  M := Integer(R mod 100);
  if M < 70 then
    Result := 1 + Integer((R shr 8) mod 256)
  else if M < 90 then
    Result := 257 + Integer((R shr 8) mod 2344)
  else if M < 97 then
    Result := 2601 + Integer((R shr 8) mod 14904)
  else
    Result := 17505 + Integer((R shr 8) mod 102400);
end;

constructor TFuzz.Create(AId, AOps: Integer);
begin
  inherited Create(True);
  Id := AId;
  Ops := AOps;
  Rng := UInt64($6D6F6F6E626F7421) xor (UInt64(AId) shl 32);
end;

procedure TFuzz.Fail(const What: string; Slot: Integer);
begin
  Inc(Fails);
  WriteLn('FUZZ_FAIL w', Id, ' ', What, ' slot=', Slot);
end;

procedure TFuzz.Run1;
var
  K, N, J, NewSize, Keep: Integer;
  R: UInt64;
  S: ^TSlot;
  NP: PByte;
begin
  for K := 1 to Ops do
  begin
    R := RndNext(Rng);
    S := @Slots[R mod SlotsPerWorker];
    if S^.P = nil then
    begin
      S^.Size := PickSize(R shr 16);
      S^.Pat := Byte(R shr 56) or 1;
      GetMem(S^.P, S^.Size);
      if NativeUInt(S^.P) and 15 <> 0 then
        Fail('align', Integer(R mod SlotsPerWorker));
      FillChar(S^.P^, S^.Size, S^.Pat);
    end else begin
      for J := 0 to S^.Size - 1 do
        if S^.P[J] <> S^.Pat then
        begin
          Fail('corrupt', Integer(R mod SlotsPerWorker));
          Break;
        end;
      if (R shr 40) and 3 = 0 then
      begin                            { realloc, verify kept prefix }
        NewSize := PickSize(R shr 24);
        Keep := S^.Size;
        if NewSize < Keep then
          Keep := NewSize;
        NP := S^.P;
        ReallocMem(NP, NewSize);
        for J := 0 to Keep - 1 do
          if NP[J] <> S^.Pat then
          begin
            Fail('realloc-prefix', Integer(R mod SlotsPerWorker));
            Break;
          end;
        S^.P := NP;
        S^.Size := NewSize;
        S^.Pat := Byte(R shr 48) or 1;
        FillChar(S^.P^, S^.Size, S^.Pat);
      end else begin
        FreeMem(S^.P);
        S^.P := nil;
      end;
    end;
  end;
  { drain: verify + free everything }
  for N := 0 to SlotsPerWorker - 1 do
    if Slots[N].P <> nil then
    begin
      for J := 0 to Slots[N].Size - 1 do
        if Slots[N].P[J] <> Slots[N].Pat then
        begin
          Fail('drain-corrupt', N);
          Break;
        end;
      FreeMem(Slots[N].P);
      Slots[N].P := nil;
    end;
end;

procedure TFuzz.Execute;
begin
  Run1;
end;

var
  W: array[0..3] of TFuzz;
  Solo: TFuzz;
  T, TotFails: Integer;
begin
  Solo := TFuzz.Create(0, 4000000);
  Solo.Run1;                           { single-threaded pass, main thread }
  TotFails := Solo.Fails;
  WriteLn('single: ops=4000000 fails=', Solo.Fails);
  Solo.Free;

  for T := 0 to 3 do
    W[T] := TFuzz.Create(T + 1, 2000000);
  for T := 0 to 3 do
    W[T].Start;
  for T := 0 to 3 do
    W[T].WaitFor;
  for T := 0 to 3 do
  begin
    WriteLn('worker', T + 1, ': ops=2000000 fails=', W[T].Fails);
    Inc(TotFails, W[T].Fails);
    W[T].Free;
  end;
  if TotFails = 0 then
    WriteLn('FUZZ_PASS')
  else begin
    WriteLn('FUZZ_FAIL total=', TotFails);
    Halt(1);
  end;
end.
