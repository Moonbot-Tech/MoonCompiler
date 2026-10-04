program pulse_hot_rtl;

{ Hot RTL corpus: one timed cell per ordinary hot path of the routines listed
  in doc-int/HOT_RTL_ROUTINES_20260914.md.  Every case returns a semantic
  digest; a faster but different result is rejected by the harness.  Where a
  full-cost hand-written reference exists (SameText on Win64) it is measured
  next to the RTL routine on the same inputs. }

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
  {$I ../common/pulse_placement_uses.inc}
  SysUtils,
  Classes,
  StrUtils,
  Math,
  DateUtils,
  Variants,
  SyncObjs,
  Generics.Defaults,
  Generics.Collections,
  pulse_harness in '..\common\pulse_harness.pas';

{$I ../common/pulse_program_prefix.inc}

{$ifdef WIN64}
{$L sametext_pair_astra.obj}
function asm_sametext_pair_content(A, B: PWideChar; N: NativeInt): LongBool; cdecl; external;
{$endif}

const
  InnerCount = 64;
  ListCount = 1024;
  KeyCount = 128;
  MovePagePhase = 320;

type
  TDoubleArray = array of Double;
  TStringArray = array of UnicodeString;
  TInt64Array = array of Int64;
  TBuffer4k = array[0..4095] of Byte;
  PBuffer4k = ^TBuffer4k;
  TBuffer64 = array[0..63] of Byte;

  TPlainObject = class
  end;

  TManagedHolder = class
  public
    F1, F2, F3, F4: UnicodeString;
  end;

  TPulseObject = class
  private
    FValue: UInt64;
  public
    constructor Create(AValue: UInt64);
    function Mix(AValue: UInt64): UInt64; virtual;
  end;

  TInterfacedThing = class(TInterfacedObject)
  end;

var
  Distinct12A, Distinct12B, Fold12, MismatchFirst12, MismatchLast12: UnicodeString;
  { the same keys as 8-bit strings: RawUtf8 = UTF8String in the product }
  AStrA, AStrB, AStrFirst, AStrLast: UTF8String;
  Length13, Fold1A, Fold1B, Fold128A, Fold128B, Equal128A, Equal128B: UnicodeString;
  Short8A, Short8B, Text16, Text32, Text64, Mixed12, Mixed64: UnicodeString;
  Padded16, NoPad16, Replace32, Needle, NeedleMiss, NeedleUpper: UnicodeString;
  Prefix12, Suffix12: UnicodeString;
  MixedLower12, CyrPrefix12, CyrText32, CyrNeedle6: UnicodeString;
  IntText7, Int64Text19, FloatText8, FloatText8Comma: UnicodeString;
  Ascii32, Cyrillic32: UnicodeString;
  Ascii32Utf8, Cyrillic32Utf8: UTF8String;
  Ascii32Bytes, Cyrillic32Bytes: TBytes;
  PosChar: WideChar;
  AnsiPosChar: AnsiChar;
  AnsiText32: UTF8String;
  Keys: array[0..KeyCount - 1] of UnicodeString;
  MissingKeys: array[0..KeyCount - 1] of UnicodeString;
  DoubleData: array[0..255] of Double;
  IntData: array[0..ListCount - 1] of Integer;
  Int64Data: array[0..ListCount - 1] of Int64;
  RandomInts: array[0..ListCount - 1] of Integer;
  SortedInts: array[0..ListCount - 1] of Integer;
  Double64: TDoubleArray;
  MoveBlock: Pointer;          { one heap block: common page phase, Src4k and Dst4k 4096 bytes apart }
  Src4k, Dst4k: PBuffer4k;
  Src64, Dst64: TBuffer64;
  { The objects the cases work on.  Where the stores of a case's calls
    4K-aliased the reload of one of them, the case takes it into a local
    before its loop (check_case_loads.py). }
  IntList: TList<Integer>;
  StrList: TList<UnicodeString>;
  ObjList: TList<TPulseObject>;
  IntDict: TDictionary<Integer, Integer>;
  StrDict: TDictionary<UnicodeString, Integer>;
  Names: TStringList;
  PlainNames: TStringList;
  SortedNames: TStringList;
  MemStream, SourceStream: TMemoryStream;
  MonitorObject: TObject;
  CriticalSection: TCriticalSection;
  Interfaced: TInterfacedThing;
  Plain: TPlainObject;
  FixedDateTime: TDateTime;
  FixedUnix: Int64;
  PulseFormatSettings, PulseCommaSettings: TFormatSettings;
  RuntimeInt3, RuntimeInt10: Integer;
  RuntimeInt64: Int64;
  RuntimeDouble: Double;
  RuntimeBool: Boolean;

constructor TPulseObject.Create(AValue: UInt64);
begin
  inherited Create;
  FValue := AValue;
end;

function TPulseObject.Mix(AValue: UInt64): UInt64;
begin
  Result := (FValue xor AValue) * UInt64($9E3779B185EBCA87);
end;

function RuntimeText(const Prefix: UnicodeString; Value: Integer): UnicodeString;
begin
  Result := Prefix + UnicodeString(IntToStr(Value));
end;

{ Measurement hygiene, not part of any case: a short string's payload is put inside one
  64-byte cache line (a payload of exactly 64 bytes on a line start).  Where the allocator's
  pool puts a 12-byte payload - on byte 8, 24, 40 or 56 of a line - depends on every string
  allocated before it; from byte 56 it straddles two lines, each 8-byte load of a compare is
  a split load, and the case moves by 20% on the Xeon with no change in the measured code.
  The rejected copies stay alive so that their blocks are not handed out again. }
var
  SettleParkingA: array of UTF8String;
  SettleParkingU: array of UnicodeString;

function PayloadFitsLine(P: Pointer; Bytes: NativeInt): Boolean;
begin
  If Bytes >= 64 then
    Result := (NativeUInt(P) and 63) = 0
  else
    Result := NativeInt(NativeUInt(P) and 63) + Bytes <= 64;
end;

procedure SettleInLine(var S: UTF8String); overload;
var
  Attempt: Integer;
begin
  for Attempt := 1 to 16 do
  begin
    If (S = '') or PayloadFitsLine(Pointer(S), Length(S)) then
      Exit;
    SetLength(SettleParkingA, Length(SettleParkingA) + 1);
    SettleParkingA[High(SettleParkingA)] := S;
    S := Copy(S, 1, Length(S));
    UniqueString(AnsiString(S));
  end;
end;

procedure SettleInLine(var S: UnicodeString); overload;
var
  Attempt: Integer;
begin
  for Attempt := 1 to 16 do
  begin
    If (S = '') or PayloadFitsLine(Pointer(S), Length(S) * SizeOf(WideChar)) then
      Exit;
    SetLength(SettleParkingU, Length(SettleParkingU) + 1);
    SettleParkingU[High(SettleParkingU)] := S;
    S := Copy(S, 1, Length(S));
    UniqueString(S);
  end;
end;

function Repeated(const Part: UnicodeString; Count: Integer): UnicodeString;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Count do
    Result := Result + Part;
end;

function DoubleDigest(Value: Double): UInt64; inline;
begin
  Move(Value, Result, SizeOf(Result));
end;

function TextDigest(const Value: UnicodeString): UInt64; inline;
begin
  Result := UInt64(Length(Value));
  If Result > 0 then
    Result := Result * 31 + UInt64(Ord(Value[1])) * 7 + UInt64(Ord(Value[Length(Value)]));
end;

{$ifdef WIN64}
function AsmSameText(const X, Y: UnicodeString): Boolean;
var
  N: NativeInt;
begin
  N := Length(X);
  If N <> Length(Y) then
    Exit(False);
  If Pointer(X) = Pointer(Y) then
    Exit(True);
  Result := asm_sametext_pair_content(Pointer(X), Pointer(Y), N);
end;
{$endif}

{ ---- UnicodeString core ---- }

