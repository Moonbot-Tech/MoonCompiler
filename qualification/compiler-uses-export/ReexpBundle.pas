unit ReexpBundle;

{ "uses export": the units using this one see ReexpA and ReexpB as well.
  Its own Who wins over ReexpA.Who. }
{$mode unleashed}

interface

uses export ReexpA, ReexpB;

function Who: string;

implementation

function Who: string;
begin
  Result := 'bundle';
end;

end.