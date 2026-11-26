unit unleashed_unit;

{$mode unleashed}

interface

function UnitMode: string;

implementation

function UnitMode: string;
begin
{$if defined(FPC_UNLEASHED) and not defined(FPC_DELPHI)}
  Result := 'unleashed';
{$else}
  Result := 'wrong';
{$endif}
end;

end.
