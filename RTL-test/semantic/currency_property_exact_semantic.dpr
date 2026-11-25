program currency_property_exact_semantic;

{$APPTYPE CONSOLE}

uses SysUtils, Classes, Rtti;

type
  TLimits = class(TPersistent)
  private
    FValue: Currency;
    function GetDirect: Currency;
    procedure SetDirect(Value: Currency);
  protected
    function GetIndexed(Index: Integer): Currency; virtual;
    procedure SetIndexed(Index: Integer; Value: Currency); virtual;
  published
    property FieldValue: Currency read FValue write FValue;
    property MethodValue: Currency read GetDirect write SetDirect;
    property IndexedValue: Currency index 7 read GetIndexed write SetIndexed;
    property MixedValue: Currency read FValue write SetDirect;
  end;

  TDerivedLimits = class(TLimits)
  protected
    function GetIndexed(Index: Integer): Currency; override;
    procedure SetIndexed(Index: Integer; Value: Currency); override;
  end;

var
  Calls: Integer;

function TLimits.GetDirect: Currency;
begin
  Inc(Calls);
  Result:=FValue;
end;

procedure TLimits.SetDirect(Value: Currency);
begin
  Inc(Calls);
  FValue:=Value;
end;

function TLimits.GetIndexed(Index: Integer): Currency;
begin
  raise Exception.Create('Base getter');
end;

procedure TLimits.SetIndexed(Index: Integer; Value: Currency);
begin
  raise Exception.Create('Base setter');
end;

function TDerivedLimits.GetIndexed(Index: Integer): Currency;
begin
  if Index<>7 then raise Exception.Create('Getter index');
  Result:=GetDirect;
end;

procedure TDerivedLimits.SetIndexed(Index: Integer; Value: Currency);
begin
  if Index<>7 then raise Exception.Create('Setter index');
  SetDirect(Value);
end;

procedure Test(Obj: TLimits; Prop: TRttiProperty; Bits: Int64; ExpectedCalls: Integer);
var
  Amount, Actual: Currency;
  Raw: Int64;
begin
  Calls:=0;
  Move(Bits,Amount,SizeOf(Amount));
  Obj.FieldValue:=Amount;
  Actual:=Prop.GetValue(Obj).AsType<Currency>;
  Move(Actual,Raw,SizeOf(Raw));
  if Raw<>Bits then raise Exception.Create(Prop.Name+' read');
  Bits:=not Bits;
  Move(Bits,Amount,SizeOf(Amount));
  Prop.SetValue(Obj,TValue.From<Currency>(Amount));
  Actual:=Obj.FieldValue;
  Move(Actual,Raw,SizeOf(Raw));
  if Raw<>Bits then raise Exception.Create(Prop.Name+' write');
  if Calls<>ExpectedCalls then raise Exception.Create(Prop.Name+' accessors');
end;

const
  Values: array[0..4] of Int64 = (0, 9007199254740993, -9007199254740993, High(Int64), Low(Int64));
var
  Context: TRttiContext;
  Obj: TLimits;
  Info: TRttiType;
  Bits: Int64;
begin
  Context:=TRttiContext.Create;
  Obj:=TDerivedLimits.Create;
  try
    Info:=Context.GetType(Obj.ClassType);
    for Bits in Values do begin
      Test(Obj,Info.GetProperty('FieldValue'),Bits,0);
      Test(Obj,Info.GetProperty('MethodValue'),Bits,2);
      Test(Obj,Info.GetProperty('IndexedValue'),Bits,2);
      Test(Obj,Info.GetProperty('MixedValue'),Bits,1);
    end;
    Info.GetProperty('FieldValue').SetValue(Obj,TValue.From<Double>(1.25));
    if Obj.FieldValue<>1.25 then raise Exception.Create('Double conversion');
    WriteLn('CURRENCY_PROPERTY_EXACT_PASS');
  finally
    Obj.Free;
    Context.Free;
  end;
end.
