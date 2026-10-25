program WrongConcrete;
{$mode delphi}
type
  IValue<T> = interface
    function Tag: Integer;
  end;
  TDistinct = type Integer;
  TWrong = class(TInterfacedObject,IValue<Integer>)
    function WrongTag:Integer;
    function IValue<TDistinct>.Tag=WrongTag;
  end;
function TWrong.WrongTag:Integer;
begin
  Result:=29;
end;
begin
end.