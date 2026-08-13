program fpc_41317_cmov_int64;

{$mode objfpc}

function Test(A: DWord; B: Int64): Int64;
begin
  while True do
  begin
    if B > 0 then
      B := A;
    Result := B;
    Break;
  end;
end;

var
  V: Int64;
begin
  V := Test(0, -1);
  if V <> -1 then
  begin
    WriteLn('FAIL fpc-41317 value=', V);
    Halt(1);
  end;
  WriteLn('PASS fpc-41317');
end.
