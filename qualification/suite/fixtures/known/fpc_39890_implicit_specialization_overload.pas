program Project1;

{$mode delphi}
{$modeswitch implicitfunctionspecialization}

procedure Test(V: PByte); overload;
begin
  WriteLn('test');
end;

procedure Test<T>(V: T); overload;
begin
  Test(PByte(@V));
end;

begin
  Test<Int64>(1);
  ReadLn;
end.
