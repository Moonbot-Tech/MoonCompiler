program pulse_dictionary;

{$ifndef FPC}
  {$APPTYPE CONSOLE}
{$endif}

{$ifdef FPC}
  {$mode delphi}{$H+}
{$endif}

{$Q-}{$R-}

uses
  {$if defined(FPC) and not defined(PULSE_DEFAULT_MM)}
  mormot.core.fpcx64mm,
  {$ifend}
  SysUtils,
  Generics.Collections,
  pulse_harness in '..\common\pulse_harness.pas';

const
  ShortCount = 100;
  LongCount = 10000;

type
  TUInt64Array = array of UInt64;
  TStringArray = array of UnicodeString;
  TUInt64Dictionary = TDictionary<UInt64, UInt64>;
  TStringKeyDictionary = TDictionary<UnicodeString, UInt64>;
  TStringValueDictionary = TDictionary<UInt64, UnicodeString>;

var
  UInt64Keys: TUInt64Array;
  UInt64Misses: TUInt64Array;
  StringKeys: TStringArray;
  StringMisses: TStringArray;
  StringValues: TStringArray;
  PreparedUInt64Short: TUInt64Dictionary;
  PreparedUInt64Long: TUInt64Dictionary;
  PreparedUInt64LongHalfLoad: TUInt64Dictionary;
  PreparedStringKeyShort: TStringKeyDictionary;
  PreparedStringKeyLong: TStringKeyDictionary;
  PreparedStringValueShort: TStringValueDictionary;
  PreparedStringValueLong: TStringValueDictionary;
  PreparedStringValueLongHalfLoad: TStringValueDictionary;

procedure FillUInt64Dictionary(Dictionary: TUInt64Dictionary; Count: Integer;
  HalfLoad: Boolean = False);
var
  I: Integer;
begin
  {$ifdef FPC}
  if HalfLoad then
    Dictionary.MaxLoadFactor := 0.5;
  {$endif}
  Dictionary.Capacity := Count;
  for I := 0 to Count - 1 do
    Dictionary.Add(UInt64Keys[I], UInt64Keys[I] xor UInt64($D1B54A32D192ED03));
  if HalfLoad and (Dictionary.Capacity <> 32768) then
    raise Exception.CreateFmt('unexpected half-load capacity: %d',
      [Dictionary.Capacity]);
end;

procedure FillStringKeyDictionary(Dictionary: TStringKeyDictionary;
  Count: Integer);
var
  I: Integer;
begin
  Dictionary.Capacity := Count;
  for I := 0 to Count - 1 do
    Dictionary.Add(StringKeys[I], UInt64Keys[I]);
end;

procedure FillStringValueDictionary(Dictionary: TStringValueDictionary;
  Count: Integer; HalfLoad: Boolean = False);
var
  I: Integer;
begin
  {$ifdef FPC}
  if HalfLoad then
    Dictionary.MaxLoadFactor := 0.5;
  {$endif}
  Dictionary.Capacity := Count;
  for I := 0 to Count - 1 do
    Dictionary.Add(UInt64Keys[I], StringValues[I]);
  if HalfLoad and (Dictionary.Capacity <> 32768) then
    raise Exception.CreateFmt('unexpected half-load capacity: %d',
      [Dictionary.Capacity]);
end;

procedure InitializeData;
var
  I: Integer;
begin
  SetLength(UInt64Keys, LongCount);
  SetLength(UInt64Misses, LongCount);
  SetLength(StringKeys, LongCount);
  SetLength(StringMisses, LongCount);
  SetLength(StringValues, LongCount);
  for I := 0 to LongCount - 1 do begin
    UInt64Keys[I] := (UInt64(I + 1) * UInt64($9E3779B97F4A7C15)) and
      UInt64($7FFFFFFFFFFFFFFF);
    UInt64Misses[I] := UInt64Keys[I] or UInt64($8000000000000000);
    StringKeys[I] := 'key-' + IntToHex(UInt64Keys[I], 16);
    StringMisses[I] := 'missing-' + IntToHex(UInt64Keys[I], 16);
    StringValues[I] := 'value-' + IntToHex(UInt64Keys[I], 16);
  end;

  PreparedUInt64Short := TUInt64Dictionary.Create;
  PreparedUInt64Long := TUInt64Dictionary.Create;
  PreparedUInt64LongHalfLoad := TUInt64Dictionary.Create;
  PreparedStringKeyShort := TStringKeyDictionary.Create;
  PreparedStringKeyLong := TStringKeyDictionary.Create;
  PreparedStringValueShort := TStringValueDictionary.Create;
  PreparedStringValueLong := TStringValueDictionary.Create;
  PreparedStringValueLongHalfLoad := TStringValueDictionary.Create;
  FillUInt64Dictionary(PreparedUInt64Short, ShortCount);
  FillUInt64Dictionary(PreparedUInt64Long, LongCount);
  FillUInt64Dictionary(PreparedUInt64LongHalfLoad, LongCount, True);
  FillStringKeyDictionary(PreparedStringKeyShort, ShortCount);
  FillStringKeyDictionary(PreparedStringKeyLong, LongCount);
  FillStringValueDictionary(PreparedStringValueShort, ShortCount);
  FillStringValueDictionary(PreparedStringValueLong, LongCount);
  FillStringValueDictionary(PreparedStringValueLongHalfLoad, LongCount, True);
