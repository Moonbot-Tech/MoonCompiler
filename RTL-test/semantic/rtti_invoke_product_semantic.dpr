program rtti_invoke_product_semantic;

{$mode delphi}{$H+}
{$RTTI EXPLICIT METHODS([vcPublic])}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  cwstring,
  {$endif UNIX}
  System.SysUtils,
  System.TypInfo,
  System.Rtti,
  System.JSON.Serializers;

type
  EInvokeProbe = class(Exception);

  TInvokeProbe = class
  private
    FPrefix: string;
  public
    constructor Create(const aPrefix: string; aNumber: Integer);
    function Join(const aSuffix: string; aNumber: Integer): string;
    procedure RaiseProbe;
  end;

  TInvokeRecord = record
    Value: Integer;
    constructor Create(aValue: Integer);
    function Add(aValue: Integer): Integer;
  end;

constructor TInvokeProbe.Create(const aPrefix: string; aNumber: Integer);
begin
  inherited Create;
  FPrefix:=aPrefix+IntToStr(aNumber);
end;

function TInvokeProbe.Join(const aSuffix: string; aNumber: Integer): string;
begin
  Result:=FPrefix+aSuffix+IntToStr(aNumber);
end;

procedure TInvokeProbe.RaiseProbe;
begin
  raise EInvokeProbe.Create('invoke-exception');
end;

constructor TInvokeRecord.Create(aValue: Integer);
begin
  Value:=aValue;
end;

function TInvokeRecord.Add(aValue: Integer): Integer;
begin
  Result:=Value+aValue;
end;

procedure Check(aCondition: Boolean; const aMessage: string);
begin
  if not aCondition then
    raise Exception.Create('RTTI_INVOKE_PRODUCT_FAIL: '+aMessage);
end;

var
  Context: TRttiContext;
  Instance: TInvokeProbe;
  Rec: TInvokeRecord;
  RecValue: TValue;
  RttiType: TRttiType;

begin
  Context:=TRttiContext.Create(False);
  try
    RttiType:=Context.GetType(TypeInfo(TInvokeProbe));
    Instance:=TInvokeProbe(RttiType.GetMethod('Create').Invoke(TValue.Empty,
      ['Moon',7]).AsObject);
    try
      Check(RttiType.GetMethod('Join').Invoke(Instance,
        [UnicodeString('-Ж-'),9]).AsString='Moon7-Ж-9',
        'class constructor/method with managed arguments');
      try
        RttiType.GetMethod('RaiseProbe').Invoke(Instance,[]);
        Check(False,'exception was swallowed');
      except
        on E: EInvokeProbe do
          Check(E.Message='invoke-exception','exception payload');
      end;
    finally
      Instance.Free;
    end;

    Rec:=Default(TInvokeRecord);
    RttiType:=Context.GetType(TypeInfo(TInvokeRecord));
    TValue.Make(@Rec,TypeInfo(TInvokeRecord),RecValue);
    RecValue:=RttiType.GetMethod('Create').Invoke(RecValue,[40]);
    Check(RttiType.GetMethod('Add').Invoke(RecValue,[2]).AsInteger=42,
      'record constructor/method');
  finally
    Context.Free;
  end;
  WriteLn('RTTI_INVOKE_PRODUCT_PASS');
end.
