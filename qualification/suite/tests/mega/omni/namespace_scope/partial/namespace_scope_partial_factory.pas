unit namespace_scope_partial_factory;

interface

uses
  Group.Sample;

function NewPartialMarker: TPartialMarker;

implementation

function NewPartialMarker: TPartialMarker;
begin
  Result := TPartialMarker.Create;
end;

end.
