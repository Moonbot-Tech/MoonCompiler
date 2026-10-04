unit cycrel;

{ One half of a unit cycle: uses cyctypes in its interface (the result type of the inline
  function), is used by the implementation of cyctypes.  CYCREL_CHANGED changes nothing but the
  body of a routine, that is the unit's implementation crc. }

{$mode delphi}

interface

uses
  cyctypes;

function Relation(const A, B: Single): TRelation; inline;
function Scaled(const V: Single): Single;

implementation

function Relation(const A, B: Single): TRelation;
begin
  Result := 1;
  If A = B then
    Result := 0
  else If A < B then
    Result := -1;
end;

function Scaled(const V: Single): Single;
begin
{$ifdef CYCREL_CHANGED}
  Result := V * 4;
{$else}
  Result := V * 2;
{$endif}
end;

end.
