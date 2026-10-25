unit MappingA;
{$mode delphi}
interface
uses MappingCore;
function IntegerClass: TClass;
function IntegerInfo: Pointer;
function MakeInteger: IValue<Integer>;
implementation
function IntegerClass:TClass;
begin
  Result:=TBox<Integer>;
end;
function IntegerInfo:Pointer;
begin
  Result:=TypeInfo(IValue<Integer>);
end;
function MakeInteger:IValue<Integer>;
begin
  Result:=TBox<Integer>.Create(137);
end;
end.