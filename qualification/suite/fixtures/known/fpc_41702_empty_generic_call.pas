program Fpc41702EmptyGenericCall;

{$mode objfpc}
{$modeswitch advancedrecords}

type
  TOperations = record
    class procedure Invoke(); static;
  end;

class procedure TOperations.Invoke();
begin
end;

generic procedure CallOperation<T>();
begin
  T.Invoke();
end;

begin
  specialize CallOperation<TOperations>();
end.
