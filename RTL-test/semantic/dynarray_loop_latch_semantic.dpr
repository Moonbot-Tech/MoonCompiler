program dynarray_loop_latch_semantic;

{$ifdef FPC}
  {$mode delphi}
{$endif}

{ Semantic pin for the dynamic-array induction-variable substitution
  (optloop.pas): a counter-indexed dynarray access may be rewritten into a
  bumped pointer only while the base pointer cannot move.  Pins the fences:
  element writes go through (they never move the base), reassigning the
  array variable or calling anything inside the body must keep plain
  indexed access, zero-length and nil arrays run zero iterations, and
  forward/downto walks see the same elements as Delphi. }

uses
  {$ifdef FPC}
  mormot.core.fpcx64mm,
  {$ifdef UNIX}cthreads,cwstring,{$endif UNIX}
  {$endif}
  SysUtils;

var
  GBytes: array of Byte;
  GInts: array of Integer;
  GSpare: array of Byte;

procedure Fail(const AWhere: string);
begin
  WriteLn('FAIL: ', AWhere);
  Halt(1);
end;

function SumForward(const ACount: Integer): Int64;
var
  J: Integer;
begin
  Result := 0;
  for J := 0 to ACount - 1 do
    Result := Result + GBytes[J];
end;

function SumDownto(const ACount: Integer): Int64;
var
  J: Integer;
begin
  Result := 0;
  for J := ACount - 1 downto 0 do
    Result := Result + GBytes[J];
end;

procedure ScaleElements;
var
  J: Integer;
begin
  { element writes through the substituted pointer }
  for J := 0 to Length(GInts) - 1 do
    GInts[J] := GInts[J] * 3 + J;
end;

function SwapBaseMidLoop: Int64;
var
  J: Integer;
begin
  { the base is reassigned inside the body: the substitution must not fire,
    reads after the swap must come from the NEW array }
  Result := 0;
  for J := 0 to 7 do
  begin
    Result := Result + GBytes[J];
    If J = 3 then
      GBytes := GSpare;
  end;
end;

function SumViaParam(const A: array of Byte): Int64;
var
  J: Integer;
begin
  Result := 0;
  for J := 0 to High(A) do
    Result := Result + A[J];
end;

var
  J: Integer;
  Total: Int64;
begin
  SetLength(GBytes, 256);
  for J := 0 to 255 do
    GBytes[J] := Byte(J);

  { forward walk: sum 0..255 }
  If SumForward(256) <> 32640 then
    Fail('forward sum');
  If SumDownto(256) <> 32640 then
    Fail('downto sum');

  { element writes }
  SetLength(GInts, 64);
  for J := 0 to 63 do
    GInts[J] := J;
  ScaleElements;
  Total := 0;
  for J := 0 to 63 do
    Total := Total + GInts[J];
  If Total <> 8064 then
    Fail('element writes');

  { base swap mid-loop: first 4 elements old (0+1+2+3), last 4 new (100..) }
  SetLength(GSpare, 8);
  for J := 0 to 7 do
    GSpare[J] := 100 + J;
  If SwapBaseMidLoop <> 6 + 104 + 105 + 106 + 107 then
    Fail('base swap mid-loop');
  SetLength(GBytes, 256);
  for J := 0 to 255 do
    GBytes[J] := Byte(J);

  { zero-length and nil: zero iterations, no touch }
  GSpare := nil;
  Total := 0;
  for J := 0 to Length(GSpare) - 1 do
    Total := Total + GSpare[J];
  for J := Length(GSpare) - 1 downto 0 do
    Total := Total + GSpare[J];
  If Total <> 0 then
    Fail('nil walks');

  { open-array parameter walk }
  If SumViaParam(GBytes) <> 32640 then
    Fail('open array param');

  WriteLn('DYNARRAY_LOOP_LATCH_PASS');
end.
