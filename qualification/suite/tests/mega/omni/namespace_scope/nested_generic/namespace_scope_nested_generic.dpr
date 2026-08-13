program namespace_scope_nested_generic;

uses
  Collections;

type
  TContainer<T, U> = class(TEnumerable<T>)
  public type
    TEnumerator = class(ScopeX.Collections.TEnumerator<T>);
    TPairType = ScopeX.Collections.TPair<T, U>;
  protected
    function DoGetEnumerator: ScopeX.Collections.TEnumerator<T>; override;
  end;

function TContainer<T, U>.DoGetEnumerator:
  ScopeX.Collections.TEnumerator<T>;
begin
  Result := nil;
end;

var
  PairValue: TContainer<Integer, string>.TPairType;
begin
  PairValue.Key := 42;
  PairValue.Value := 'answer';
  If (PairValue.Key <> 42) or (PairValue.Value <> 'answer') then
    Halt(1);
  WriteLn('NAMESPACE_SCOPE_NESTED_GENERIC_PASS');
end.
