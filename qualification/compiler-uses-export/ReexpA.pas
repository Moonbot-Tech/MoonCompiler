unit ReexpA;

{ re-exported by ReexpBundle }
{$mode unleashed}

interface

type
  TReexpA = record
    X: Integer;
  end;

function Who: string;
function OnlyA: string;

implementation

function Who: string;
begin
  Result := 'A';
end;

function OnlyA: string;
begin
  Result := 'onlyA';
end;

end.