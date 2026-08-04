{ %OPT=-O2 }
{ %NORUN }
program tw41616;

function TestFunc(X: Integer): Integer; inline;
begin
  TestFunc := TestFunc(X + 1);
end;

begin
  WriteLn(TestFunc(5));
end.
