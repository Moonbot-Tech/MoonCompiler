program namespace_scope_alias_case;

{$mode delphi}

uses
  Foo;

begin
  If AliasValue <> 42 then
    Halt(1);
  WriteLn('NAMESPACE_SCOPE_ALIAS_CASE_PASS');
end.
