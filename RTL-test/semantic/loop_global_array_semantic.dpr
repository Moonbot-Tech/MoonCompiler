program loop_global_array_semantic;

{$ifdef FPC}
  {$mode delphi}
{$endif}

{ Semantic pin for the global-array strength reduction (optloop pointer
  bump now also covers power-of-two element sizes with a symbol base) and
  for full-width small-register copies: results, boundaries and aliasing
  must stay bit-identical in every optimizer mode. }

uses
  {$ifdef FPC}
  mormot.core.fpcx64mm,
  {$ifdef UNIX}cthreads,cwstring,{$endif UNIX}
  {$endif}
  SysUtils;

const
  N = 517; { deliberately not a power of two }
  GuardedValues: array[0..15] of Int32 =
    (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16);

var
  GInts: array[0..N - 1] of Int32;
  GBytes: array[0..N - 1] of Byte;
  GCopy: array[0..N - 1] of Int32;
  GRecs: array[0..N - 1] of packed record
    A: Int32;
    B: Int32;
  end;

procedure Fail(const Msg: string);
begin
  WriteLn('FAIL ', Msg);
  Halt(1);
end;

procedure MutateTail;
begin
  GInts[N - 1] := GInts[N - 1] xor 1000000;
end;

var
  I: Integer;
  J: Integer;
  B: Byte;
  W: Word;
  SumFor, SumRef: Int64;
  ByteAcc, ByteRef: UInt64;
begin
{$push}{$Q-}{$R-}
  for I := 0 to N - 1 do
  begin
    GInts[I] := Int32(UInt32(I * 747796405 + 2891336453));
    GBytes[I] := Byte(I * 31 + 7);
    GRecs[I].A := I * 3;
    GRecs[I].B := -I;
  end;
{$pop}

  { The pointer-bump initializer is allowed to stand outside the array while
    the guarded loop approaches its first valid index.  Its delta must remain
    signed instead of zero-extending the negative Integer loop bound. }
  SumFor := 0;
  for J := -1100 to 1100 do
    If (J >= Low(GuardedValues)) and (J <= High(GuardedValues)) then
      SumFor := SumFor + GuardedValues[J];
  If SumFor <> 136 then
    Fail('guarded forward address');

  SumFor := 0;
  for J := 1100 downto -1100 do
    If (J >= Low(GuardedValues)) and (J <= High(GuardedValues)) then
      SumFor := SumFor + GuardedValues[J];
  If SumFor <> 136 then
    Fail('guarded backward address');

  { forward sum with the counter as index: pointer-bump candidate }
  SumFor := 0;
  for J := 0 to N - 1 do
    SumFor := SumFor + GInts[J];
  SumRef := 0;
  I := 0;
  while I < N do
  begin
    SumRef := SumRef + GInts[I];
    Inc(I);
  end;
  If SumFor <> SumRef then
    Fail('forward int sum');

  { backward loop }
  SumFor := 0;
  for J := N - 1 downto 0 do
    SumFor := SumFor + Int64(GInts[J]) * 2;
  SumRef := 0;
  I := N - 1;
  while I >= 0 do
  begin
    SumRef := SumRef + Int64(GInts[I]) * 2;
    Dec(I);
  end;
  If SumFor <> SumRef then
    Fail('backward int sum');

  { zero-iteration loop must touch nothing }
  SumFor := 12345;
  for J := 0 to -1 do
    SumFor := SumFor + GInts[J];
  If SumFor <> 12345 then
    Fail('zero-iteration');

  { writes through the counter index }
  for J := 0 to N - 1 do
    GCopy[J] := GInts[J];
  for I := 0 to N - 1 do
    If GCopy[I] <> GInts[I] then
      Fail('manual copy');

  { a call inside the loop body may mutate the array: the bumped pointer
    reads must observe the store }
  for J := 0 to N - 1 do
  begin
    If J = 0 then
      MutateTail;
    GCopy[J] := GInts[J];
  end;
  If GCopy[N - 1] <> GInts[N - 1] then
    Fail('call aliasing');

  { record fields through the counter }
  SumFor := 0;
  for J := 0 to N - 1 do
    SumFor := SumFor + GRecs[J].A + GRecs[J].B;
  SumRef := 0;
  I := 0;
  while I < N do
  begin
    SumRef := SumRef + GRecs[I].A + GRecs[I].B;
    Inc(I);
  end;
  If SumFor <> SumRef then
    Fail('record fields');

  { full byte counter range with byte temporaries: partial-register copy
    semantics (values must be exactly the low 8 bits everywhere) }
  ByteAcc := 0;
  for I := 1 to 3 do
    for B := 0 to 255 do
      ByteAcc := ByteAcc + UInt64(B xor Byte(I)) + GBytes[B and (N - 1) mod N];
  ByteRef := 0;
  for I := 1 to 3 do
  begin
    J := 0;
    while J <= 255 do
    begin
      ByteRef := ByteRef + UInt64((J xor I) and $FF) + GBytes[J and (N - 1) mod N];
      Inc(J);
    end;
  end;
  If ByteAcc <> ByteRef then
    Fail('byte counter xor');

  { word counter with copies through word temporaries }
  ByteAcc := 0;
  for W := 0 to 4097 do
  begin
    B := Byte(W shr 4);
    ByteAcc := ByteAcc + UInt64(B or Byte(W));
  end;
  ByteRef := 0;
  J := 0;
  while J <= 4097 do
  begin
    ByteRef := ByteRef + UInt64(((J shr 4) and $FF) or (J and $FF));
    Inc(J);
  end;
  If ByteAcc <> ByteRef then
    Fail('word counter or');

  WriteLn('LOOP_GLOBAL_ARRAY_OK');
end.
