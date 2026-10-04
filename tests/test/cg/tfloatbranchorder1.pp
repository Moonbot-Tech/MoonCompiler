{ %OPT=-O3 }
program tfloatbranchorder1;
{$mode delphi}
uses Math;

{ Calls in each arm keep the six comparisons as control flow. The oracle uses
  integer IEEE encodings, including unordered and the equality of signed zero. }
procedure Mark(var Bits: Integer; Flag: Integer); noinline;
begin
  Bits := Bits or Flag;
end;

function DoubleBranches(L, R: Double): Integer; noinline;
begin
  Result := 0;
  If L < R then Mark(Result, 1);
  If L <= R then Mark(Result, 2);
  If L = R then Mark(Result, 4);
  If L <> R then Mark(Result, 8);
  If L >= R then Mark(Result, 16);
  If L > R then Mark(Result, 32);
end;

function SingleBranches(L, R: Single): Integer; noinline;
begin
  Result := 0;
  If L < R then Mark(Result, 1);
  If L <= R then Mark(Result, 2);
  If L = R then Mark(Result, 4);
  If L <> R then Mark(Result, 8);
  If L >= R then Mark(Result, 16);
  If L > R then Mark(Result, 32);
end;

function Expected(A, B, Sign, Infinity: QWord): Integer;
var
  AbsA, AbsB, KeyA, KeyB: QWord;
begin
  AbsA := A and (Sign - 1);
  AbsB := B and (Sign - 1);
  If (AbsA > Infinity) or (AbsB > Infinity) then Exit(8);
  If (A = B) or ((AbsA = 0) and (AbsB = 0)) then Exit(2 or 4 or 16);
  If A and Sign <> 0 then KeyA := not A else KeyA := A or Sign;
  If B and Sign <> 0 then KeyB := not B else KeyB := B or Sign;
  { Mask the complemented key to the width of Single or Double. }
  KeyA := KeyA and (Sign or (Sign - 1));
  KeyB := KeyB and (Sign or (Sign - 1));
  If KeyA < KeyB then Result := 1 or 2 or 8 else Result := 8 or 16 or 32;
end;

const
  D: array[0..13] of QWord = (0, QWord($8000000000000000), 1, QWord($8000000000000001),
    $0010000000000000, QWord($8010000000000000), $3FF0000000000000, QWord($BFF0000000000000),
    $7FF0000000000000, QWord($FFF0000000000000), $7FF8000000000001, QWord($FFF8000000000001),
    $7FF0000000000001, QWord($FFF0000000000001));
  S: array[0..13] of LongWord = (0, $80000000, 1, $80000001, $00800000, $80800000,
    $3F800000, $BF800000, $7F800000, $FF800000, $7FC00001, $FFC00001, $7F800001, $FF800001);
var
  I, J: Integer;
  DL, DR: Double;
  SL, SR: Single;
begin
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  for I := Low(D) to High(D) do
    for J := Low(D) to High(D) do begin
      Move(D[I], DL, SizeOf(DL));
      Move(D[J], DR, SizeOf(DR));
      If DoubleBranches(DL, DR) <> Expected(D[I], D[J], QWord($8000000000000000), $7FF0000000000000) then Halt(1);
      Move(S[I], SL, SizeOf(SL));
      Move(S[J], SR, SizeOf(SR));
      If SingleBranches(SL, SR) <> Expected(S[I], S[J], $80000000, $7F800000) then Halt(2);
    end;
  Writeln('FLOAT_BRANCH_ORDER_OK');
end.
