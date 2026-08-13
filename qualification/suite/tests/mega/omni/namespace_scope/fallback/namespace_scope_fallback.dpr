program namespace_scope_fallback;

uses
  ScopeX.Sample,
  namespace_scope_factory;

var
  Marker: ScopeX.Sample.TScopedMarker;
begin
  Marker := NewMarker;
  Marker.Free;
  WriteLn('NAMESPACE_SCOPE_FALLBACK_PASS');
end.