end;

procedure FinalizeData;
begin
  PreparedStringValueLongHalfLoad.Free;
  PreparedStringValueLong.Free;
  PreparedStringValueShort.Free;
  PreparedStringKeyLong.Free;
  PreparedStringKeyShort.Free;
  PreparedUInt64LongHalfLoad.Free;
  PreparedUInt64Long.Free;
  PreparedUInt64Short.Free;
  Finalize(StringValues);
  Finalize(StringMisses);
  Finalize(StringKeys);
  Finalize(UInt64Misses);
  Finalize(UInt64Keys);
end;

function BuildUInt64(Iterations, Count: Integer; Reserve: Boolean): UInt64;
var
  Dictionary: TUInt64Dictionary;
  I, J: Integer;
begin
  Result := 0;
  for J := 1 to Iterations do begin
    Dictionary := TUInt64Dictionary.Create;
    try
      if Reserve then
        Dictionary.Capacity := Count;
      for I := 0 to Count - 1 do
        Dictionary.Add(UInt64Keys[I], UInt64Keys[I] xor UInt64($D1B54A32D192ED03));
      Result := Result xor UInt64(Dictionary.Count) xor
        Dictionary[UInt64Keys[(J - 1) mod Count]];
    finally
      Dictionary.Free;
    end;
  end;
end;

function LookupUInt64(Iterations, Count: Integer;
  Dictionary: TUInt64Dictionary): UInt64;
var
  I, J: Integer;
  Value: UInt64;
begin
  Result := 0;
  for J := 1 to Iterations do
    for I := 0 to Count - 1 do begin
      if Dictionary.TryGetValue(UInt64Keys[I], Value) then
        Result := Result xor Value;
      if Dictionary.TryGetValue(UInt64Misses[I], Value) then
        Inc(Result);
    end;
  Result := Result xor UInt64(Dictionary.Count);
end;

function LookupUInt64Hits(Iterations, Count: Integer;
  Dictionary: TUInt64Dictionary): UInt64;
var
  I, J: Integer;
  Value: UInt64;
begin
  Result := 0;
  for J := 1 to Iterations do
    for I := 0 to Count - 1 do
      if Dictionary.TryGetValue(UInt64Keys[I], Value) then
        Result := Result xor Value;
  Result := Result xor UInt64(Dictionary.Count);
end;

function LookupUInt64Misses(Iterations, Count: Integer;
  Dictionary: TUInt64Dictionary): UInt64;
var
  I, J: Integer;
  Value: UInt64;
begin
  Result := 0;
  for J := 1 to Iterations do
    for I := 0 to Count - 1 do
      if Dictionary.TryGetValue(UInt64Misses[I], Value) then
        Inc(Result);
  Result := Result xor UInt64(Dictionary.Count);
end;

function ChurnUInt64(Iterations, Count: Integer;
  Dictionary: TUInt64Dictionary): UInt64;
var
  I, J: Integer;
  Value: UInt64;
begin
  for J := 1 to Iterations do begin
    I := 0;
    while I < Count do begin
      Dictionary.Remove(UInt64Keys[I]);
      Inc(I, 2);
    end;
    I := 0;
    while I < Count do begin
      Dictionary.Add(UInt64Keys[I],
        UInt64Keys[I] xor UInt64($D1B54A32D192ED03));
      Inc(I, 2);
    end;
  end;
  Dictionary.TryGetValue(UInt64Keys[Count - 2], Value);
  Result := UInt64(Dictionary.Count) xor Value;
end;

