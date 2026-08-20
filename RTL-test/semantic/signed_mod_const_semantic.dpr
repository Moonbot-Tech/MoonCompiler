program signed_mod_const_semantic;

{$ifdef FPC}
  {$mode delphi}
{$endif}

{ Semantic pin for the signed modulus-by-constant reduction (nmat.pas):
  x mod C is rewritten as x - (x div C) * C (non-power-of-2) or the
  branchless mask form (power of 2) instead of idiv.  The reference value
  comes from a runtime divisor the compiler cannot fold, so every edge -
  Low(T), sign combinations, |C| power of 2 and not - is compared against
  the untransformed machine division. }

uses
  {$ifdef FPC}
  mormot.core.fpcx64mm,
  {$ifdef UNIX}cthreads,cwstring,{$endif UNIX}
  {$endif}
  SysUtils;

var
  RuntimeDiv32: Integer;
  RuntimeDiv64: Int64;

procedure Fail(const AWhere: string);
begin
  WriteLn('FAIL: ', AWhere);
  Halt(1);
end;

procedure Check32(X: Integer);
var
  M, D: Integer;
begin
  RuntimeDiv32 := 10;
  M := X mod 10;
  D := X div 10;
  If (M <> X mod RuntimeDiv32) or (D <> X div RuntimeDiv32) then
    Fail(Format('int32 10: x=%d', [X]));
  RuntimeDiv32 := 7;
  If X mod 7 <> X mod RuntimeDiv32 then
    Fail(Format('int32 7: x=%d', [X]));
  RuntimeDiv32 := 8;
  If X mod 8 <> X mod RuntimeDiv32 then
    Fail(Format('int32 8: x=%d', [X]));
  RuntimeDiv32 := 2;
  If X mod 2 <> X mod RuntimeDiv32 then
    Fail(Format('int32 2: x=%d', [X]));
  RuntimeDiv32 := -3;
  If X mod (-3) <> X mod RuntimeDiv32 then
    Fail(Format('int32 -3: x=%d', [X]));
  RuntimeDiv32 := -8;
  If X mod (-8) <> X mod RuntimeDiv32 then
    Fail(Format('int32 -8: x=%d', [X]));
end;

procedure Check64(X: Int64);
var
  M, D: Int64;
begin
  RuntimeDiv64 := 1000;
  M := X mod 1000;
  D := X div 1000;
  If (M <> X mod RuntimeDiv64) or (D <> X div RuntimeDiv64) then
    Fail(Format('int64 1000: x=%d', [X]));
  RuntimeDiv64 := 10;
  If X mod 10 <> X mod RuntimeDiv64 then
    Fail(Format('int64 10: x=%d', [X]));
  RuntimeDiv64 := 16;
  If X mod 16 <> X mod RuntimeDiv64 then
    Fail(Format('int64 16: x=%d', [X]));
  RuntimeDiv64 := -1000;
  If X mod (-1000) <> X mod RuntimeDiv64 then
    Fail(Format('int64 -1000: x=%d', [X]));
end;

const
  Edges32: array[0..11] of Integer = (
    Low(Integer), Low(Integer) + 1, -1001, -1000, -999, -11, -1, 0,
    1, 999, High(Integer) - 1, High(Integer));
  Edges64: array[0..11] of Int64 = (
    Low(Int64), Low(Int64) + 1, -1000000001, -1000000000, -1001, -999,
    -1, 0, 1, 1000, High(Int64) - 1, High(Int64));

var
  I: Integer;
begin
  for I := 0 to High(Edges32) do
    Check32(Edges32[I]);
  for I := 0 to High(Edges64) do
    Check64(Edges64[I]);
  { sign of the remainder follows the dividend: pin a few directly }
  If (-7) mod 3 <> -1 then
    Fail('sign -7 mod 3');
  If 7 mod (-3) <> 1 then
    Fail('sign 7 mod -3');
  If (-7) mod (-3) <> -1 then
    Fail('sign -7 mod -3');
  WriteLn('SIGNED_MOD_CONST_PASS');
end.
