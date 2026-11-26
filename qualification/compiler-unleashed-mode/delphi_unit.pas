unit delphi_unit;

{ A unit in another mode, compiled before the program that uses it. Its
  $MODE directive used to leave FPC_DELPHI/FPC_UNLEASHED changed for the
  modules compiled after it. }
{$mode delphi}

interface

function UnitMode: string;

implementation

function UnitMode: string;
begin
{$if defined(FPC_DELPHI) and not defined(FPC_UNLEASHED)}
  Result := 'delphi';
{$else}
  Result := 'wrong';
{$endif}
end;

end.
