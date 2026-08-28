program memory_stream_state_semantic;

{ R-006/C-001: memory streams as a state machine - every size, capacity
  and position transition is validated before mutation.
  DCC64-measured canvas (streams_oracle probes): negative count Read and
  Write return 0 and leave the position alone; a negative position is
  legal (Read/Write gate it, returning 0); Length(Bytes) is the rounded
  capacity, above Size.
  Deliberately STRICTER than DCC64 (measured defects, not canvas):
  Seek overflow raises instead of silently wrapping the position;
  negative SetSize raises one unified argument-error class (DCC is
  self-contradictory: accidental EStreamError via allocator failure for
  TMemoryStream, ERangeError for TBytesStream) and negative capacity is
  rejected before the allocator (DCC corrupts the heap: EInvalidPointer
  followed by a dead process). Recorded boundary: Write(_,0) after a
  Seek past the end stays a pure no-op here, while DCC64 commits the
  grown size with a garbage hole. }

{$mode delphiunicode}{$H+}
{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}cthreads,cwstring,{$endif UNIX}
  SysUtils, Classes;

var
  Fails: Integer = 0;

procedure Check(const Name: AnsiString; Cond: Boolean);
begin
  if not Cond then
  begin
    WriteLn('FAIL ', Name);
    Inc(Fails);
  end;
end;

type
  TCapHack = class(TMemoryStream); { expose protected Capacity }

  TTrackingMemoryStream = class(TMemoryStream)
  public
    CapacityCalls: Integer;
    procedure Reserve(NewCapacity: TMemoryStreamCapacity);
  protected
    procedure SetCapacity(NewCapacity: TMemoryStreamCapacity); override;
  end;

procedure TTrackingMemoryStream.SetCapacity(NewCapacity: TMemoryStreamCapacity);
begin
  Inc(CapacityCalls);
  inherited SetCapacity(NewCapacity);
end;

procedure TTrackingMemoryStream.Reserve(NewCapacity: TMemoryStreamCapacity);
begin
  SetCapacity(NewCapacity);
end;

procedure ExpectRange(const Name: AnsiString; Proc: TProc);
begin
  try
    Proc();
    Check(Name + '-raised', False);
  except
    on E: ERangeError do
      Check(Name + '-ok', True);
    on E: Exception do
    begin
      WriteLn('  got ', E.ClassName, ' "', E.Message, '"');
      Check(Name + '-class', False);
    end;
  end;
end;

var
  M: TMemoryStream;
  B: TBytesStream;
  T: TTrackingMemoryStream;
  Buf: array[0..15] of Byte;
  Rd: array[0..15] of Byte;
  R: LongInt;
  I: Integer;