function BuildStringKey(Iterations, Count: Integer; Reserve: Boolean): UInt64;
var
  Dictionary: TStringKeyDictionary;
  I, J: Integer;
begin
  Result := 0;
  for J := 1 to Iterations do begin
    Dictionary := TStringKeyDictionary.Create;
    try
      if Reserve then
        Dictionary.Capacity := Count;
      for I := 0 to Count - 1 do
        Dictionary.Add(StringKeys[I], UInt64Keys[I]);
      Result := Result xor UInt64(Dictionary.Count) xor
        Dictionary[StringKeys[(J - 1) mod Count]];
    finally
      Dictionary.Free;
    end;
  end;
end;

function LookupStringKey(Iterations, Count: Integer;
  Dictionary: TStringKeyDictionary): UInt64;
var
  I, J: Integer;
  Value: UInt64;
begin
  Result := 0;
  for J := 1 to Iterations do
    for I := 0 to Count - 1 do begin
      if Dictionary.TryGetValue(StringKeys[I], Value) then
        Result := Result xor Value;
      if Dictionary.TryGetValue(StringMisses[I], Value) then
        Inc(Result);
    end;
  Result := Result xor UInt64(Dictionary.Count);
end;

function ChurnStringKey(Iterations, Count: Integer;
  Dictionary: TStringKeyDictionary): UInt64;
var
  I, J: Integer;
  Value: UInt64;
begin
  for J := 1 to Iterations do begin
    I := 0;
    while I < Count do begin
      Dictionary.Remove(StringKeys[I]);
      Inc(I, 2);
    end;
    I := 0;
    while I < Count do begin
      Dictionary.Add(StringKeys[I], UInt64Keys[I]);
      Inc(I, 2);
    end;
  end;
  Dictionary.TryGetValue(StringKeys[Count - 2], Value);
  Result := UInt64(Dictionary.Count) xor Value;
end;

function BuildStringValue(Iterations, Count: Integer; Reserve: Boolean): UInt64;
var
  Dictionary: TStringValueDictionary;
  I, J: Integer;
begin
  Result := 0;
  for J := 1 to Iterations do begin
    Dictionary := TStringValueDictionary.Create;
    try
      if Reserve then
        Dictionary.Capacity := Count;
      for I := 0 to Count - 1 do
        Dictionary.Add(UInt64Keys[I], StringValues[I]);
      Result := Result xor UInt64(Dictionary.Count) xor
        UInt64(Length(Dictionary[UInt64Keys[(J - 1) mod Count]]));
    finally
      Dictionary.Free;
    end;
  end;
end;

function LookupStringValue(Iterations, Count: Integer;
  Dictionary: TStringValueDictionary): UInt64;
var
  I, J: Integer;
  Value: UnicodeString;
begin
  Result := 0;
  for J := 1 to Iterations do
    for I := 0 to Count - 1 do begin
      if Dictionary.TryGetValue(UInt64Keys[I], Value) then
        Result := Result xor UInt64(Length(Value));
      if Dictionary.TryGetValue(UInt64Misses[I], Value) then
        Inc(Result);
    end;
  Result := Result xor UInt64(Dictionary.Count);
end;

function LookupStringValueHits(Iterations, Count: Integer;
  Dictionary: TStringValueDictionary): UInt64;
var
  I, J: Integer;
  Value: UnicodeString;
begin
  Result := 0;
  for J := 1 to Iterations do
    for I := 0 to Count - 1 do
      if Dictionary.TryGetValue(UInt64Keys[I], Value) then
        Result := Result xor UInt64(Length(Value));
  Result := Result xor UInt64(Dictionary.Count);
end;

function LookupStringValueMisses(Iterations, Count: Integer;
  Dictionary: TStringValueDictionary): UInt64;
var
  I, J: Integer;
  Value: UnicodeString;
begin
  Result := 0;
  for J := 1 to Iterations do
    for I := 0 to Count - 1 do
      if Dictionary.TryGetValue(UInt64Misses[I], Value) then
        Inc(Result);
  Result := Result xor UInt64(Dictionary.Count);
end;

function ChurnStringValue(Iterations, Count: Integer;
  Dictionary: TStringValueDictionary): UInt64;
var
  I, J: Integer;
  Value: UnicodeString;
