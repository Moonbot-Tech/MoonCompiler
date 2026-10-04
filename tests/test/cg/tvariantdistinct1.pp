program tvariantdistinct1;

{$mode delphi}

uses
  Variants;

type
  TAlias = type Variant;
  TSecondAlias = type Variant;
  TOleAlias = type OleVariant;
  TDistinctInt64 = type Int64;
  TSecondDistinctInt64 = type TDistinctInt64;
  TCustomVariant = record
    Value: Integer;
    class operator Implicit(const AValue: TCustomVariant): TAlias;
  end;

var
  CustomCalls: Integer;

class operator TCustomVariant.Implicit(const AValue: TCustomVariant): TAlias;
begin
  Inc(CustomCalls);
  Result:=AValue.Value;
end;

function ToVariant(const Value: TAlias): Variant; noinline;
begin
  Result:=Value;
end;

function ToAlias(const Value: Variant): TAlias; noinline;
begin
  Result:=Value;
end;

var
  AliasValue: TAlias;
  SecondAliasValue: TSecondAlias;
  OleAliasValue: TOleAlias;
  Value: Variant;
  OleValue: OleVariant;
  DistinctInt64Value: TSecondDistinctInt64;
  CustomValue: TCustomVariant;
begin
  AliasValue:=42;
  Value:=AliasValue;
  if Integer(Value)<>42 then Halt(1);
  AliasValue:=Value;
  if Integer(ToVariant(AliasValue))<>42 then Halt(2);
  AliasValue:=ToAlias('managed');
  Value:=AliasValue;
  if String(Value)<>'managed' then Halt(3);
  SecondAliasValue:=AliasValue;
  Value:=SecondAliasValue;
  if String(Value)<>'managed' then Halt(7);
  Value:=Variant(AliasValue);
  if String(Value)<>'managed' then Halt(8);

  OleAliasValue:='ole';
  OleValue:=OleAliasValue;
  if String(OleValue)<>'ole' then Halt(4);
  OleAliasValue:=OleValue;
  Value:=OleAliasValue;
  if String(Value)<>'ole' then Halt(5);

  Value:=123;
  OleAliasValue:=Value;
  OleValue:=OleAliasValue;
  if Integer(OleValue)<>123 then Halt(10);

  AliasValue:=Default(TAlias);
  Value:=AliasValue;
  if not VarIsEmpty(Value) then Halt(6);

  Value:=VarArrayCreate([0,1],varInteger);
  Value[0]:=17;
  Value[1]:=29;
  AliasValue:=Value;
  Value:=AliasValue;
  if (Integer(Value[0])<>17) or (Integer(Value[1])<>29) then Halt(9);

  AliasValue:=Int64(9007199254740993);
  DistinctInt64Value:=AliasValue;
  if Int64(DistinctInt64Value)<>9007199254740993 then Halt(11);

  DistinctInt64Value:=-9007199254740993;
  AliasValue:=DistinctInt64Value;
  Value:=AliasValue;
  if Int64(Value)<>-9007199254740993 then Halt(12);

  OleAliasValue:=Int64(High(Int64));
  DistinctInt64Value:=OleAliasValue;
  if Int64(DistinctInt64Value)<>High(Int64) then Halt(13);

  CustomValue.Value:=71;
  AliasValue:=CustomValue;
  if (Integer(AliasValue)<>71) or (CustomCalls<>1) then Halt(14);
end.
