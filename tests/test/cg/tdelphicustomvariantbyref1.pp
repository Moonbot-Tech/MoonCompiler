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
  IInterfaceProbe = interface
    ['{97C776A8-7A40-43D3-A5BB-32426D167FBE}']
    function Value: Integer;
  end;

  TInterfaceProbe = class(TInterfacedObject, IInterfaceProbe)
  public
    destructor Destroy; override;
    function Value: Integer;
  end;

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

var
  CopyCount: Integer;
  IndirectCopyCount: Integer;
  InterfaceDeaths: Integer;

destructor TInterfaceProbe.Destroy;
begin
  Inc(InterfaceDeaths);
  inherited Destroy;
end;

function TInterfaceProbe.Value: Integer;
begin
  Result := 73;
end;

procedure TProbeVariantType.Clear(var V: TVarData);
begin
  V.VType := varEmpty;
end;

procedure TProbeVariantType.Copy(var Dest: TVarData; const Source: TVarData;
  const Indirect: Boolean);
begin
  Inc(CopyCount);
  If Indirect then
    Inc(IndirectCopyCount);
  Dest.VType := Source.VType and not varByRef;
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

{$ifdef FPC}
procedure CheckInterfaceSnapshot(const Snapshot: Variant);
var
  Held: IInterfaceProbe;
begin
  Check(VarType(Snapshot) = varUnknown, 30);
  Held := IUnknown(Snapshot) as IInterfaceProbe;
  Check(Held.Value = 73, 31);
end;

procedure CheckCopyNoIndSnapshots;
var
  I: Integer;
  InterfaceSource: IUnknown;
  SourceInt64: Int64;
  SourceInteger: Integer;
  SourceWide: WideString;
  SourceAnsi: AnsiString;
  SourceUnicode: UnicodeString;
  SourceVariant, SourceArray, CopyValue: Variant;
  Reference: TVarData;
begin
  FillChar(Reference, SizeOf(Reference), 0);

  SourceInteger := 42;
  Reference.VType := varInteger or varByRef;
  Reference.VPointer := @SourceInteger;
  VarCopyNoInd(CopyValue, PVariant(@Reference)^);
  SourceInteger := 73;
  Check((VarType(CopyValue) = varInteger) and (Integer(CopyValue) = 42), 20);

  SourceInteger := 51;
  TVarData(CopyValue).VType := varInteger or varByRef;
  TVarData(CopyValue).VPointer := @SourceInteger;
  VarCopyNoInd(CopyValue, CopyValue);
  SourceInteger := 99;
  Check((VarType(CopyValue) = varInteger) and (Integer(CopyValue) = 51), 28);

  InterfaceDeaths := 0;
  InterfaceSource := TInterfaceProbe.Create;
  for I := 1 to 10 do
  begin
    Reference.VType := varInt64 or varByRef;
    Reference.VPointer := @SourceInt64;
    SourceInt64 := 123456789;
    VarCopyNoInd(CopyValue, PVariant(@Reference)^);
    Check(Int64(CopyValue) = 123456789, 29);

    Reference.VType := varUnknown or varByRef;
    Reference.VPointer := @InterfaceSource;
    VarCopyNoInd(CopyValue, PVariant(@Reference)^);
    CheckInterfaceSnapshot(CopyValue);
    VarClear(CopyValue);
  end;
  VarCopyNoInd(CopyValue, PVariant(@Reference)^);
  InterfaceSource := nil;
  Check(InterfaceDeaths = 0, 32);
  VarClear(CopyValue);
  Check(InterfaceDeaths = 1, 33);

  SourceWide := 'wide-before';
  Reference.VType := varOleStr or varByRef;
  Reference.VPointer := @SourceWide;
  VarCopyNoInd(CopyValue, PVariant(@Reference)^);
  SourceWide := 'wide-after';
  Check((VarType(CopyValue) = varOleStr) and
    (WideString(CopyValue) = 'wide-before'), 22);

  SourceAnsi := 'ansi-before';
  Reference.VType := varString or varByRef;
  Reference.VPointer := @SourceAnsi;
  VarCopyNoInd(CopyValue, PVariant(@Reference)^);
  SourceAnsi := 'ansi-after';
  Check((VarType(CopyValue) = varString) and
    (AnsiString(CopyValue) = 'ansi-before'), 21);

  SourceUnicode := 'unicode-before';
  Reference.VType := varUString or varByRef;
  Reference.VPointer := @SourceUnicode;
  VarCopyNoInd(CopyValue, PVariant(@Reference)^);
  SourceUnicode := 'unicode-after';
  Check((VarType(CopyValue) = varUString) and
    (UnicodeString(CopyValue) = 'unicode-before'), 23);

  SourceVariant := Int64(9007199254740993);
  Reference.VType := varVariant or varByRef;
  Reference.VPointer := @TVarData(SourceVariant);
  VarCopyNoInd(CopyValue, PVariant(@Reference)^);
  SourceVariant := Int64(7);
  Check((VarType(CopyValue) = varInt64) and
    (Int64(CopyValue) = 9007199254740993), 24);

  SourceArray := VarArrayOf([Integer(11), Integer(29)]);
  Reference.VType := VarType(SourceArray) or varByRef;
  Reference.VPointer := @TVarData(SourceArray).VArray;
  VarCopyNoInd(CopyValue, PVariant(@Reference)^);
  SourceArray[0] := Integer(99);
  Check((Integer(CopyValue[0]) = 11) and (Integer(CopyValue[1]) = 29), 25);

  SourceArray := VarArrayCreate([0, 1], varInteger);
  SourceArray[0] := Integer(31);
  SourceArray[1] := Integer(47);
  Reference.VType := VarType(SourceArray) or varByRef;
  Reference.VPointer := @TVarData(SourceArray).VArray;
  VarCopyNoInd(CopyValue, PVariant(@Reference)^);
  SourceArray[0] := Integer(101);
  Check((Integer(CopyValue[0]) = 31) and (Integer(CopyValue[1]) = 47), 26);

  Reference.VType := varEmpty;
  VarClear(CopyValue);
  VarClear(SourceArray);
  VarClear(SourceVariant);
