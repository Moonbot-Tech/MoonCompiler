{ %FAIL }
program tmoonarrayconstindex1;

{$mode delphi}
{$R-}

type
  TValues = array[2..4] of Integer;

var
  Values: TValues;
begin
  Values[5] := 42;
end.
