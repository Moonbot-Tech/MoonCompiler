unit InitUnit;

{$mode delphi}

interface

var
  GTouched: Integer;

function Status: string;

implementation

function Status: string;
begin
  if GTouched = 42 then
    Result := 'initialization ran'
  else
    Result := 'NOT initialized (GTouched=' + Chr(48 + GTouched) + ')';
end;

initialization
  GTouched := 42;

finalization
  GTouched := 0;

end.
