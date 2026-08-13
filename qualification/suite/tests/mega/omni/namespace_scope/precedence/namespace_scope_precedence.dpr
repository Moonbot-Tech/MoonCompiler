program namespace_scope_precedence;

uses
  ScopeX.Sample,
  namespace_direct_consumer;

begin
  If ScopeX.Sample.Origin <> 1 then
    Halt(1);
  If DirectOrigin <> 2 then
    Halt(2);
  WriteLn('NAMESPACE_SCOPE_PRECEDENCE_PASS');
end.
