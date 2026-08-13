program namespace_scope_partial;

uses
  ScopeX.Group.Sample,
  namespace_scope_partial_factory;

var
  Marker: ScopeX.Group.Sample.TPartialMarker;
begin
  Marker := NewPartialMarker;
  Marker.Free;
  WriteLn('NAMESPACE_SCOPE_PARTIAL_PASS');
end.
