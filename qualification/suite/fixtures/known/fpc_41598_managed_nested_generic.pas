program Fpc41598ManagedNestedGeneric;

{$mode objfpc}
{$modeswitch advancedrecords}

type
  generic TManagedType<T> = record
    class operator Initialize(var Value: TManagedType);
    function Test: T;
  end;

class operator TManagedType.Initialize(var Value: TManagedType);
begin
end;

function TManagedType.Test: T;
begin
  Result := Default(T);
end;

type
  TRecord = record
    type
      TUnusedTypeDef = specialize TManagedType<TRecord>;
    var
      FManagedField: array of Integer;
  end;

begin
end.
