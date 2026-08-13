program with_rvalue_write_rejected;

{$mode delphi}

type
  TPoint = record
    X: Integer;
    Y: Integer;
  end;

function MakePoint: TPoint;
begin
  Result.X:=1;
  Result.Y:=2;
end;

begin
  with MakePoint do
    X:=3;
end.
