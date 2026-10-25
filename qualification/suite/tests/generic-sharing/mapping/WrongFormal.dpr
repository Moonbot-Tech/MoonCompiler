program WrongFormal;
{$mode delphi}
type
  IValue<T> = interface
    function Tag: Integer;
  end;
  TWrong<T:class;U:class> = class(TInterfacedObject,IValue<T>)
    function WrongTag:Integer;
    function IValue<U>.Tag=WrongTag;
  end;
function TWrong<T,U>.WrongTag:Integer;
begin
  Result:=29;
end;
begin
end.