begin
  for J := 1 to Iterations do begin
    I := 0;
    while I < Count do begin
      Dictionary.Remove(UInt64Keys[I]);
      Inc(I, 2);
    end;
    I := 0;
    while I < Count do begin
      Dictionary.Add(UInt64Keys[I], StringValues[I]);
      Inc(I, 2);
    end;
  end;
  Dictionary.TryGetValue(UInt64Keys[Count - 2], Value);
  Result := UInt64(Dictionary.Count) xor UInt64(Length(Value));
end;

function CaseUInt64BuildGrow100(Iterations: Integer): UInt64;
begin Result := BuildUInt64(Iterations, ShortCount, False); end;
function CaseUInt64BuildGrow10000(Iterations: Integer): UInt64;
begin Result := BuildUInt64(Iterations, LongCount, False); end;
function CaseUInt64BuildReserved100(Iterations: Integer): UInt64;
begin Result := BuildUInt64(Iterations, ShortCount, True); end;
function CaseUInt64BuildReserved10000(Iterations: Integer): UInt64;
begin Result := BuildUInt64(Iterations, LongCount, True); end;
function CaseUInt64Lookup100(Iterations: Integer): UInt64;
begin Result := LookupUInt64(Iterations, ShortCount, PreparedUInt64Short); end;
function CaseUInt64Lookup10000(Iterations: Integer): UInt64;
begin Result := LookupUInt64(Iterations, LongCount, PreparedUInt64Long); end;
function CaseUInt64LookupHits10000(Iterations: Integer): UInt64;
begin Result := LookupUInt64Hits(Iterations, LongCount, PreparedUInt64Long); end;
function CaseUInt64LookupMisses10000(Iterations: Integer): UInt64;
begin Result := LookupUInt64Misses(Iterations, LongCount, PreparedUInt64Long); end;
function CaseUInt64LookupHalfLoad10000(Iterations: Integer): UInt64;
begin
  Result := LookupUInt64(Iterations, LongCount, PreparedUInt64LongHalfLoad);
end;
function CaseUInt64Churn100(Iterations: Integer): UInt64;
begin Result := ChurnUInt64(Iterations, ShortCount, PreparedUInt64Short); end;
function CaseUInt64Churn10000(Iterations: Integer): UInt64;
begin Result := ChurnUInt64(Iterations, LongCount, PreparedUInt64Long); end;

function CaseStringKeyBuildGrow100(Iterations: Integer): UInt64;
begin Result := BuildStringKey(Iterations, ShortCount, False); end;
function CaseStringKeyBuildGrow10000(Iterations: Integer): UInt64;
begin Result := BuildStringKey(Iterations, LongCount, False); end;
function CaseStringKeyBuildReserved100(Iterations: Integer): UInt64;
begin Result := BuildStringKey(Iterations, ShortCount, True); end;
function CaseStringKeyBuildReserved10000(Iterations: Integer): UInt64;
begin Result := BuildStringKey(Iterations, LongCount, True); end;
function CaseStringKeyLookup100(Iterations: Integer): UInt64;
begin Result := LookupStringKey(Iterations, ShortCount, PreparedStringKeyShort); end;
function CaseStringKeyLookup10000(Iterations: Integer): UInt64;
begin Result := LookupStringKey(Iterations, LongCount, PreparedStringKeyLong); end;
function CaseStringKeyChurn100(Iterations: Integer): UInt64;
begin Result := ChurnStringKey(Iterations, ShortCount, PreparedStringKeyShort); end;
function CaseStringKeyChurn10000(Iterations: Integer): UInt64;
begin Result := ChurnStringKey(Iterations, LongCount, PreparedStringKeyLong); end;

function CaseStringValueBuildGrow100(Iterations: Integer): UInt64;
begin Result := BuildStringValue(Iterations, ShortCount, False); end;
function CaseStringValueBuildGrow10000(Iterations: Integer): UInt64;
begin Result := BuildStringValue(Iterations, LongCount, False); end;
function CaseStringValueBuildReserved100(Iterations: Integer): UInt64;
begin Result := BuildStringValue(Iterations, ShortCount, True); end;
function CaseStringValueBuildReserved10000(Iterations: Integer): UInt64;
begin Result := BuildStringValue(Iterations, LongCount, True); end;
function CaseStringValueLookup100(Iterations: Integer): UInt64;
begin Result := LookupStringValue(Iterations, ShortCount, PreparedStringValueShort); end;
function CaseStringValueLookup10000(Iterations: Integer): UInt64;
begin Result := LookupStringValue(Iterations, LongCount, PreparedStringValueLong); end;
function CaseStringValueLookupHits10000(Iterations: Integer): UInt64;
begin
  Result := LookupStringValueHits(Iterations, LongCount,
    PreparedStringValueLong);
