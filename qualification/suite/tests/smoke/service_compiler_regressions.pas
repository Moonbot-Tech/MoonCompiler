program service_compiler_regressions;

{$mode delphi}
{$modeswitch inlinevars}

uses
  SysUtils,
  Classes,
  Variants,
  Generics.Defaults,
  Generics.Collections;

type
  TFirstOrdinal = type Int64;
  TSecondOrdinal = type TFirstOrdinal;
  TThirdOrdinal = type TSecondOrdinal;

procedure Check(ACondition: Boolean; const AName: string);
begin
  If not ACondition then begin
    WriteLn('FAIL ', AName);
    Halt(1);
  end;
end;

procedure CheckKeyNames;
var
  Values: TStringList;
begin
  Values := TStringList.Create;
  try
    Values.Add('plain');
    Values.Add('key=value');
    Check(Values.KeyNames[0] = 'plain', 'keynames-plain');
    Check(Values.KeyNames[1] = 'key', 'keynames-pair');
  finally
    Values.Free;
  end;
end;

procedure CheckDistinctVariantChain;
var
  Source: Variant;
  Value: TThirdOrdinal;
begin
  Source := Int64(42);
  Value := Source;
  Check(Int64(Value) = 42, 'variant-distinct-chain');
end;

procedure CheckInlineConstArray;
begin
  const Leverages = [1, 2, 4, 8];
  Check((Length(Leverages) = 4) and (Leverages[0] = 1) and
    (Leverages[3] = 8), 'inline-const-array');
end;

procedure CheckGenericArraySurface;
var
  Values: TArray<Integer>;
  Index: Integer;
begin
  Values := TArray<Integer>.Create(9, 1, 5);
  TArray.Sort<Integer>(Values);
  Check((Values[0] = 1) and (Values[1] = 5) and (Values[2] = 9),
    'tarray-sort');
  Check(TArray.BinarySearch<Integer>(Values, 5, Index) and (Index = 1),
    'tarray-search-found');
  Check((not TArray.BinarySearch<Integer>(Values, 4, Index)) and (Index = 1),
    'tarray-search-insert');
  Check(TArray.BinarySearch<Integer>(Values, 5, Index,
    TComparer<Integer>.Default) and (Index = 1), 'tarray-search-comparer-found');
  Check((not TArray.BinarySearch<Integer>(Values, 4, Index,
    TComparer<Integer>.Default)) and (Index = 1),
    'tarray-search-comparer-insert');
  Check(TArray.BinarySearch<Integer>(Values, 5, Index,
    TComparer<Integer>.Default, 1, 2) and (Index = 1),
    'tarray-search-range-found');
  Check((not TArray.BinarySearch<Integer>(Values, 6, Index,
    TComparer<Integer>.Default, 1, 2)) and (Index = 2),
    'tarray-search-range-insert');
end;

procedure CheckUnsignedFormatting;
begin
  Check(UIntToStr(Int64(-1)) = '18446744073709551615', 'uinttostr-int64');
end;

{$ifdef UNIX}
procedure CheckPathSeparatorOptIn;
var
  Saved: Boolean;
begin
  Saved := TreatBackslashAsDirectorySeparator;
  try
    TreatBackslashAsDirectorySeparator := False;
    Check(ToSingleByteFileSystemEncodedFileName(UnicodeString('a\b')) = 'a\b',
      'path-separator-disabled');
    TreatBackslashAsDirectorySeparator := True;
    Check(ToSingleByteFileSystemEncodedFileName(UnicodeString('a\b')) = 'a/b',
      'path-separator-enabled');
  finally
    TreatBackslashAsDirectorySeparator := Saved;
  end;
end;
{$endif}

begin
  CheckKeyNames;
  CheckDistinctVariantChain;
  CheckInlineConstArray;
  CheckGenericArraySurface;
  CheckUnsignedFormatting;
{$ifdef UNIX}
  CheckPathSeparatorOptIn;
{$endif}
  WriteLn('SERVICE_COMPILER_REGRESSIONS_OK');
end.
