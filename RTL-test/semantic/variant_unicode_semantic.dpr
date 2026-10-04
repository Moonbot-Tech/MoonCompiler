program variant_unicode_semantic;
{$mode delphiunicode}
{$define V1_EXPECT_DIRECT}
uses variant_unicode_early_manager, SysUtils, Variants;

type
  TMarkerVariant = class(TCustomVariantType)
    procedure Clear(var V: TVarData); override;
    procedure Copy(var Dest: TVarData; const Source: TVarData; const Indirect: Boolean); override;
    procedure CastTo(var Dest: TVarData; const Source: TVarData; const AVarType: TVarType); override;
  end;

var
  Original: TVariantManager;
  HookCalls, CustomCalls, Checks: Integer;

procedure Check(Value: Boolean; const Name: UnicodeString);
begin
  Inc(Checks);
  if not Value then begin
    WriteLn('FAIL ', Name);
    Halt(1);
  end;
end;

procedure TMarkerVariant.Clear(var V: TVarData);
begin
  V.VType := varEmpty;
end;

procedure TMarkerVariant.Copy(var Dest: TVarData; const Source: TVarData; const Indirect: Boolean);
begin
  Dest := Source;
end;

procedure TMarkerVariant.CastTo(var Dest: TVarData; const Source: TVarData; const AVarType: TVarType);
begin
  Inc(CustomCalls);
  if AVarType = varOleStr then
    VarDataFromOleStr(Dest, 'custom-variant')
  else
    inherited;
end;

procedure Hook(var Dest: WideString; const Value: Variant);
begin
  Inc(HookCalls);
  Dest := 'hooked';
end;

procedure Delegate(var Dest: WideString; const Value: Variant);
begin
  Inc(HookCalls);
  Original.VarToWStr(Dest, Value);
end;

procedure Compare(const V: Variant; const Name: UnicodeString);
var Actual, Expected: UnicodeString;
    Wide: WideString;
begin
  Original.VarToWStr(Wide, V);
  Expected := Wide;
  Actual := UnicodeString(V);
  Check(Actual = Expected, Name);
end;

procedure Test;
var
  V, Nested: Variant;
  O: OleVariant;
  Source, Dest, Shared: UnicodeString;
  W: WideString;
  Ref: TVarData;
  Custom: TVariantManager;
  Marker: TMarkerVariant;
  I: Integer;
  Raised: Boolean;
begin
  Check(EarlyCalls = 1, 'manager before Variants initialization');
  Check(SizeOf(TVariantManager) = 368, 'manager ABI remains 368 bytes');
  for I := 0 to 4 do begin
    case I of
      0: Source := '';
      1: Source := 'ordinary';
      2: Source := 'A'#0'B';
      3: Source := #$D83D#$DE00#$D800;
      4: Source := StringOfChar('x', 4096);
    end;
    V := Source;
    {$ifdef windows}
    Check(VarType(V) = varUString, 'Win64 carrier');
    {$else}
    Check(VarType(V) = varOleStr, 'Linux observable carrier');
    {$endif}
    Compare(V, 'normal read');
    Dest := UnicodeString(V);
    {$if defined(windows) and defined(V1_EXPECT_DIRECT)}
    Check(Pointer(Dest) = TVarData(V).VUString, 'actual direct storage identity');
    {$endif}
    Shared := Dest;
    VarClear(V);
    Check(Dest = Source, 'carrier release preserves result');
    if Dest <> '' then begin
      Dest[1] := 'Q';
      Check(Shared = Source, 'destination COW');
    end;
    V := Source;
    Dest := UnicodeString(V);
    if Source <> '' then Source[1] := 'R';
    Check(UnicodeString(V) = Dest, 'source COW');
  end;
  O := WideString('BSTR'#0'value');
  Dest := UnicodeString(O);
  Check(Dest = 'BSTR'#0'value', 'OleVariant operator');
  Compare(O, 'varOleStr fallback');
  V := 12345;
  Compare(V, 'integer fallback');
  V := True;
  Compare(V, 'boolean fallback');
  V := 1.25;
  Compare(V, 'float fallback');
  V := Unassigned;
  Compare(V, 'empty fallback');
  NullStrictConvert := False;
  V := Null;
  Compare(V, 'Null nonstrict');
  NullStrictConvert := True;
  Raised := False;
  try
    Dest := UnicodeString(V);
  except
    on E: EVariantError do Raised := True;
  end;
  Check(Raised, 'Null strict raises');
  NullStrictConvert := False;

  FillChar(Ref, SizeOf(Ref), 0);
  Source := 'reference';
  Ref.VType := varUString or varByRef;
  Ref.VPointer := @Source;
  Compare(PVariant(@Ref)^, 'UnicodeString byref fallback');
  W := 'wide-reference';
  Ref.VType := varOleStr or varByRef;
  Ref.VPointer := @W;
  Compare(PVariant(@Ref)^, 'WideString byref fallback');
  Nested := Source;
  Ref.VType := varVariant or varByRef;
  Ref.VPointer := @Nested;
  Compare(PVariant(@Ref)^, 'Variant byref fallback');

  V := UnicodeString('payload');
  Custom := Original;
  Custom.VarToWStr := @Hook;
  SetVariantManager(Custom);
  try
    HookCalls := 0;
    Dest := UnicodeString(V);
    Check((Dest = 'hooked') and (HookCalls = 1), 'custom manager hook');
    Dest := UnicodeString(PVariant(@Ref)^);
    Check((Dest = 'hooked') and (HookCalls = 2), 'custom byref hook');
    Custom.VarToWStr := @Delegate;
    SetVariantManager(Custom);
    Dest := UnicodeString(V);
    Check((Dest = 'payload') and (HookCalls = 3), 'delegating custom manager');
  finally
    SetVariantManager(Original);
  end;
  Check(UnicodeString(V) = 'payload', 'restore standard manager');
  Custom := Original;
  Custom.VarToLStr := nil;
  SetVariantManager(Custom);
  try
    Check(UnicodeString(V) = 'payload', 'same reader other manager fields');
  finally
    SetVariantManager(Original);
  end;
  Marker := TMarkerVariant.Create;
  try
    VarClear(V);
    TVarData(V).VType := Marker.VarType;
    CustomCalls := 0;
    Dest := UnicodeString(V);
    Check((Dest = 'custom-variant') and (CustomCalls = 1), 'custom variant CastTo');
    VarClear(V);
  finally
    Marker.Free;
  end;
  WriteLn('V1_CONTRACT_PASS', ' checks=', Checks, ' manager_bytes=', SizeOf(TVariantManager));
end;

begin
  GetVariantManager(Original);
  Test;
end.
