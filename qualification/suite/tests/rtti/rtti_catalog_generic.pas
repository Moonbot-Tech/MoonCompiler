unit rtti_catalog_generic;

{$mode delphi}

interface

uses
  TypInfo;

type
  TGenericRecord<T,U> = record
    First: T;
    Second: U;
  end;

  TGenericFactory = class
    class function Make<T>(const Value: T): TGenericRecord<T,Integer>; static;
  end;

  TGenericConsumer<T> = class
    class procedure Consume; static;
  end;

  TConcreteRecord = TGenericRecord<Integer,Integer>;

function ConcreteRecordTypeInfo: PTypeInfo;

implementation

class function TGenericFactory.Make<T>(const Value: T): TGenericRecord<T,Integer>;
begin
  Result.First:=Value;
  Result.Second:=SizeOf(T);
end;

class procedure TGenericConsumer<T>.Consume;
var
  Value: T;
  Pair: TGenericRecord<T,Integer>;
begin
  Pair:=TGenericFactory.Make<T>(Value);
  if Pair.Second<0 then
    Halt(1);
end;

function ConcreteRecordTypeInfo: PTypeInfo;
begin
  Result:=TypeInfo(TConcreteRecord);
end;

end.