function CaseUStrAssignShared(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Value: UnicodeString;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      Value := Keys[J and (KeyCount - 1)];
      Result := Result + UInt64(Ord(Value[1]));
    end;
end;

function CaseUStrAssignNil(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Value: UnicodeString;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      Value := Keys[J and (KeyCount - 1)];
      Value := '';
      Result := Result + UInt64(Length(Value)) + 1;
    end;
end;

function CaseUStrUniqueCow16(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Value: UnicodeString;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      Value := Text16;
      Value[1 + (J and 7)] := 'x';
      Result := Result + UInt64(Ord(Value[2]));
    end;
end;

function CaseUStrConcat2Short(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Value: UnicodeString;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      Value := Short8A + Short8B;
      Result := Result + UInt64(Length(Value));
    end;
end;

function CaseUStrConcat3(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Value: UnicodeString;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      Value := Short8A + Short8B + Short8A;
      Result := Result + UInt64(Length(Value));
    end;
end;

function CaseUStrEqualDistinct12(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      If Distinct12A = Distinct12B then
        Inc(Result);
end;

function CaseUStrEqualMismatchLast12(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      If Distinct12A <> MismatchLast12 then
        Inc(Result);
end;

{ 8-bit string keys: equality and ordering through fpc_ansistr_compare_equal
  and fpc_ansistr_compare (the code-page checking helpers every UTF8String
  and RawUtf8 comparison uses) }
function CaseAStrEqualDistinct12(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      If AStrA = AStrB then
        Inc(Result);
end;

function CaseAStrEqualMismatchLast12(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      If AStrA <> AStrLast then
        Inc(Result);
end;

function CaseAStrEqualMismatchFirst12(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      If AStrA <> AStrFirst then
        Inc(Result);
end;

function CaseAStrCompareLess12(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      If AStrA < AStrLast then
        Inc(Result);
end;

function CaseUStrSetLength64(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Value: UnicodeString;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      Value := '';
      SetLength(Value, 64);
      Value[1] := 'a';
      Result := Result + UInt64(Length(Value));
    end;
end;

function CaseUStrCopyMid16(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Value: UnicodeString;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      Value := Copy(Text64, 5 + (J and 3), 16);
      Result := Result + UInt64(Ord(Value[1]));
    end;
end;

function CaseUStrPosCharHit32(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      Result := Result + UInt64(Pos(PosChar, Text32));
end;

function CaseAStrPosCharHit32(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      Result := Result + UInt64(Pos(AnsiPosChar, AnsiText32));
end;

function CaseUStrPosStrHit64(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      Result := Result + UInt64(Pos(Needle, Text64));
end;

{ ---- SameText / CompareText ---- }

function CaseSameTextEqualDistinct12(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      If SameText(Distinct12A, Distinct12B) then
        Inc(Result);
end;

function CaseSameTextFold12(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      If SameText(Distinct12A, Fold12) then
        Inc(Result);
end;

function CaseSameTextMismatchFirst12(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      If not SameText(Distinct12A, MismatchFirst12) then
        Inc(Result);
end;

function CaseSameTextMismatchLast12(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      If not SameText(Distinct12A, MismatchLast12) then
        Inc(Result);
end;

function CaseSameTextLengthDiffer(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      If not SameText(Distinct12A, Length13) then
        Inc(Result);
end;

function CaseSameTextFold1(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      If SameText(Fold1A, Fold1B) then
        Inc(Result);
end;

function CaseSameTextFold128(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      If SameText(Fold128A, Fold128B) then
        Inc(Result);
end;

function CaseSameTextEqual128(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      If SameText(Equal128A, Equal128B) then
        Inc(Result);
end;

{$ifdef WIN64}
function CaseAsmSameTextEqualDistinct12(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      If AsmSameText(Distinct12A, Distinct12B) then
        Inc(Result);
end;

function CaseAsmSameTextFold12(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      If AsmSameText(Distinct12A, Fold12) then
        Inc(Result);
end;

function CaseAsmSameTextMismatchFirst12(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      If not AsmSameText(Distinct12A, MismatchFirst12) then
        Inc(Result);
end;

function CaseAsmSameTextMismatchLast12(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      If not AsmSameText(Distinct12A, MismatchLast12) then
        Inc(Result);
end;

function CaseAsmSameTextLengthDiffer(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      If not AsmSameText(Distinct12A, Length13) then
        Inc(Result);
end;

function CaseAsmSameTextFold1(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      If AsmSameText(Fold1A, Fold1B) then
        Inc(Result);
end;

function CaseAsmSameTextFold128(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      If AsmSameText(Fold128A, Fold128B) then
        Inc(Result);
end;

function CaseAsmSameTextEqual128(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      If AsmSameText(Equal128A, Equal128B) then
        Inc(Result);
end;
{$endif}

function CaseCompareTextEqual12(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      Result := Result + UInt64(CompareText(Distinct12A, Distinct12B) + 1);
end;

function CaseCompareTextFold12(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      Result := Result + UInt64(CompareText(Distinct12A, Fold12) + 1);
end;

{ ---- case, trim, replace, search ---- }

function CaseUpperCase12(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Value: UnicodeString;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      Value := UpperCase(Mixed12);
      Result := Result + UInt64(Ord(Value[3]));
    end;
end;

function CaseLowerCase12(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Value: UnicodeString;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      Value := LowerCase(Mixed12);
      Result := Result + UInt64(Ord(Value[3]));
    end;
end;

function CaseUpperCase64(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Value: UnicodeString;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      Value := UpperCase(Mixed64);
      Result := Result + UInt64(Ord(Value[40]));
    end;
end;

function CaseTrimBoth16(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Value: UnicodeString;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      Value := Trim(Padded16);
      Result := Result + UInt64(Length(Value));
    end;
end;

function CaseTrimNone16(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Value: UnicodeString;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      Value := Trim(NoPad16);
      Result := Result + UInt64(Length(Value));
    end;
end;

function CaseStringReplaceOne32(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Value, Pattern: UnicodeString;
begin
  { A local: Needle sits on the page offset of the MM's own global that every
    GetMem of the result writes, and its reload waited on that store. }
  Pattern := Needle;
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      Value := StringReplace(Replace32, Pattern, Short8A, [rfReplaceAll]);
      Result := Result + UInt64(Length(Value));
    end;
end;

function CaseStringReplaceNone32(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Value: UnicodeString;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      Value := StringReplace(Replace32, NeedleMiss, Short8A, [rfReplaceAll]);
      Result := Result + UInt64(Length(Value));
    end;
end;

function CaseReplaceTextOne32(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Value: UnicodeString;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      Value := ReplaceText(Replace32, NeedleUpper, Short8A);
      Result := Result + UInt64(Length(Value));
    end;
end;

{ no match: what the case-insensitive engine costs before it finds anything }
function CaseReplaceTextNone32(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Value: UnicodeString;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      Value := ReplaceText(Replace32, NeedleMiss, Short8A);
      Result := Result + UInt64(Length(Value));
    end;
end;

{ text outside ASCII: the locale path of the case-insensitive engine }
function CaseReplaceTextCyrillic32(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Value: UnicodeString;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      Value := ReplaceText(CyrText32, CyrNeedle6, Short8A);
      Result := Result + UInt64(Length(Value));
    end;
end;

function CaseContainsTextHit32(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      If ContainsText(Replace32, NeedleUpper) then
        Inc(Result);
end;

function CaseContainsTextMiss32(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      If not ContainsText(Replace32, NeedleMiss) then
        Inc(Result);
end;

function CaseStartsTextHit12(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      If StartsText(Prefix12, Text32) then
        Inc(Result);
end;

function CaseStartsTextHitCyrillic12(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      If StartsText(CyrPrefix12, CyrText32) then
        Inc(Result);
end;

function CaseAnsiSameTextEqual12(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      If AnsiSameText(Mixed12, MixedLower12) then
        Inc(Result);
end;

function CaseEndsTextHit12(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      If EndsText(Suffix12, Text32) then
        Inc(Result);
end;

{ ---- number <-> text ---- }

function CaseIntToStrInt32Small(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      Result := Result + TextDigest(IntToStr(RuntimeInt3 + J));
end;

function CaseIntToStrInt32Ten(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      Result := Result + TextDigest(IntToStr(RuntimeInt10 + J));
end;

function CaseIntToStrInt64Nineteen(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      Result := Result + TextDigest(IntToStr(RuntimeInt64 + J));
end;

function CaseUIntToStrInt64(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      Result := Result + TextDigest(UIntToStr(UInt64(RuntimeInt64) + UInt64(J)));
end;

function CaseIntToHex8(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      Result := Result + TextDigest(IntToHex(RuntimeInt10 + J, 8));
end;

function CaseIntToHex16(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      Result := Result + TextDigest(IntToHex(RuntimeInt64 + J, 16));
end;

function CaseTryStrToInt7(Iterations: Integer): UInt64;
var
  I, J, Value: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      If TryStrToInt(IntText7, Value) then
        Result := Result + UInt64(Value);
end;

function CaseTryStrToInt64Nineteen(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Value: Int64;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      If TryStrToInt64(Int64Text19, Value) then
        Result := Result + UInt64(Value and $FFFF);
end;

function CaseStrToIntDefHit(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      Result := Result + UInt64(StrToIntDef(IntText7, -1));
end;

function CaseTryStrToFloat8(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Value: Double;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      If TryStrToFloat(FloatText8, Value, PulseFormatSettings) then
        Result := Result + UInt64(Trunc(Value));
end;

{ a locale whose decimal separator is a comma: the separator becomes a point
  on the way to the conversion }
function CaseTryStrToFloatComma8(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Value: Double;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      If TryStrToFloat(FloatText8Comma, Value, PulseCommaSettings) then
        Result := Result + UInt64(Trunc(Value));
end;

function CaseStrToFloat8(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      Result := Result + UInt64(Trunc(StrToFloat(FloatText8, PulseFormatSettings)));
end;

function CaseFloatToStr8(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      Result := Result + TextDigest(FloatToStr(RuntimeDouble + J, PulseFormatSettings));
end;

function CaseFloatToStrFFixed2(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      Result := Result + TextDigest(FloatToStrF(RuntimeDouble + J, ffFixed, 15, 2, PulseFormatSettings));
end;

function CaseFormatSD(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      Result := Result + TextDigest(Format('%s=%d', [Short8A, RuntimeInt10 + J]));
end;

function CaseFormatF2(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      Result := Result + TextDigest(Format('%.2f', [RuntimeDouble + J], PulseFormatSettings));
end;

function CaseFormat3Mixed(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      Result := Result + TextDigest(Format('%s %d %.4f', [Short8B, RuntimeInt3 + J, RuntimeDouble], PulseFormatSettings));
end;

function CaseFormatLiteral(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      Result := Result + TextDigest(Format('literal text without arguments', []));
end;

function CaseBoolToStrTrue(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      Result := Result + TextDigest(BoolToStr(RuntimeBool, True));
end;

{ ---- time ---- }

function CaseFormatDateTimeShort(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      Result := Result + TextDigest(FormatDateTime('hh:nn:ss', FixedDateTime));
end;

function CaseFormatDateTimeFull(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      Result := Result + TextDigest(FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', FixedDateTime));
end;

function CaseNow(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      If Now > 0 then
        Inc(Result);
end;

function CaseDate(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      If Date > 0 then
        Inc(Result);
end;

function CaseDateTimeToUnix(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      Result := Result + UInt64(DateTimeToUnix(FixedDateTime + J) and $FFFF);
end;

function CaseUnixToDateTime(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      Result := Result + UInt64(Trunc(UnixToDateTime(FixedUnix + J)));
end;

{ ---- UTF-8 ---- }

function CaseUtf8Encode32Ascii(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Raw: UTF8String;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      Raw := UTF8Encode(Ascii32);
      Result := Result + UInt64(Length(Raw));
    end;
end;

function CaseUtf8ToString32Ascii(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Text: UnicodeString;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      Text := UTF8ToString(Ascii32Utf8);
      Result := Result + UInt64(Length(Text));
    end;
end;

function CaseUtf8Encode32Cyrillic(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Raw: UTF8String;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      Raw := UTF8Encode(Cyrillic32);
      Result := Result + UInt64(Length(Raw));
    end;
end;

function CaseUtf8ToString32Cyrillic(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Text: UnicodeString;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      Text := UTF8ToString(Cyrillic32Utf8);
      Result := Result + UInt64(Length(Text));
    end;
end;

function CaseEncodingGetBytes32(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Bytes: TBytes;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      Bytes := TEncoding.UTF8.GetBytes(Ascii32);
      Result := Result + UInt64(Length(Bytes));
    end;
end;

function CaseEncodingGetString32(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Text: UnicodeString;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      Text := TEncoding.UTF8.GetString(Ascii32Bytes);
      Result := Result + UInt64(Length(Text));
    end;
end;

{ two-byte sequences all the way: the decoder's general path, no ASCII run }
function CaseEncodingGetString32Cyrillic(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Text: UnicodeString;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      Text := TEncoding.UTF8.GetString(Cyrillic32Bytes);
      Result := Result + UInt64(Length(Text));
    end;
end;

{ ---- memory ---- }

function CaseMove16(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      Move(Src4k^[J], Dst4k^[J + 128], 16);
      Result := Result + UInt64(Dst4k^[J + 128]);
    end;
end;

function CaseMove64(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Source, Dest: PBuffer4k;
begin
  Source := Src4k;
  Dest := Dst4k;
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      Move(Source^[J], Dest^[J + 256], 64);
      Result := Result + UInt64(Dest^[J + 256]);
    end;
end;

function CaseMove256(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      Move(Src4k^[J], Dst4k^[J + 512], 256);
      Result := Result + UInt64(Dst4k^[J + 512]);
    end;
end;

function CaseMove4k(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    Move(Src4k^, Dst4k^, SizeOf(TBuffer4k));
    Result := Result + UInt64(Dst4k^[I and 4095]);
  end;
end;

function CaseFillChar64(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      FillChar(Dst4k^[J], 64, J and 255);
      Result := Result + UInt64(Dst4k^[J + 63]);
    end;
end;

function CaseFillChar4k(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    FillChar(Dst4k^, SizeOf(TBuffer4k), I and 255);
    Result := Result + UInt64(Dst4k^[4095]);
  end;
end;

function CaseCompareMem64Equal(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      If CompareMem(@Src64, @Dst64, SizeOf(Src64)) then
        Inc(Result);
end;

function CaseGetMemFreeMem32(Iterations: Integer): UInt64;
var
  I, J: Integer;
  P: Pointer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      GetMem(P, 32);
      PByte(P)^ := J;
      Result := Result + UInt64(PByte(P)^);
      FreeMem(P);
    end;
end;

function CaseGetMemFreeMem256(Iterations: Integer): UInt64;
var
  I, J: Integer;
  P: Pointer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      GetMem(P, 256);
      PByte(P)^ := J;
      Result := Result + UInt64(PByte(P)^);
      FreeMem(P);
    end;
end;

function CaseReallocMemGrow(Iterations: Integer): UInt64;
var
  I, J: Integer;
  P: Pointer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      GetMem(P, 64);
      PByte(P)^ := J;
      ReallocMem(P, 128);
      Result := Result + UInt64(PByte(P)^);
      FreeMem(P);
    end;
end;

function CaseObjectCreateFreePlain(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Instance: TPlainObject;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      Instance := TPlainObject.Create;
      Result := Result + UInt64(Ord(Instance <> nil));
      Instance.Free;
    end;
end;

function CaseObjectCreateFreeManaged(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Instance: TManagedHolder;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      Instance := TManagedHolder.Create;
      Instance.F1 := Keys[J and (KeyCount - 1)];
      Result := Result + UInt64(Length(Instance.F1));
      Instance.Free;
    end;
end;

function CaseDynArraySetLengthDouble64(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Values: TDoubleArray;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      Values := nil;
      SetLength(Values, 64);
      Values[J] := J;
      Result := Result + UInt64(Length(Values));
    end;
end;

function CaseDynArraySetLengthString16(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Values: TStringArray;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      Values := nil;
      SetLength(Values, 16);
      Values[J and 15] := Short8A;
      Result := Result + UInt64(Length(Values[J and 15]));
    end;
end;

function CaseDynArrayCopy64(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Values, Source: TDoubleArray;
begin
  { A local: every copy writes the same block, over the page offset of
    Double64, and its reload waited on those stores. }
  Source := Double64;
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      Values := Copy(Source);
      Result := Result + UInt64(Trunc(Values[J]));
    end;
end;

function CaseDynArrayAssignShare(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Values: TDoubleArray;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      Values := Double64;
      Result := Result + UInt64(Trunc(Values[J]));
      Values := nil;
    end;
end;

{ ---- numeric ---- }

function CaseMaxInt32(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      Result := Result + UInt64(Max(IntData[J], IntData[J + 64]));
end;

function CaseMinInt32(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      Result := Result + UInt64(Min(IntData[J], IntData[J + 64]));
end;

function CaseMaxDouble(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Value: Double;
begin
  Result := 0;
  Value := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      Value := Value + Max(DoubleData[J], DoubleData[J + 64]);
  Result := DoubleDigest(Value);
end;

function CaseMinDouble(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Value: Double;
begin
  Result := 0;
  Value := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      Value := Value + Min(DoubleData[J], DoubleData[J + 64]);
  Result := DoubleDigest(Value);
end;

function CaseSameValueDouble(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      If SameValue(DoubleData[J], DoubleData[J + 1]) then
        Inc(Result);
end;

function CaseEnsureRangeInt(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      Result := Result + UInt64(EnsureRange(IntData[J], 100, 100000));
end;

function CaseInRangeInt(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      If InRange(IntData[J], 100, 100000) then
        Inc(Result);
end;

function CaseRandomInt(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  RandSeed := 12345;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      If Random(1000) < 1000 then
        Inc(Result);
end;

function CaseRandomDouble(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  RandSeed := 12345;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      If Random < 1.0 then
        Inc(Result);
end;

function CaseCeilDouble(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      Result := Result + UInt64(Ceil(DoubleData[J]));
end;

function CaseFloorDouble(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      Result := Result + UInt64(Floor(DoubleData[J]));
end;

{ ---- collections ---- }

function CaseListIntAdd1kReuse(Iterations: Integer): UInt64;
var
  I, J: Integer;
  List: TList<Integer>;
begin
  List := IntList;
  Result := 0;
  for I := 1 to Iterations do
  begin
    List.Clear;
    for J := 0 to ListCount - 1 do
      List.Add(IntData[J]);
    Result := Result + UInt64(List.Count);
  end;
end;

function CaseListIntItemsSum1k(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to ListCount - 1 do
      Result := Result + UInt64(IntList[J]);
end;

function CaseListIntIndexOfHitMid(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    Result := Result + UInt64(IntList.IndexOf(IntData[512]));
end;

function CaseListIntContainsMiss(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    If not IntList.Contains(-7) then
      Inc(Result);
end;

function CaseListIntForIn1k(Iterations: Integer): UInt64;
var
  I: Integer;
  Value: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for Value in IntList do
      Result := Result + UInt64(Value);
end;

function CaseListIntDeleteInsertMid(Iterations: Integer): UInt64;
var
  I: Integer;
  Value: Integer;
  List: TList<Integer>;
begin
  List := IntList;
  Result := 0;
  for I := 1 to Iterations do
  begin
    Value := List[512];
    List.Delete(512);
    List.Insert(512, Value);
    Result := Result + UInt64(List.Count);
  end;
end;

function CaseListIntSort1k(Iterations: Integer): UInt64;
var
  I, J: Integer;
  List: TList<Integer>;
begin
  List := IntList;
  Result := 0;
  for I := 1 to Iterations do
  begin
    List.Clear;
    for J := 0 to ListCount - 1 do
      List.Add(RandomInts[J]);
    List.Sort;
    Result := Result + UInt64(List[0]) + UInt64(List[ListCount - 1]);
  end;
end;

function CaseListStringAdd256Reuse(Iterations: Integer): UInt64;
var
  I, J: Integer;
  List: TList<UnicodeString>;
begin
  List := StrList;
  Result := 0;
  for I := 1 to Iterations do
  begin
    List.Clear;
    for J := 0 to 255 do
      List.Add(Keys[J and (KeyCount - 1)]);
    Result := Result + UInt64(List.Count);
  end;
end;

function CaseListObjForIn256(Iterations: Integer): UInt64;
var
  I: Integer;
  Item: TPulseObject;
begin
  Result := 0;
  for I := 1 to Iterations do
    for Item in ObjList do
      Result := Result + Item.Mix(UInt64(I));
end;

function CaseArraySortInt64_1k(Iterations: Integer): UInt64;
var
  I: Integer;
  Values: TInt64Array;
begin
  Result := 0;
  SetLength(Values, ListCount);
  for I := 1 to Iterations do
  begin
    Move(Int64Data, Values[0], ListCount * SizeOf(Int64));
    TArray.Sort<Int64>(Values);
    Result := Result + UInt64(Values[0]) + UInt64(Values[ListCount - 1]);
  end;
end;

function CaseArrayBinarySearchInt1k(Iterations: Integer): UInt64;
var
  I, J, Index: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      If TArray.BinarySearch<Integer>(SortedInts, SortedInts[(J * 16) and (ListCount - 1)], Index) then
        Result := Result + UInt64(Index);
end;

function CaseDictIntTryGetValueHit(Iterations: Integer): UInt64;
var
  I, J, Value: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      If IntDict.TryGetValue(IntData[(J * 16) and (ListCount - 1)], Value) then
        Result := Result + UInt64(Value);
end;

function CaseDictIntTryGetValueMiss(Iterations: Integer): UInt64;
var
  I, J, Value: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      If not IntDict.TryGetValue(-1 - J, Value) then
        Inc(Result);
end;

function CaseDictStrTryGetValueHit(Iterations: Integer): UInt64;
var
  I, J, Value: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      If StrDict.TryGetValue(Keys[J and (KeyCount - 1)], Value) then
        Result := Result + UInt64(Value);
end;

function CaseDictStrContainsKeyMiss(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      If not StrDict.ContainsKey(MissingKeys[J and (KeyCount - 1)]) then
        Inc(Result);
end;

function CaseDictIntAddOrSetExisting(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      IntDict.AddOrSetValue(IntData[J], J);
      Inc(Result);
    end;
end;

function CaseDictStrAddRemoveChurn(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Dictionary: TDictionary<UnicodeString, Integer>;
begin
  Dictionary := StrDict;
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      Dictionary.Add(MissingKeys[J], J);
      Dictionary.Remove(MissingKeys[J]);
      Inc(Result);
    end;
end;

function CaseStringListAdd128Reuse(Iterations: Integer): UInt64;
var
  I, J: Integer;
  List: TStringList;
begin
  List := Names;
  Result := 0;
  for I := 1 to Iterations do
  begin
    List.Clear;
    for J := 0 to KeyCount - 1 do
      List.Add(Keys[J]);
    Result := Result + UInt64(List.Count);
  end;
end;

function CaseStringListIndexOfHit(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      Result := Result + UInt64(PlainNames.IndexOf(Keys[(J * 3) and (KeyCount - 1)]));
end;

function CaseStringListIndexOfMiss128(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    Result := Result + UInt64(PlainNames.IndexOf(MissingKeys[I and (KeyCount - 1)]) + 2);
end;

function CaseStringListIndexOfNameHit(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      Result := Result + UInt64(Names.IndexOfName(Keys[(J * 3) and (KeyCount - 1)]));
end;

function CaseStringListValuesHit(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      Result := Result + UInt64(Length(Names.Values[Keys[(J * 3) and (KeyCount - 1)]]));
end;

function CaseStringListSortedFind(Iterations: Integer): UInt64;
var
  I, J, Index: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      If SortedNames.Find(Keys[(J * 3) and (KeyCount - 1)], Index) then
        Result := Result + UInt64(Index);
end;

{ ---- streams ---- }

function CaseMemStreamWrite16(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Stream: TMemoryStream;
begin
  Stream := MemStream;
  Result := 0;
  for I := 1 to Iterations do
  begin
    Stream.Position := 0;
    for J := 0 to InnerCount - 1 do
      Result := Result + UInt64(Stream.Write(Src64, 16));
  end;
end;

function CaseMemStreamWrite4k(Iterations: Integer): UInt64;
var
  I: Integer;
  Stream: TMemoryStream;
  Source: PBuffer4k;
begin
  Stream := MemStream;
  Source := Src4k;
  Result := 0;
  for I := 1 to Iterations do
  begin
    Stream.Position := 0;
    Result := Result + UInt64(Stream.Write(Source^, SizeOf(TBuffer4k)));
  end;
end;

function CaseMemStreamRead16(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    MemStream.Position := 0;
    for J := 0 to InnerCount - 1 do
      Result := Result + UInt64(MemStream.Read(Dst64, 16));
  end;
end;

function CaseMemStreamSeekPosition(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      MemStream.Position := J * 16;
      Result := Result + UInt64(MemStream.Position);
    end;
end;

function CaseMemStreamCopyFrom4k(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    SourceStream.Position := 0;
    MemStream.Position := 0;
    Result := Result + UInt64(MemStream.CopyFrom(SourceStream, SizeOf(TBuffer4k)));
  end;
end;

function CaseMemStreamSetSizeReuse(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      MemStream.SetSize(Int64(1024 + (J and 3) * 256));
      Result := Result + UInt64(MemStream.Size);
    end;
end;

{ ---- synchronization ---- }

function CaseMonitorEnterExit(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      TMonitor.Enter(MonitorObject);
      Inc(Result);
      TMonitor.Exit(MonitorObject);
    end;
end;

function CaseCriticalSectionEnterLeave(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      CriticalSection.Enter;
      Inc(Result);
      CriticalSection.Leave;
    end;
end;

{ ---- Variant and interfaces ---- }

function CaseVariantAssignInt(Iterations: Integer): UInt64;
var
  I, J: Integer;
  V: Variant;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      V := IntData[J];
      Result := Result + UInt64(Integer(V));
    end;
end;

function CaseVariantAssignString(Iterations: Integer): UInt64;
var
  I, J: Integer;
  V: Variant;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      V := Keys[J and (KeyCount - 1)];
      Result := Result + UInt64(Length(UnicodeString(V)));
    end;
end;

function CaseVariantToStrInt(Iterations: Integer): UInt64;
var
  I, J: Integer;
  V: Variant;
begin
  Result := 0;
  V := RuntimeInt10;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      Result := Result + TextDigest(VarToStr(V));
end;

function CaseVariantIsNull(Iterations: Integer): UInt64;
var
  I, J: Integer;
  V: Variant;
begin
  Result := 0;
  V := RuntimeInt10;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      If not VarIsNull(V) then
        Inc(Result);
end;

function CaseSupportsHit(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Intf: IInterface;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
    begin
      If Supports(Interfaced, IInterface, Intf) then
        Inc(Result);
      Intf := nil;
    end;
end;

function CaseSupportsMiss(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Intf: IInterface;
begin
  Result := 0;
  for I := 1 to Iterations do
    for J := 0 to InnerCount - 1 do
      If not Supports(Plain, IInterface, Intf) then
        Inc(Result);
end;

{ ---- program-internal placement filler: shifts the program's own code and
  the linked ASM object without touching the RTL ---- }

{$if defined(PULSE_PROGRAM_FILLER_1) or defined(PULSE_PROGRAM_FILLER_2) or defined(PULSE_PROGRAM_FILLER_3)}
var
  ProgramFillerKeep: array[0..2] of Pointer;
function ProgramFiller0(X: Int64): Int64; begin Result := X * 3 + 1; end;
{$endif}
{$if defined(PULSE_PROGRAM_FILLER_2) or defined(PULSE_PROGRAM_FILLER_3)}
function ProgramFiller1(X: Int64): Int64; begin Result := X * 5 + 2; end;
{$endif}
{$if defined(PULSE_PROGRAM_FILLER_3)}
function ProgramFiller2(X: Int64): Int64; begin Result := X * 7 + 3; end;
{$endif}

{ ---- data ---- }

procedure InitializeData;
var
  I: Integer;
  State: Cardinal;
begin
  PulseFormatSettings := TFormatSettings.Create;
  PulseFormatSettings.DecimalSeparator := '.';
  PulseCommaSettings := TFormatSettings.Create;
  PulseCommaSettings.DecimalSeparator := ',';
  PulseCommaSettings.ThousandSeparator := ' ';
  Distinct12A := RuntimeText('Market-', 12345);
  Distinct12B := RuntimeText('Market-', 12345);
  Fold12 := RuntimeText('market-', 12345);
  MismatchFirst12 := RuntimeText('Xarket-', 12345);
  MismatchLast12 := RuntimeText('Market-', 12346);
  AStrA := UTF8String(Distinct12A);
  AStrB := UTF8String(Distinct12B);
  AStrFirst := UTF8String(MismatchFirst12);
  AStrLast := UTF8String(MismatchLast12);
  Length13 := RuntimeText('Market-', 123456);
  Fold1A := UnicodeString(Chr(Ord('a') + (Length(Distinct12A) and 7)));
  Fold1B := UpperCase(Fold1A);
  Fold128A := Repeated(RuntimeText('Abcd', 1234), 16);
  Fold128B := LowerCase(Fold128A);
  Equal128A := Repeated(RuntimeText('Abcd', 5678), 16);
  Equal128B := Repeated(RuntimeText('Abcd', 5678), 16);
  Short8A := RuntimeText('sym', 12345);
  Short8B := RuntimeText('qty', 67890);
  Text16 := RuntimeText('field-value', 12345);
  Prefix12 := RuntimeText('Prefix-', 12345);
  Suffix12 := RuntimeText('Suffix-', 54321);
  Text32 := Prefix12 + RuntimeText('mid-x', 123) + Suffix12;
  If Length(Text32) <> 32 then
    raise Exception.Create('Text32 length');
  Text64 := Repeated(RuntimeText('block-', 12), 7) + RuntimeText('needle', 12);
  If Length(Text64) <> 64 then
    raise Exception.Create('Text64 length');
  Needle := Copy(Text64, 57, 6);
  NeedleMiss := RuntimeText('zz', 9);
  Mixed12 := RuntimeText('MiXeD-CaSe', 12);
  Mixed64 := Repeated(Mixed12, 5) + RuntimeText('Ab', 12);
  MixedLower12 := LowerCase(Mixed12);
  { Cyrillic text built from code points (no non-ASCII literal in the
    source): the locale path of the case-insensitive routines }
  CyrPrefix12 := '';
  for I := 0 to 11 do
    CyrPrefix12 := CyrPrefix12 + WideChar($0410 + ((I * 5) mod 32));
  CyrText32 := CyrPrefix12;
  for I := 0 to 19 do
    CyrText32 := CyrText32 + WideChar($0430 + ((I * 7) mod 32));
  If (Length(CyrPrefix12) <> 12) or (Length(CyrText32) <> 32) then
    raise Exception.Create('Cyrillic text length');
  { the first six letters of CyrPrefix12 in lower case }
  CyrNeedle6 := '';
  for I := 0 to 5 do
    CyrNeedle6 := CyrNeedle6 + WideChar($0430 + ((I * 5) mod 32));
  { see SettleInLine: the operands of the short compare and search cases }
  SettleInLine(Distinct12A); SettleInLine(Distinct12B); SettleInLine(Fold12);
  SettleInLine(MismatchFirst12); SettleInLine(MismatchLast12); SettleInLine(Length13);
  SettleInLine(AStrA); SettleInLine(AStrB); SettleInLine(AStrFirst); SettleInLine(AStrLast);
  SettleInLine(Short8A); SettleInLine(Short8B); SettleInLine(Text16);
  SettleInLine(Prefix12); SettleInLine(Suffix12); SettleInLine(Text32);
  SettleInLine(Mixed12); SettleInLine(MixedLower12); SettleInLine(CyrPrefix12); SettleInLine(CyrText32);
  Padded16 := UnicodeString('   ') + RuntimeText('trimmed', 12) + UnicodeString('  ');
  NoPad16 := RuntimeText('untrimmed-', 123456);
  Replace32 := RuntimeText('head-', 12345) + Needle + Repeated(RuntimeText('x', 1), 8);
  If Length(Replace32) <> 32 then
    raise Exception.Create('Replace32 length');
  NeedleUpper := UpperCase(Needle);
  PosChar := Text32[20];
  AnsiText32 := UTF8String(Text32);
  SettleInLine(AnsiText32);
  AnsiPosChar := AnsiText32[20];
  IntText7 := IntToStr(1234567);
  Int64Text19 := IntToStr(Int64(1234567890123456789));
  FloatText8 := UnicodeString('12345.') + IntToStr(678);
  FloatText8Comma := UnicodeString('12345,') + IntToStr(678);
  Ascii32 := Repeated(RuntimeText('ab', 12), 8);
  Cyrillic32 := Repeated(UnicodeString(#$0430#$0431#$0432#$0433), 8);
  Ascii32Utf8 := UTF8Encode(Ascii32);
  Cyrillic32Utf8 := UTF8Encode(Cyrillic32);
  Ascii32Bytes := TEncoding.UTF8.GetBytes(Ascii32);
  Cyrillic32Bytes := TEncoding.UTF8.GetBytes(Cyrillic32);
  for I := 0 to KeyCount - 1 do
  begin
    Keys[I] := RuntimeText('key-', 10000 + I);
    MissingKeys[I] := RuntimeText('miss-', 20000 + I);
  end;
  State := 4201;
  for I := 0 to High(DoubleData) do
  begin
    State := State * 1664525 + 1013904223;
    DoubleData[I] := (State shr 8) / 65536.0 + 0.25;
  end;
  for I := 0 to ListCount - 1 do
  begin
    IntData[I] := I * 17 + 29;
    Int64Data[I] := Int64(ListCount - I) * 1000003;
    SortedInts[I] := I * 3;
    State := State * 1664525 + 1013904223;
    RandomInts[I] := Integer(State shr 4);
  end;
  SetLength(Double64, 64);
  for I := 0 to 63 do
    Double64[I] := I * 1.5;
  { Match page geometry across allocators. Cache-line alignment alone can
    accidentally compare a page-crossing copy with an ordinary copy. }
  GetMem(MoveBlock, 4 * SizeOf(TBuffer4k));
  Src4k := PBuffer4k(((NativeUInt(MoveBlock) + 4095) and not NativeUInt(4095)) + MovePagePhase);
  Dst4k := PBuffer4k(PByte(Src4k) + SizeOf(TBuffer4k));
  for I := 0 to High(TBuffer4k) do
    Src4k^[I] := Byte(I * 17 + 29);
  FillChar(Dst4k^, SizeOf(TBuffer4k), 0);
  for I := 0 to High(Src64) do
  begin
    Src64[I] := Byte(I * 7 + 3);
    Dst64[I] := Src64[I];
  end;
  IntList := TList<Integer>.Create;
  for I := 0 to ListCount - 1 do
    IntList.Add(IntData[I]);
  StrList := TList<UnicodeString>.Create;
  ObjList := TList<TPulseObject>.Create;
  for I := 0 to 255 do
    ObjList.Add(TPulseObject.Create(UInt64(I) * 7919));
  IntDict := TDictionary<Integer, Integer>.Create;
  for I := 0 to ListCount - 1 do
    IntDict.Add(IntData[I], I);
  StrDict := TDictionary<UnicodeString, Integer>.Create;
  for I := 0 to KeyCount - 1 do
    StrDict.Add(Keys[I], I);
  Names := TStringList.Create;
  for I := 0 to KeyCount - 1 do
    Names.Add(Keys[I] + UnicodeString('=') + MissingKeys[I]);
  PlainNames := TStringList.Create;
  for I := 0 to KeyCount - 1 do
    PlainNames.Add(Keys[I]);
  SortedNames := TStringList.Create;
  SortedNames.Sorted := True;
  for I := 0 to KeyCount - 1 do
    SortedNames.Add(Keys[I]);
  MemStream := TMemoryStream.Create;
  MemStream.SetSize(Int64(65536));
  SourceStream := TMemoryStream.Create;
  SourceStream.Write(Src4k^, SizeOf(TBuffer4k));
  MonitorObject := TObject.Create;
  CriticalSection := TCriticalSection.Create;
  Interfaced := TInterfacedThing.Create;
  Interfaced._AddRef;
  Plain := TPlainObject.Create;
  FixedDateTime := EncodeDateTime(2026, 9, 14, 12, 34, 56, 0);
  FixedUnix := DateTimeToUnix(FixedDateTime);
  RuntimeInt3 := 100 + (Length(Distinct12A) and 1);
  RuntimeInt10 := 1234567890 - (Length(Distinct12A) and 1);
  RuntimeInt64 := Int64(1234567890123456789) - (Length(Distinct12A) and 1);
  RuntimeDouble := 12345.678 + (Length(Distinct12A) and 1);
  RuntimeBool := Length(Distinct12A) = 12;
  {$if defined(PULSE_PROGRAM_FILLER_1) or defined(PULSE_PROGRAM_FILLER_2) or defined(PULSE_PROGRAM_FILLER_3)}
  ProgramFillerKeep[0] := @ProgramFiller0;
  {$endif}
  {$if defined(PULSE_PROGRAM_FILLER_2) or defined(PULSE_PROGRAM_FILLER_3)}
  ProgramFillerKeep[1] := @ProgramFiller1;
  {$endif}
  {$if defined(PULSE_PROGRAM_FILLER_3)}
  ProgramFillerKeep[2] := @ProgramFiller2;
  {$endif}
  If GetEnvironmentVariable('PULSE_HOT_RTL_ADDR') <> '' then
    WriteLn(ErrOutput, 'ADDR Distinct12A=', IntToHex(NativeUInt(Pointer(Distinct12A)), 16),
      ' Distinct12B=', IntToHex(NativeUInt(Pointer(Distinct12B)), 16),
      ' Fold12=', IntToHex(NativeUInt(Pointer(Fold12)), 16),
      ' Equal128A=', IntToHex(NativeUInt(Pointer(Equal128A)), 16),
      ' Equal128B=', IntToHex(NativeUInt(Pointer(Equal128B)), 16),
      ' Fold128B=', IntToHex(NativeUInt(Pointer(Fold128B)), 16),
      ' stack=', IntToHex(NativeUInt(@State), 16));
end;

var
  Profile: TPulseProfile;
  SelectedCase: string;
  Found: Boolean;

begin
  InitializeData;
  {$ifdef PULSE_PROGRAM_PREFIX}PulseProgramPrefix;{$endif}
  PulseInitialize('pulse_hot-rtl', Profile, SelectedCase);
  Found := False;
  try
    PulseRunCase('pulse_hot-rtl', 'ustr-assign-shared', 'rtl', 'UnicodeString', @CaseUStrAssignShared, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'ustr-assign-nil', 'rtl', 'UnicodeString', @CaseUStrAssignNil, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'ustr-unique-cow-16', 'rtl', 'UnicodeString', @CaseUStrUniqueCow16, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'ustr-concat-2-short', 'rtl+mm', 'UnicodeString', @CaseUStrConcat2Short, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'ustr-concat-3', 'rtl+mm', 'UnicodeString', @CaseUStrConcat3, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'ustr-equal-distinct-12', 'rtl', 'UnicodeString', @CaseUStrEqualDistinct12, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'ustr-equal-mismatch-last-12', 'rtl', 'UnicodeString', @CaseUStrEqualMismatchLast12, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'astr-equal-distinct-12', 'rtl', 'UTF8String', @CaseAStrEqualDistinct12, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'astr-equal-mismatch-last-12', 'rtl', 'UTF8String', @CaseAStrEqualMismatchLast12, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'astr-equal-mismatch-first-12', 'rtl', 'UTF8String', @CaseAStrEqualMismatchFirst12, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'astr-compare-less-12', 'rtl', 'UTF8String', @CaseAStrCompareLess12, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'ustr-setlength-64', 'rtl+mm', 'UnicodeString', @CaseUStrSetLength64, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'ustr-copy-mid-16', 'rtl+mm', 'UnicodeString', @CaseUStrCopyMid16, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'ustr-pos-char-hit-32', 'rtl', 'UnicodeString', @CaseUStrPosCharHit32, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'astr-pos-char-hit-32', 'rtl', 'UTF8String', @CaseAStrPosCharHit32, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'ustr-pos-str-hit-64', 'rtl', 'UnicodeString', @CaseUStrPosStrHit64, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'sametext-equal-distinct-12', 'rtl', 'SysUtils.SameText', @CaseSameTextEqualDistinct12, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'sametext-fold-12', 'rtl', 'SysUtils.SameText', @CaseSameTextFold12, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'sametext-mismatch-first-12', 'rtl', 'SysUtils.SameText', @CaseSameTextMismatchFirst12, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'sametext-mismatch-last-12', 'rtl', 'SysUtils.SameText', @CaseSameTextMismatchLast12, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'sametext-length-differ', 'rtl', 'SysUtils.SameText', @CaseSameTextLengthDiffer, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'sametext-fold-1', 'rtl', 'SysUtils.SameText', @CaseSameTextFold1, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'sametext-fold-128', 'rtl', 'SysUtils.SameText', @CaseSameTextFold128, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'sametext-equal-128', 'rtl', 'SysUtils.SameText', @CaseSameTextEqual128, InnerCount, Profile, SelectedCase, Found);
    {$ifdef WIN64}
    PulseRunCase('pulse_hot-rtl', 'asm-sametext-equal-distinct-12', 'asm-reference', 'SysUtils.SameText', @CaseAsmSameTextEqualDistinct12, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'asm-sametext-fold-12', 'asm-reference', 'SysUtils.SameText', @CaseAsmSameTextFold12, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'asm-sametext-mismatch-first-12', 'asm-reference', 'SysUtils.SameText', @CaseAsmSameTextMismatchFirst12, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'asm-sametext-mismatch-last-12', 'asm-reference', 'SysUtils.SameText', @CaseAsmSameTextMismatchLast12, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'asm-sametext-length-differ', 'asm-reference', 'SysUtils.SameText', @CaseAsmSameTextLengthDiffer, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'asm-sametext-fold-1', 'asm-reference', 'SysUtils.SameText', @CaseAsmSameTextFold1, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'asm-sametext-fold-128', 'asm-reference', 'SysUtils.SameText', @CaseAsmSameTextFold128, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'asm-sametext-equal-128', 'asm-reference', 'SysUtils.SameText', @CaseAsmSameTextEqual128, InnerCount, Profile, SelectedCase, Found);
    {$endif}
    PulseRunCase('pulse_hot-rtl', 'comparetext-equal-12', 'rtl', 'SysUtils.CompareText', @CaseCompareTextEqual12, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'comparetext-fold-12', 'rtl', 'SysUtils.CompareText', @CaseCompareTextFold12, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'uppercase-12', 'rtl+mm', 'SysUtils.UpperCase', @CaseUpperCase12, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'lowercase-12', 'rtl+mm', 'SysUtils.LowerCase', @CaseLowerCase12, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'uppercase-64', 'rtl+mm', 'SysUtils.UpperCase', @CaseUpperCase64, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'trim-both-16', 'rtl+mm', 'SysUtils.Trim', @CaseTrimBoth16, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'trim-none-16', 'rtl', 'SysUtils.Trim', @CaseTrimNone16, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'stringreplace-one-32', 'rtl+mm', 'SysUtils.StringReplace', @CaseStringReplaceOne32, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'stringreplace-none-32', 'rtl+mm', 'SysUtils.StringReplace', @CaseStringReplaceNone32, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'replacetext-one-32', 'rtl+mm', 'StrUtils.ReplaceText', @CaseReplaceTextOne32, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'replacetext-none-32', 'rtl+mm', 'StrUtils.ReplaceText', @CaseReplaceTextNone32, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'replacetext-cyrillic-32', 'rtl+mm', 'StrUtils.ReplaceText', @CaseReplaceTextCyrillic32, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'containstext-hit-32', 'rtl', 'StrUtils.ContainsText', @CaseContainsTextHit32, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'containstext-miss-32', 'rtl', 'StrUtils.ContainsText', @CaseContainsTextMiss32, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'startstext-hit-12', 'rtl', 'StrUtils.StartsText', @CaseStartsTextHit12, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'startstext-hit-cyrillic-12', 'rtl', 'StrUtils.StartsText', @CaseStartsTextHitCyrillic12, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'ansisametext-equal-12', 'rtl', 'SysUtils.AnsiSameText', @CaseAnsiSameTextEqual12, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'endstext-hit-12', 'rtl', 'StrUtils.EndsText', @CaseEndsTextHit12, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'inttostr-int32-3', 'rtl+mm', 'SysUtils.IntToStr', @CaseIntToStrInt32Small, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'inttostr-int32-10', 'rtl+mm', 'SysUtils.IntToStr', @CaseIntToStrInt32Ten, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'inttostr-int64-19', 'rtl+mm', 'SysUtils.IntToStr', @CaseIntToStrInt64Nineteen, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'uinttostr-int64', 'rtl+mm', 'SysUtils.UIntToStr', @CaseUIntToStrInt64, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'inttohex-8', 'rtl+mm', 'SysUtils.IntToHex', @CaseIntToHex8, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'inttohex-16', 'rtl+mm', 'SysUtils.IntToHex', @CaseIntToHex16, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'trystrtoint-7', 'rtl', 'SysUtils.TryStrToInt', @CaseTryStrToInt7, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'trystrtoint64-19', 'rtl', 'SysUtils.TryStrToInt64', @CaseTryStrToInt64Nineteen, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'strtointdef-hit', 'rtl', 'SysUtils.StrToIntDef', @CaseStrToIntDefHit, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'trystrtofloat-8', 'rtl', 'SysUtils.TryStrToFloat', @CaseTryStrToFloat8, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'trystrtofloat-comma-8', 'rtl', 'SysUtils.TryStrToFloat', @CaseTryStrToFloatComma8, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'strtofloat-8', 'rtl', 'SysUtils.StrToFloat', @CaseStrToFloat8, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'floattostr-8', 'rtl+mm', 'SysUtils.FloatToStr', @CaseFloatToStr8, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'floattostrf-fixed-2', 'rtl+mm', 'SysUtils.FloatToStrF', @CaseFloatToStrFFixed2, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'format-s-d', 'rtl+mm', 'SysUtils.Format', @CaseFormatSD, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'format-f2', 'rtl+mm', 'SysUtils.Format', @CaseFormatF2, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'format-3-mixed', 'rtl+mm', 'SysUtils.Format', @CaseFormat3Mixed, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'format-literal', 'rtl+mm', 'SysUtils.Format', @CaseFormatLiteral, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'booltostr-true', 'rtl', 'SysUtils.BoolToStr', @CaseBoolToStrTrue, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'formatdatetime-hhnnss', 'rtl+mm', 'SysUtils.FormatDateTime', @CaseFormatDateTimeShort, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'formatdatetime-full', 'rtl+mm', 'SysUtils.FormatDateTime', @CaseFormatDateTimeFull, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'now', 'rtl', 'SysUtils.Now', @CaseNow, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'date', 'rtl', 'SysUtils.Date', @CaseDate, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'datetimetounix', 'rtl', 'DateUtils.DateTimeToUnix', @CaseDateTimeToUnix, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'unixtodatetime', 'rtl', 'DateUtils.UnixToDateTime', @CaseUnixToDateTime, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'utf8encode-32-ascii', 'rtl+mm', 'System.UTF8Encode', @CaseUtf8Encode32Ascii, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'utf8tostring-32-ascii', 'rtl+mm', 'System.UTF8ToString', @CaseUtf8ToString32Ascii, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'utf8encode-32-cyrillic', 'rtl+mm', 'System.UTF8Encode', @CaseUtf8Encode32Cyrillic, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'utf8tostring-32-cyrillic', 'rtl+mm', 'System.UTF8ToString', @CaseUtf8ToString32Cyrillic, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'encoding-utf8-getbytes-32', 'rtl+mm', 'SysUtils.TEncoding', @CaseEncodingGetBytes32, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'encoding-utf8-getstring-32', 'rtl+mm', 'SysUtils.TEncoding', @CaseEncodingGetString32, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'encoding-utf8-getstring-32-cyrillic', 'rtl+mm', 'SysUtils.TEncoding', @CaseEncodingGetString32Cyrillic, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'move-16', 'rtl', 'System.Move', @CaseMove16, InnerCount, Profile, SelectedCase, Found);
    PulseRunCaseData('pulse_hot-rtl', 'move-64', 'rtl', 'System.Move', @CaseMove64, InnerCount,
      Profile, SelectedCase, Found, @CaseMove64, PulseData('source', Src4k) + PulseData('dest', Dst4k));
    PulseRunCase('pulse_hot-rtl', 'move-256', 'rtl', 'System.Move', @CaseMove256, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'move-4k', 'rtl', 'System.Move', @CaseMove4k, 1, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'fillchar-64', 'rtl', 'System.FillChar', @CaseFillChar64, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'fillchar-4k', 'rtl', 'System.FillChar', @CaseFillChar4k, 1, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'comparemem-64-equal', 'rtl', 'SysUtils.CompareMem', @CaseCompareMem64Equal, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'getmem-freemem-32', 'mm', 'fpcx64mm', @CaseGetMemFreeMem32, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'getmem-freemem-256', 'mm', 'fpcx64mm', @CaseGetMemFreeMem256, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'reallocmem-grow-64-128', 'mm', 'fpcx64mm', @CaseReallocMemGrow, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'object-create-free-plain', 'rtl+mm', 'TObject', @CaseObjectCreateFreePlain, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'object-create-free-managed', 'rtl+mm', 'TObject', @CaseObjectCreateFreeManaged, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'dynarray-setlength-double-64', 'rtl+mm', 'DynArray', @CaseDynArraySetLengthDouble64, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'dynarray-setlength-string-16', 'rtl+mm', 'DynArray', @CaseDynArraySetLengthString16, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'dynarray-copy-64', 'rtl+mm', 'DynArray', @CaseDynArrayCopy64, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'dynarray-assign-share', 'rtl', 'DynArray', @CaseDynArrayAssignShare, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'max-int32', 'rtl', 'Math.Max', @CaseMaxInt32, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'min-int32', 'rtl', 'Math.Min', @CaseMinInt32, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'max-double', 'rtl', 'Math.Max', @CaseMaxDouble, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'min-double', 'rtl', 'Math.Min', @CaseMinDouble, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'samevalue-double', 'rtl', 'Math.SameValue', @CaseSameValueDouble, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'ensurerange-int', 'rtl', 'Math.EnsureRange', @CaseEnsureRangeInt, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'inrange-int', 'rtl', 'Math.InRange', @CaseInRangeInt, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'random-int', 'rtl', 'System.Random', @CaseRandomInt, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'random-double', 'rtl', 'System.Random', @CaseRandomDouble, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'ceil-double', 'rtl', 'Math.Ceil', @CaseCeilDouble, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'floor-double', 'rtl', 'Math.Floor', @CaseFloorDouble, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'list-int-add-1k-reuse', 'rtl', 'TList<Integer>', @CaseListIntAdd1kReuse, ListCount, Profile, SelectedCase, Found);
    PulseRunCaseData('pulse_hot-rtl', 'list-int-items-sum-1k', 'rtl', 'TList<Integer>', @CaseListIntItemsSum1k, ListCount, Profile, SelectedCase, Found, nil, PulseData('items', Pointer(IntList.List)));
    PulseRunCaseData('pulse_hot-rtl', 'list-int-indexof-hit-mid', 'rtl', 'TList<Integer>', @CaseListIntIndexOfHitMid, 1, Profile, SelectedCase, Found, nil, PulseData('items', Pointer(IntList.List)));
    PulseRunCaseData('pulse_hot-rtl', 'list-int-contains-miss', 'rtl', 'TList<Integer>', @CaseListIntContainsMiss, 1, Profile, SelectedCase, Found, nil, PulseData('items', Pointer(IntList.List)));
    PulseRunCaseData('pulse_hot-rtl', 'list-int-forin-1k', 'rtl', 'TList<Integer>', @CaseListIntForIn1k, ListCount, Profile, SelectedCase, Found, nil, PulseData('items', Pointer(IntList.List)));
    PulseRunCaseData('pulse_hot-rtl', 'list-int-delete-insert-mid', 'rtl', 'TList<Integer>', @CaseListIntDeleteInsertMid, 1, Profile, SelectedCase, Found, nil, PulseData('items', Pointer(IntList.List)));
    PulseRunCase('pulse_hot-rtl', 'list-int-sort-1k', 'rtl', 'TList<Integer>', @CaseListIntSort1k, ListCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'list-string-add-256-reuse', 'rtl', 'TList<UnicodeString>', @CaseListStringAdd256Reuse, 256, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'list-obj-forin-256', 'rtl', 'TList<TObject>', @CaseListObjForIn256, 256, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'array-sort-int64-1k', 'rtl', 'TArray.Sort', @CaseArraySortInt64_1k, ListCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'array-binarysearch-int-1k', 'rtl', 'TArray.BinarySearch', @CaseArrayBinarySearchInt1k, InnerCount, Profile, SelectedCase, Found);
    PulseRunCaseData('pulse_hot-rtl', 'dict-int-trygetvalue-hit', 'rtl', 'TDictionary<Integer,Integer>', @CaseDictIntTryGetValueHit, InnerCount, Profile, SelectedCase, Found, nil, {$ifdef FPC}PulseData('items', PPointer(IntDict.Ptr)^){$else}''{$endif});
    PulseRunCaseData('pulse_hot-rtl', 'dict-int-trygetvalue-miss', 'rtl', 'TDictionary<Integer,Integer>', @CaseDictIntTryGetValueMiss, InnerCount, Profile, SelectedCase, Found, nil, {$ifdef FPC}PulseData('items', PPointer(IntDict.Ptr)^){$else}''{$endif});
    PulseRunCaseData('pulse_hot-rtl', 'dict-str-trygetvalue-hit', 'rtl', 'TDictionary<UnicodeString,Integer>', @CaseDictStrTryGetValueHit, InnerCount, Profile, SelectedCase, Found, nil, {$ifdef FPC}PulseData('items', PPointer(StrDict.Ptr)^){$else}''{$endif});
    PulseRunCaseData('pulse_hot-rtl', 'dict-str-containskey-miss', 'rtl', 'TDictionary<UnicodeString,Integer>', @CaseDictStrContainsKeyMiss, InnerCount, Profile, SelectedCase, Found, nil, {$ifdef FPC}PulseData('items', PPointer(StrDict.Ptr)^){$else}''{$endif});
    PulseRunCaseData('pulse_hot-rtl', 'dict-int-addorset-existing', 'rtl', 'TDictionary<Integer,Integer>', @CaseDictIntAddOrSetExisting, InnerCount, Profile, SelectedCase, Found, nil, {$ifdef FPC}PulseData('items', PPointer(IntDict.Ptr)^){$else}''{$endif});
    PulseRunCaseData('pulse_hot-rtl', 'dict-str-add-remove-churn', 'rtl+mm', 'TDictionary<UnicodeString,Integer>', @CaseDictStrAddRemoveChurn, InnerCount, Profile, SelectedCase, Found, nil, {$ifdef FPC}PulseData('items', PPointer(StrDict.Ptr)^){$else}''{$endif});
    PulseRunCase('pulse_hot-rtl', 'stringlist-add-128-reuse', 'rtl', 'TStringList', @CaseStringListAdd128Reuse, KeyCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'stringlist-indexof-hit', 'rtl', 'TStringList', @CaseStringListIndexOfHit, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'stringlist-indexof-miss-128', 'rtl', 'TStringList', @CaseStringListIndexOfMiss128, 1, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'stringlist-indexofname-hit', 'rtl', 'TStringList', @CaseStringListIndexOfNameHit, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'stringlist-values-hit', 'rtl+mm', 'TStringList', @CaseStringListValuesHit, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'stringlist-sorted-find', 'rtl', 'TStringList', @CaseStringListSortedFind, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'memstream-write-16', 'rtl', 'TMemoryStream', @CaseMemStreamWrite16, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'memstream-write-4k', 'rtl', 'TMemoryStream', @CaseMemStreamWrite4k, 1, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'memstream-read-16', 'rtl', 'TMemoryStream', @CaseMemStreamRead16, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'memstream-seek-position', 'rtl', 'TMemoryStream', @CaseMemStreamSeekPosition, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'memstream-copyfrom-4k', 'rtl', 'TMemoryStream', @CaseMemStreamCopyFrom4k, 1, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'memstream-setsize-reuse', 'rtl', 'TMemoryStream', @CaseMemStreamSetSizeReuse, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'monitor-enter-exit', 'rtl', 'TMonitor', @CaseMonitorEnterExit, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'criticalsection-enter-leave', 'rtl', 'TCriticalSection', @CaseCriticalSectionEnterLeave, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'variant-assign-int', 'rtl', 'Variant', @CaseVariantAssignInt, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'variant-assign-string', 'rtl', 'Variant', @CaseVariantAssignString, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'variant-vartostr-int', 'rtl+mm', 'Variants.VarToStr', @CaseVariantToStrInt, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'variant-isnull', 'rtl', 'Variants.VarIsNull', @CaseVariantIsNull, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'supports-hit', 'rtl', 'SysUtils.Supports', @CaseSupportsHit, InnerCount, Profile, SelectedCase, Found);
    PulseRunCase('pulse_hot-rtl', 'supports-miss', 'rtl', 'SysUtils.Supports', @CaseSupportsMiss, InnerCount, Profile, SelectedCase, Found);
  finally
    PulseFinish('pulse_hot-rtl', SelectedCase, Found);
  end;
end.
