unit fpc_41497_forward_constraint_unit;

{$mode objfpc}

interface

type
  generic TWrapped<T: class> = record
    Field: T;
  end;

generic procedure Test<T: class>(Arg: specialize TWrapped<T>);

implementation

generic procedure Test<T>(Arg: specialize TWrapped<T>);
begin
end;

end.
