program Fpc41696GenericClassSubprogram;

{$mode objfpc}
{$modeswitch advancedrecords}

type
  TPrefix = record
    const Value = '111';
  end;

  TOperations = class
    generic class function ReadPrefix<P>: String; static;
  end;

generic class function TOperations.ReadPrefix<P>: String;
begin
  Result := P.Value;
end;

generic function Invoke<T; P>: String;
begin
  Result := T.specialize ReadPrefix<P>();
end;

begin
  if specialize Invoke<TOperations, TPrefix>() <> '111' then
    Halt(1);
end.
