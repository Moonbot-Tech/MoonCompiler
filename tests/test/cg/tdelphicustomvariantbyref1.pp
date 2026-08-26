program tdelphicustomvariantbyref1;

{$ifdef FPC}
  {$mode delphiunicode}
{$endif}

uses
{$ifdef FPC}
  SysUtils,
  StrUtils,
  Variants;
{$else}
  System.SysUtils,
  System.StrUtils,
  System.Variants;
{$endif}

type
  TProbeVariantType = class(TCustomVariantType)
  public
    procedure Clear(var V: TVarData); override;
    procedure Copy(var Dest: TVarData; const Source: TVarData;
      const Indirect: Boolean); override;
    procedure CastTo(var Dest: TVarData; const Source: TVarData;
      const AVarType: TVarType); override;
    procedure BinaryOp(var Left: TVarData; const Right: TVarData;
      const Operation: TVarOp); override;
    function CompareOp(const Left, Right: TVarData;
      const Operation: TVarOp): Boolean; override;
  end;

procedure TProbeVariantType.Clear(var V: TVarData);
begin
  V.VType := varEmpty;
end;

procedure TProbeVariantType.Copy(var Dest: TVarData; const Source: TVarData;
  const Indirect: Boolean);
begin
  Dest.VType := Source.VType;
end;

procedure TProbeVariantType.CastTo(var Dest: TVarData;
  const Source: TVarData; const AVarType: TVarType);
begin
  case AVarType of
    varInteger:
      Variant(Dest) := Integer(42);
    varDouble:
      Variant(Dest) := Double(12.5);
    varCurrency:
      Variant(Dest) := Currency(7.25);
    varDate:
      begin
        Dest.VType := varDate;
        Dest.VDate := 45678.5;
      end;
    varBoolean:
      Variant(Dest) := True;
    varString:
      Variant(Dest) := AnsiString('custom-reference');
    varOleStr:
      Variant(Dest) := WideString('custom-reference');
    varUString:
      Variant(Dest) := UnicodeString('custom-reference');
  else
    inherited CastTo(Dest, Source, AVarType);
  end;
end;

procedure TProbeVariantType.BinaryOp(var Left: TVarData;
  const Right: TVarData; const Operation: TVarOp);
begin
  if Operation <> opAdd then
    RaiseInvalidOp;
  Variant(Left) := 42 + Integer(Variant(Right));
end;

function TProbeVariantType.CompareOp(const Left, Right: TVarData;
  const Operation: TVarOp): Boolean;
begin
  if Operation <> opCmpEq then
    RaiseInvalidOp;
  Result := Integer(Variant(Right)) = 42;
end;

procedure SetVariantByRef(const Source: Variant; var Dest: Variant);
begin
  VarClear(Dest);
  TVarData(Dest).VType := varVariant or varByRef;
  TVarData(Dest).VPointer := @TVarData(Source);
end;

procedure Check(Condition: Boolean; ErrorCode: Byte);
begin
  if not Condition then
    Halt(ErrorCode);
end;

procedure ConsumeUnicode(const Value: UnicodeString);
begin
  Check(Value = 'custom-reference', 12);
end;

var
  Handler: TProbeVariantType;
  Value, Reference1, Reference2, CastValue, CopyValue, NilReference: Variant;
  AnsiValue: AnsiString;
  WideValue: WideString;
  UnicodeValue: UnicodeString;
  IntegerValue: Integer;
  DoubleValue: Double;
  CurrencyValue: Currency;
  DateValue: TDateTime;
  BooleanValue, Raised: Boolean;
{$ifdef FPC}
  BeforeHeap, AfterHeap: PtrUInt;
  I: Integer;
{$endif FPC}
begin
  Handler := TProbeVariantType.Create;
  try
    TVarData(Value).VType := Handler.VarType;
    VarCopyNoInd(CopyValue, Value);
    Check(VarType(CopyValue) = Handler.VarType, 17);
    VarCopyNoInd(CopyValue, UnicodeString('copy-value'));
    Check(UnicodeString(CopyValue) = 'copy-value', 18);
    SetVariantByRef(Value, Reference1);
    SetVariantByRef(Reference1, Reference2);
    try
      AnsiValue := Reference2;
      Check(AnsiValue = 'custom-reference', 1);
      WideValue := Reference2;
      Check(WideValue = 'custom-reference', 2);
      UnicodeValue := Reference2;
      Check(UnicodeValue = 'custom-reference', 3);
{$ifdef FPC}
      { The custom handler returns a managed string through a temporary
        TVarData.  Repeated conversions must release that temporary instead
        of leaking one string per call. }
      UnicodeValue := '';
      BeforeHeap := GetHeapStatus.TotalAllocated;
      for I := 1 to 64 do
      begin
        UnicodeValue := Reference2;
        UnicodeValue := '';
      end;
      AfterHeap := GetHeapStatus.TotalAllocated;
      Check(AfterHeap = BeforeHeap, 19);
{$endif FPC}
      ConsumeUnicode(Reference2);
      Check(ContainsText(Reference2, 'REFERENCE'), 4);

      IntegerValue := Reference2;
      Check(IntegerValue = 42, 5);
      DoubleValue := Reference2;
      Check(DoubleValue = 12.5, 6);
      CurrencyValue := Reference2;
      Check(CurrencyValue = 7.25, 7);
      DateValue := Reference2;
      Check(DateValue = 45678.5, 8);
      BooleanValue := Reference2;
      Check(BooleanValue, 9);

      CastValue := VarAsType(Reference2, varOleStr);
      Check(WideString(CastValue) = 'custom-reference', 10);
      CastValue := VarAsType(Reference2, varUString);
      Check(UnicodeString(CastValue) = 'custom-reference', 11);
      CastValue := VarAsType(Reference2, Handler.VarType);
      Check(VarType(CastValue) = Handler.VarType, 14);
      Check(Reference2 = 42, 15);
      CastValue := Reference2 + 8;
      Check(Integer(CastValue) = 50, 16);

      TVarData(NilReference).VType := varVariant or varByRef;
      TVarData(NilReference).VPointer := nil;
      Raised := False;
      try
        UnicodeValue := NilReference;
      except
        on E: EVariantError do
          Raised := True;
      end;
      Check(Raised, 13);
    finally
      TVarData(NilReference).VType := varEmpty;
      VarClear(CopyValue);
      VarClear(CastValue);
      VarClear(Reference2);
      VarClear(Reference1);
      VarClear(Value);
    end;
  finally
    Handler.Free;
  end;
end.