end;
function CaseStringValueLookupMisses10000(Iterations: Integer): UInt64;
begin
  Result := LookupStringValueMisses(Iterations, LongCount,
    PreparedStringValueLong);
end;
function CaseStringValueLookupHalfLoad10000(Iterations: Integer): UInt64;
begin
  Result := LookupStringValue(Iterations, LongCount,
    PreparedStringValueLongHalfLoad);
end;
function CaseStringValueChurn100(Iterations: Integer): UInt64;
begin Result := ChurnStringValue(Iterations, ShortCount, PreparedStringValueShort); end;
function CaseStringValueChurn10000(Iterations: Integer): UInt64;
begin Result := ChurnStringValue(Iterations, LongCount, PreparedStringValueLong); end;

procedure RegisterCases(const Profile: TPulseProfile;
  const SelectedCase: string; var Found: Boolean);
begin
  PulseRunCase('pulse_dictionary', 'u64-u64-build-grow-100', 'rtl+mm',
    'TDictionary<UInt64,UInt64> grow/build, 100 items',
    @CaseUInt64BuildGrow100, ShortCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_dictionary', 'u64-u64-build-grow-10000', 'rtl+mm',
    'TDictionary<UInt64,UInt64> grow/build, 10000 items',
    @CaseUInt64BuildGrow10000, LongCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_dictionary', 'u64-u64-build-reserved-100', 'rtl+mm',
    'TDictionary<UInt64,UInt64> reserved build, 100 items',
    @CaseUInt64BuildReserved100, ShortCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_dictionary', 'u64-u64-build-reserved-10000', 'rtl+mm',
    'TDictionary<UInt64,UInt64> reserved build, 10000 items',
    @CaseUInt64BuildReserved10000, LongCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_dictionary', 'u64-u64-lookup-mixed-100', 'rtl',
    'TDictionary<UInt64,UInt64> hit/miss lookup, 100 items',
    @CaseUInt64Lookup100, ShortCount * 2, Profile, SelectedCase, Found);
  PulseRunCase('pulse_dictionary', 'u64-u64-lookup-mixed-10000', 'rtl',
    'TDictionary<UInt64,UInt64> hit/miss lookup, 10000 items',
    @CaseUInt64Lookup10000, LongCount * 2, Profile, SelectedCase, Found);
  PulseRunCase('pulse_dictionary', 'u64-u64-lookup-hit-10000', 'rtl',
    'TDictionary<UInt64,UInt64> hit-only lookup, 10000 items',
    @CaseUInt64LookupHits10000, LongCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_dictionary', 'u64-u64-lookup-miss-10000', 'rtl',
    'TDictionary<UInt64,UInt64> miss-only lookup, 10000 items',
    @CaseUInt64LookupMisses10000, LongCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_dictionary', 'u64-u64-lookup-halfload-10000', 'rtl',
    'TDictionary<UInt64,UInt64> hit/miss lookup at 10000/32768 load',
    @CaseUInt64LookupHalfLoad10000, LongCount * 2, Profile, SelectedCase,
    Found);
  PulseRunCase('pulse_dictionary', 'u64-u64-churn-100', 'rtl',
    'TDictionary<UInt64,UInt64> remove/reinsert half, 100 items',
    @CaseUInt64Churn100, ShortCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_dictionary', 'u64-u64-churn-10000', 'rtl',
    'TDictionary<UInt64,UInt64> remove/reinsert half, 10000 items',
    @CaseUInt64Churn10000, LongCount, Profile, SelectedCase, Found);

  PulseRunCase('pulse_dictionary', 'string-u64-build-grow-100', 'rtl+mm',
    'TDictionary<UnicodeString,UInt64> grow/build, 100 items',
    @CaseStringKeyBuildGrow100, ShortCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_dictionary', 'string-u64-build-grow-10000', 'rtl+mm',
    'TDictionary<UnicodeString,UInt64> grow/build, 10000 items',
    @CaseStringKeyBuildGrow10000, LongCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_dictionary', 'string-u64-build-reserved-100', 'rtl+mm',
    'TDictionary<UnicodeString,UInt64> reserved build, 100 items',
    @CaseStringKeyBuildReserved100, ShortCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_dictionary', 'string-u64-build-reserved-10000', 'rtl+mm',
    'TDictionary<UnicodeString,UInt64> reserved build, 10000 items',
    @CaseStringKeyBuildReserved10000, LongCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_dictionary', 'string-u64-lookup-mixed-100', 'rtl',
    'TDictionary<UnicodeString,UInt64> hit/miss lookup, 100 items',
    @CaseStringKeyLookup100, ShortCount * 2, Profile, SelectedCase, Found);
  PulseRunCase('pulse_dictionary', 'string-u64-lookup-mixed-10000', 'rtl',
    'TDictionary<UnicodeString,UInt64> hit/miss lookup, 10000 items',
    @CaseStringKeyLookup10000, LongCount * 2, Profile, SelectedCase, Found);
  PulseRunCase('pulse_dictionary', 'string-u64-churn-100', 'rtl+mm',
    'TDictionary<UnicodeString,UInt64> remove/reinsert half, 100 items',
    @CaseStringKeyChurn100, ShortCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_dictionary', 'string-u64-churn-10000', 'rtl+mm',
    'TDictionary<UnicodeString,UInt64> remove/reinsert half, 10000 items',
    @CaseStringKeyChurn10000, LongCount, Profile, SelectedCase, Found);

  PulseRunCase('pulse_dictionary', 'u64-string-build-grow-100', 'rtl+mm',
    'TDictionary<UInt64,UnicodeString> grow/build, 100 items',
    @CaseStringValueBuildGrow100, ShortCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_dictionary', 'u64-string-build-grow-10000', 'rtl+mm',
    'TDictionary<UInt64,UnicodeString> grow/build, 10000 items',
    @CaseStringValueBuildGrow10000, LongCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_dictionary', 'u64-string-build-reserved-100', 'rtl+mm',
    'TDictionary<UInt64,UnicodeString> reserved build, 100 items',
    @CaseStringValueBuildReserved100, ShortCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_dictionary', 'u64-string-build-reserved-10000', 'rtl+mm',
    'TDictionary<UInt64,UnicodeString> reserved build, 10000 items',
    @CaseStringValueBuildReserved10000, LongCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_dictionary', 'u64-string-lookup-mixed-100', 'rtl',
    'TDictionary<UInt64,UnicodeString> hit/miss lookup, 100 items',
    @CaseStringValueLookup100, ShortCount * 2, Profile, SelectedCase, Found);
  PulseRunCase('pulse_dictionary', 'u64-string-lookup-mixed-10000', 'rtl',
    'TDictionary<UInt64,UnicodeString> hit/miss lookup, 10000 items',
    @CaseStringValueLookup10000, LongCount * 2, Profile, SelectedCase, Found);
  PulseRunCase('pulse_dictionary', 'u64-string-lookup-hit-10000', 'rtl',
    'TDictionary<UInt64,UnicodeString> hit-only lookup, 10000 items',
    @CaseStringValueLookupHits10000, LongCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_dictionary', 'u64-string-lookup-miss-10000', 'rtl',
    'TDictionary<UInt64,UnicodeString> miss-only lookup, 10000 items',
    @CaseStringValueLookupMisses10000, LongCount, Profile, SelectedCase,
    Found);
  PulseRunCase('pulse_dictionary', 'u64-string-lookup-halfload-10000', 'rtl',
    'TDictionary<UInt64,UnicodeString> hit/miss lookup at 10000/32768 load',
    @CaseStringValueLookupHalfLoad10000, LongCount * 2, Profile,
    SelectedCase, Found);
  PulseRunCase('pulse_dictionary', 'u64-string-churn-100', 'rtl+mm',
    'TDictionary<UInt64,UnicodeString> remove/reinsert half, 100 items',
    @CaseStringValueChurn100, ShortCount, Profile, SelectedCase, Found);
  PulseRunCase('pulse_dictionary', 'u64-string-churn-10000', 'rtl+mm',
    'TDictionary<UInt64,UnicodeString> remove/reinsert half, 10000 items',
    @CaseStringValueChurn10000, LongCount, Profile, SelectedCase, Found);
end;

procedure Run;
var
  Profile: TPulseProfile;
  SelectedCase: string;
  Found: Boolean;
begin
  PulseInitialize('pulse_dictionary', Profile, SelectedCase);
  InitializeData;
  try
    Found := False;
    RegisterCases(Profile, SelectedCase, Found);
    PulseFinish('pulse_dictionary', SelectedCase, Found);
  finally
    FinalizeData;
  end;
end;

begin
  try
    Run;
  except
    on E: Exception do begin
      WriteLn(ErrOutput, E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