end;
{$endif FPC}

var
  Handler: TProbeVariantType;
  Value, Reference1, Reference2, CastValue, CopyValue, NilReference,
    SourceArray: Variant;
  CustomReference: TVarData;
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
  HeapStatus: THeapStatus;
  I: Integer;
{$endif FPC}
begin
{$ifdef FPC}
  CheckCopyNoIndSnapshots;
{$endif FPC}
  Handler := TProbeVariantType.Create;
  try
    TVarData(Value).VType := Handler.VarType;
    VarCopyNoInd(CopyValue, Value);
    Check(VarType(CopyValue) = Handler.VarType, 17);
    FillChar(CustomReference, SizeOf(CustomReference), 0);
    CustomReference.VType := Handler.VarType or varByRef;
    CustomReference.VPointer := @TVarData(Value).VPointer;
    CopyCount := 0;
    IndirectCopyCount := 0;
    VarCopyNoInd(CopyValue, PVariant(@CustomReference)^);
    Check((VarType(CopyValue) = Handler.VarType) and
      (CopyCount = 1) and (IndirectCopyCount = 1), 27);
    CustomReference.VType := varEmpty;

    SourceArray := VarArrayOf([Value, Value]);
    CustomReference.VType := VarType(SourceArray) or varByRef;
    CustomReference.VPointer := @TVarData(SourceArray).VArray;
    CopyCount := 0;
    VarCopyNoInd(CopyValue, PVariant(@CustomReference)^);
    Check(CopyCount = 2, 34);
    CustomReference.VType := varEmpty;
    VarClear(SourceArray);
    VarClear(CopyValue);

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
      HeapStatus := System.GetHeapStatus;
      BeforeHeap := HeapStatus.TotalAllocated;
      for I := 1 to 64 do
      begin
        UnicodeValue := Reference2;
        UnicodeValue := '';
      end;
      HeapStatus := System.GetHeapStatus;
      AfterHeap := HeapStatus.TotalAllocated;
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
