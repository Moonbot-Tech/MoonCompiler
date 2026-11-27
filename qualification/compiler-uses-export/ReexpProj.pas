unit ReexpProj;

{ no uses clause: --project-uses=ReexpBundle gives it the bundle }
{$mode unleashed}

interface

function Q: string;

implementation

function Q: string;
var
  A: TReexpA;
begin
  A.X := 1;
  Result := Who + OnlyA + Chr(Ord('0') + A.X);
end;

end.