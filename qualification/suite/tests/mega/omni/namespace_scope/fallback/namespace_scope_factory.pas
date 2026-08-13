unit namespace_scope_factory;

interface

uses
  Sample;

function NewMarker: TScopedMarker;

implementation

function NewMarker: TScopedMarker;
begin
  Result := TScopedMarker.Create;
end;

end.
