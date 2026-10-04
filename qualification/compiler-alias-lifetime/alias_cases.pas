unit alias_cases;
{$mode delphi}{$H+}{$INLINE ON}
interface
type
  TEnum = (one, two, three);
  TSub = one..two;
  TEnumCopy = type TEnum;
  TEnumChain = type TEnumCopy;
  TRec = record
    Value: LongInt;
    Text: UnicodeString;
  end;
  TRecCopy = type TRec;
  TRecChain = type TRecCopy;
  TValueObject = object
    Value: LongInt;
    function ReadValue: LongInt;
  end;
  TValueCopy = type TValueObject;
  TObj = class
    Value: LongInt;
    function ReadValue: LongInt; virtual;
  end;
  TDerived = class(TObj)
    function ReadValue: LongInt; override;
  end;
  TObjCopy = type TObj;
  TObjChain = type TObjCopy;
  TDerivedCopy = type TDerived;
  TPacked = packed record
    Prefix: Byte;
    Item: TValueCopy;
    Suffix: Byte;
  end;
  TArray = array[0..2] of TValueCopy;
function InlineValue(const Value: TRecChain): LongInt; inline;
implementation
function TObj.ReadValue: LongInt;
begin
  Result:=Value;
end;
function TDerived.ReadValue: LongInt;
begin
  Result:=inherited ReadValue+7;
end;
function TValueObject.ReadValue: LongInt;
begin
  Result:=Value;
end;
function InlineValue(const Value: TRecChain): LongInt;
begin
  Result:=Value.Value+Length(Value.Text);
end;
end.