begin
  for I := 0 to 15 do
    Buf[I] := $10 + I;

  M := TMemoryStream.Create;
  try
    Check('write-8', M.Write(Buf, 8) = 8);
    Check('size-pos-8', (M.Size = 8) and (M.Position = 8));

    { negative count: 0, no mutation (DCC canvas) }
    M.Position := 2;
    Check('read-neg-count', M.Read(Rd, -3) = 0);
    Check('read-neg-count-pos', M.Position = 2);
    Check('write-neg-count', M.Write(Buf, -3) = 0);
    Check('write-neg-count-state', (M.Position = 2) and (M.Size = 8));

    { negative position is legal; Read/Write gate it (DCC canvas) }
    Check('seek-neg-pos', M.Seek(-5, soBeginning) = -5);
    Check('read-at-neg', M.Read(Rd, 4) = 0);
    Check('write-at-neg', M.Write(Buf, 4) = 0);
    Check('state-after-neg', (M.Position = -5) and (M.Size = 8));

    { zero-count write is a pure no-op even past the end (recorded
      boundary vs DCC, which grows the size) }
    M.Position := 100;
    Check('zero-write-past-end', M.Write(Buf, 0) = 0);
    Check('zero-write-no-commit', (M.Size = 8) and (M.Position = 100));

    { write past the end commits the grown size; the hole is real }
    Check('write-past-end', M.Write(Buf, 4) = 4);
    Check('write-past-end-size', (M.Size = 104) and (M.Position = 104));

    { Seek overflow: the candidate is proven before FPosition is written
      (stricter than DCC's silent wrap) }
    M.Position := 0;
    ExpectRange('seek-end-overflow', procedure begin M.Seek(High(Int64), soEnd); end);
    Check('pos-kept-after-overflow', M.Position = 0);
    M.Position := 50;
    ExpectRange('seek-cur-overflow', procedure begin M.Seek(High(Int64), soCurrent); end);
    ExpectRange('seek-cur-underflow', procedure begin M.Position := -8; M.Seek(Low(Int64), soCurrent); end);
    Check('pos-kept-after-underflow', M.Position = -8);

    { negative SetSize: unified ERangeError, state untouched }
    M.Position := 4;
    ExpectRange('setsize-neg', procedure begin M.Size := -5; end);
    Check('state-after-setsize-neg', (M.Size = 104) and (M.Position = 4) and (M.Memory <> nil));

    { negative capacity rejected before the allocator (DCC corrupts) }
    ExpectRange('setcap-neg', procedure begin TCapHack(M).Capacity := -7; end);
    Check('state-after-setcap-neg', (M.Size = 104) and (M.Memory <> nil));

    { a direct reserve request below the live span must not truncate the
      allocation while leaving the old Size visible }
    M.Size := 10000;
    M.Position := 9999;
    Check('large-tail-write', M.Write(Buf, 1) = 1);
    M.Position := 9000;
    TCapHack(M).Capacity := 1;
    Check('setcap-below-size', (M.Size = 10000) and
      (TCapHack(M).Capacity >= M.Size) and (M.Position = 9000));
    M.Position := 9999;
    FillChar(Rd, SizeOf(Rd), 0);
    Check('setcap-tail-preserved', (M.Read(Rd, 1) = 1) and (Rd[0] = Buf[0]));

    { shrink keeps the invariant and clamps the position }
    M.Position := M.Size;
    M.Size := 4;
    Check('shrink', (M.Size = 4) and (M.Position = 4));

    { data round-trip after all the rejected transitions }
    M.Position := 0;
    FillChar(Rd, SizeOf(Rd), 0);
    Check('read-back', M.Read(Rd, 4) = 4);
    Check('read-back-data', (Rd[0] = $10) and (Rd[1] = $11) and (Rd[2] = $12) and (Rd[3] = $13));

    { clear releases storage and stays usable }
    M.Clear;
    Check('clear', (M.Size = 0) and (M.Position = 0) and (M.Memory = nil));
    Check('write-after-clear', M.Write(Buf, 2) = 2);
  finally
    M.Free;
  end;

  { SetSize and Clear must retain the protected virtual hook while the base
    implementation keeps pointer/size/capacity publication transactional. }
  T := TTrackingMemoryStream.Create;
  try
    T.Size := 10;
    Check('virtual-setsize-grow', (T.CapacityCalls = 1) and (T.Size = 10));
    T.Size := 2;
    Check('virtual-setsize-shrink', (T.CapacityCalls = 2) and (T.Size = 2));
    T.Reserve(10000);
    Check('virtual-direct-reserve',(T.CapacityCalls = 3) and (T.Size = 2));
    T.Position := 20000;
    Check('virtual-write-growth',T.Write(Buf,1) = 1);
    Check('virtual-write-growth-call',(T.CapacityCalls = 4) and
      (T.Size = 20001));
    T.Clear;
    Check('virtual-clear', (T.CapacityCalls = 5) and (T.Size = 0) and
      (T.Memory = nil));
  finally
    T.Free;
  end;

  { the TBytesStream twin goes through the same calculator }
  B := TBytesStream.Create(nil);
  try
    Check('b-write-1', B.Write(Buf, 1) = 1);
    Check('b-len-rounded', (Length(B.Bytes) >= B.Size) and (B.Size = 1));
    ExpectRange('b-setsize-neg', procedure begin B.Size := -5; end);
    Check('b-state-after-neg', (B.Size = 1) and (Length(B.Bytes) >= 1));
    ExpectRange('b-setcap-neg', procedure begin TCapHack(B).Capacity := -7; end);
    B.Size := 10000;
    B.Position := 9000;
    TCapHack(B).Capacity := 1;
    Check('b-setcap-below-size', (B.Size = 10000) and
      (Length(B.Bytes) >= B.Size) and (B.Position = 9000));
    Check('b-write-after', B.Write(Buf, 2) = 2);
    Check('b-final', B.Size = 10000);
    B.Position := 0;
    FillChar(Rd, SizeOf(Rd), 0);
    Check('b-read-back', (B.Read(Rd, 3) = 3) and (Rd[0] = $10));
  finally
    B.Free;
  end;

  if Fails <> 0 then
    Halt(1);
  WriteLn('MEMORY_STREAM_STATE_OK');
end.
