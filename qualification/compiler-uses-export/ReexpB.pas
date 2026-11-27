unit ReexpB;

{$mode unleashed}

interface

type
  TReexpB = class
    function Name: string;
  end;

implementation

function TReexpB.Name: string;
begin
  Result := 'B';
end;

end.