program fpc_41811_int64_float_literal;

{$mode delphi}

uses
  Math;

var
  Milliseconds: Int64;
  Actual: Double;
  OracleBits: QWord;
  Oracle: Double absolute OracleBits;
begin
  Milliseconds := 1356062706000;
  Actual := (Milliseconds / 86400000.0) + 25569.0;
  { Exact binary64 encoding of 25569 + 1356062706000 / 86400000.
    A bit oracle avoids exercising any compiler integer-to-float conversion
    while checking the expression under test. }
  OracleBits := QWord($40E426057258BF26);
  if Abs(Actual - Oracle) > 1E-9 then
  begin
    WriteLn('FAIL fpc-41811 actual=', Actual:0:12,
      ' oracle=', Oracle:0:12);
    Halt(1);
  end;
  WriteLn('PASS fpc-41811');
end.
