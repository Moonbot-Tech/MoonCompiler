program thelpernestedgenericrtti1;

{$mode delphiunicode}
{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}
{$modeswitch inlinevars}

type
  TContainer<T> = class
  public type
    TValue = record
      Data: T;
    end;
    TReader = reference to function(const Value: TValue): T;
    function Make(const Value: T): TValue;
  end;

  TIntValue = TContainer<LongInt>.TValue;

  TIntValueHelper = record helper for TIntValue
    function Read: LongInt;
  end;

function TContainer<T>.Make(const Value: T): TValue;
begin
  Result.Data:=Value;
end;

function TIntValueHelper.Read: LongInt;
begin
  Result:=Self.Data;
end;

var
  Container: TContainer<LongInt>;
  Item: TIntValue;
  Reader: TContainer<LongInt>.TReader;
begin
  Container:=TContainer<LongInt>.Create;
  try
    Item:=Container.Make(73);
    Reader:=function(const Value: TIntValue): LongInt
      begin
        Result:=Value.Read;
      end;
    If Reader(Item)<>73 then
      Halt(1);
  finally
    Container.Free;
  end;
end.
