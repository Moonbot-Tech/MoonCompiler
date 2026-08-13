program fpc_41828_captured_rmw;

{$mode objfpc}{$H+}
{$modeswitch functionreferences}
{$modeswitch anonymousfunctions}

type
  TIntFunction = reference to function: LongInt;

function MakeCounter: TIntFunction;
var
  N: LongInt;
begin
  N := 5;
  Result := function: LongInt
    begin
      N := N + 1;
      Result := N;
    end;
end;

var
  Counter: TIntFunction;
  A, B: LongInt;
begin
  Counter := MakeCounter;
  A := Counter();
  B := Counter();
  if (A <> 6) or (B <> 7) then
  begin
    WriteLn('FAIL fpc-41828 values=', A, ',', B);
    Halt(1);
  end;
  WriteLn('PASS fpc-41828');
end.
