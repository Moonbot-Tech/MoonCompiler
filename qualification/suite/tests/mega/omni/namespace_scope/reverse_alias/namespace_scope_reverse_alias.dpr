program namespace_scope_reverse_alias;

{$mode delphi}

uses
  AliasTarget,
  ReverseAliasGeneric;

begin
  if AliasTarget.Marker<>37 then
    Halt(1);
  if ScopeX.AliasTarget.Marker<>37 then
    Halt(2);
  if TAliasReader<Integer>.ReadMarker<>37 then
    Halt(3);
  WriteLn('NAMESPACE_SCOPE_REVERSE_ALIAS_PASS');
end.
