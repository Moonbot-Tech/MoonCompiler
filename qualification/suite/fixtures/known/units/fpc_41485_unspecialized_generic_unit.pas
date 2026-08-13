unit fpc_41485_unspecialized_generic_unit;

{$mode objfpc}

interface

generic procedure Test1<T>;
procedure Test2(Arg: array of Integer);

implementation

generic procedure Test1<T>;
begin
  Test2([T.Foo]);
end;

procedure Test2(Arg: array of Integer);
begin
end;

end.
