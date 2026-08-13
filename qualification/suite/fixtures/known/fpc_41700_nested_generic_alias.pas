program Fpc41700NestedGenericAlias;

{$mode objfpc}

type
  TRecord = record
  end;

  generic TAlias<T> = TRecord;

generic procedure Consume<T>();
begin
end;

begin
  specialize Consume<specialize TAlias<Integer>>();
end.
