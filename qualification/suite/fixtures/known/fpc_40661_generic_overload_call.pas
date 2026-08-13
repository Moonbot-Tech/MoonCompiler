program test;

generic procedure proc<T>(a: T; b: byte);
begin
end;

generic procedure proc<T>(a: T);
begin
  specialize proc<T>(a, 0);
end;

begin
end.
