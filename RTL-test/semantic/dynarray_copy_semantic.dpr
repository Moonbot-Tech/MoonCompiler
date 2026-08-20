program dynarray_copy_semantic;

{$IFDEF FPC}
  {$mode delphi}
{$ENDIF}

uses
  {$ifdef FPC}
  mormot.core.fpcx64mm,
  {$ifdef UNIX}cthreads,cwstring,{$endif UNIX}
  {$endif FPC}
  SysUtils;

type
  TByteArray = array of Byte;
  TWordArray = array of Word;
  TCardinalArray = array of Cardinal;
  TUInt64Array = array of UInt64;

  TPackedValue = packed record
    B: Byte;
    W: Word;
  end;
  TPackedValueArray = array of TPackedValue;
  TAnsiStringArray = array of AnsiString;
  TUnicodeStringArray = array of UnicodeString;
  TWideStringArray = array of WideString;
  TNestedArray = array of TUnicodeStringArray;
  TInterfaceArray = array of IInterface;

  TManagedValue = record
    Text: UnicodeString;
    Bytes: TBytes;
    Item: IInterface;
  end;
  TManagedValueArray = array of TManagedValue;

  TTracked = class(TInterfacedObject)
  public
    destructor Destroy; override;
  end;

var
  Destroyed: Integer;

procedure Check(Condition: Boolean; const What: string);
begin
  if not Condition then
    raise Exception.Create(What);
end;

destructor TTracked.Destroy;
begin
  Inc(Destroyed);
  inherited Destroy;
end;

{$IFDEF FPC}
function CopyOpenArray(const Values: array of Cardinal): TCardinalArray;
begin
  Result := Copy(Values, 1, 2);
end;
{$ENDIF}

procedure CheckUnmanagedSizes;
var
  Bytes, BytesCopy: TByteArray;
  Words, WordsCopy: TWordArray;
  Cards, CardsCopy: TCardinalArray;
  QWords, QWordsCopy: TUInt64Array;
  PackedValues, PackedCopy: TPackedValueArray;
  I: Integer;
begin
  SetLength(Bytes, 9);
  SetLength(Words, 9);
  SetLength(Cards, 9);
  SetLength(QWords, 9);
  SetLength(PackedValues, 9);
  for I := 0 to 8 do
  begin
    Bytes[I] := I * 3 + 1;
    Words[I] := I * 257 + 3;
    Cards[I] := Cardinal(I) * 65539 + 5;
    QWords[I] := UInt64(I) * $100000003 + 7;
    PackedValues[I].B := I + 11;
    PackedValues[I].W := I * 4099 + 13;
  end;

  BytesCopy := Copy(Bytes, 2, 4);
  WordsCopy := Copy(Words, 2, 4);
  CardsCopy := Copy(Cards, 2, 4);
  QWordsCopy := Copy(QWords, 2, 4);
  PackedCopy := Copy(PackedValues, 2, 4);
  Check((Length(BytesCopy) = 4) and (BytesCopy[0] = Bytes[2]) and
    (BytesCopy[3] = Bytes[5]), 'Byte Copy range');
  Check((Length(WordsCopy) = 4) and (WordsCopy[0] = Words[2]) and
    (WordsCopy[3] = Words[5]), 'Word Copy range');
  Check((Length(CardsCopy) = 4) and (CardsCopy[0] = Cards[2]) and
    (CardsCopy[3] = Cards[5]), 'Cardinal Copy range');
  Check((Length(QWordsCopy) = 4) and (QWordsCopy[0] = QWords[2]) and
    (QWordsCopy[3] = QWords[5]), 'UInt64 Copy range');
  Check((Length(PackedCopy) = 4) and
    (PackedCopy[0].B = PackedValues[2].B) and
    (PackedCopy[3].W = PackedValues[5].W), 'packed record Copy range');

  CardsCopy := Copy(Cards);
  Check((Length(CardsCopy) = Length(Cards)) and
    (CardsCopy[8] = Cards[8]), 'whole-array Copy');
  CardsCopy := Copy(Cards, 7, 1000);
  Check((Length(CardsCopy) = 2) and (CardsCopy[1] = Cards[8]),
    'Copy clamps count');
  CardsCopy := Copy(Cards, -2, 5);
  Check((Length(CardsCopy) = 3) and (CardsCopy[0] = Cards[0]) and
    (CardsCopy[2] = Cards[2]), 'Copy negative start');
  CardsCopy := Copy(Cards, 2, -1);
  Check(Length(CardsCopy) = 0, 'Copy negative count');
  CardsCopy := Copy(Cards, 1000, 4);
  Check(Length(CardsCopy) = 0, 'Copy start past end');
  {$IFDEF FPC}
  CardsCopy := CopyOpenArray(Cards);
  Check((Length(CardsCopy) = 2) and (CardsCopy[0] = Cards[1]) and
    (CardsCopy[1] = Cards[2]), 'open-array Copy');
  {$ENDIF}
end;

procedure CheckAliasing;
var
  A, B: TCardinalArray;
  I: Integer;
begin
  SetLength(A, 6);
  for I := 0 to High(A) do
    A[I] := I + 20;
  B := A;
  A := Copy(A, 1, 3);
  Check((Length(A) = 3) and (A[0] = 21) and (A[2] = 23),
    'self Copy result');
  Check((Length(B) = 6) and (B[0] = 20) and (B[5] = 25),
    'shared source survives Copy');

  B := nil;
  A := Copy(A, 1, 2);
  Check((Length(A) = 2) and (A[0] = 22) and (A[1] = 23),
    'unique self Copy');
  A := Copy(A, 0, 0);
  Check(A = nil, 'zero-length Copy is nil');
end;

procedure CheckManagedElements;
var
  AnsiStrings, AnsiStringCopy: TAnsiStringArray;
  Interfaces, InterfaceCopy: TInterfaceArray;
  Managed, ManagedCopy: TManagedValueArray;
  Nested, NestedCopy: TNestedArray;
  UnicodeStrings, UnicodeStringCopy: TUnicodeStringArray;
  WideStrings, WideStringCopy: TWideStringArray;
begin
  SetLength(AnsiStrings, 4);
  AnsiStrings[0] := AnsiString('alpha');
  AnsiStrings[2] := AnsiString('gamma');
  AnsiStringCopy := Copy(AnsiStrings);
  AnsiStrings := nil;
  Check((Length(AnsiStringCopy) = 4) and
    (AnsiStringCopy[0] = AnsiString('alpha')) and
    (AnsiStringCopy[1] = '') and
    (AnsiStringCopy[2] = AnsiString('gamma')) and
    (AnsiStringCopy[3] = ''), 'AnsiString Copy with nil holes and tail');
  AnsiStringCopy := nil;

  SetLength(UnicodeStrings, 4);
  UnicodeStrings[0] := 'alpha';
  UnicodeStrings[1] := 'be'+UnicodeChar(0)+'ta';
  UnicodeStrings[2] := 'gamma';
  UnicodeStringCopy := Copy(UnicodeStrings, 1, 3);
  UnicodeStrings := nil;
  Check((Length(UnicodeStringCopy) = 3) and
    (UnicodeStringCopy[0] = 'be'+UnicodeChar(0)+'ta') and
    (UnicodeStringCopy[1] = 'gamma') and
    (UnicodeStringCopy[2] = ''),
    'UnicodeString Copy with embedded NUL and nil tail');
  UnicodeStringCopy := nil;

  SetLength(WideStrings, 3);
  WideStrings[0] := WideString('wide-alpha');
  WideStrings[2] := WideString('wide-gamma');
  WideStringCopy := Copy(WideStrings);
  WideStrings := nil;
  Check((Length(WideStringCopy) = 3) and
    (WideStringCopy[0] = WideString('wide-alpha')) and
    (WideStringCopy[1] = '') and
    (WideStringCopy[2] = WideString('wide-gamma')),
    'WideString Copy with nil hole');
  WideStringCopy := nil;

  SetLength(Nested, 4);
  Nested[0] := TUnicodeStringArray.Create('zero','one');
  Nested[2] := TUnicodeStringArray.Create('two');
  NestedCopy := Copy(Nested);
  Nested := nil;
  Check((Length(NestedCopy) = 4) and (Length(NestedCopy[0]) = 2) and
    (NestedCopy[0][1] = 'one') and (NestedCopy[1] = nil) and
    (NestedCopy[2][0] = 'two') and (NestedCopy[3] = nil),
    'nested dynamic array Copy with nil holes and tail');
  NestedCopy := nil;

  Destroyed := 0;
  SetLength(Interfaces, 5);
  Interfaces[0] := TTracked.Create;
  Interfaces[2] := TTracked.Create;
  Interfaces[4] := TTracked.Create;
  InterfaceCopy := Copy(Interfaces, 1, 4);
  Interfaces := nil;
  Check(Destroyed = 1, 'interface Copy keeps selected non-nil values alive');
  Check((InterfaceCopy[0] = nil) and (InterfaceCopy[1] <> nil) and
    (InterfaceCopy[2] = nil) and (InterfaceCopy[3] <> nil),
    'interface Copy preserves nil holes');
  InterfaceCopy := nil;
  Check(Destroyed = 3, 'interface Copy releases every value once');

  Destroyed := 0;
  SetLength(Managed, 3);
  Managed[0].Text := 'record-zero';
  Managed[0].Bytes := TBytes.Create(0,1);
  Managed[0].Item := TTracked.Create;
  Managed[1].Text := 'record-one';
  Managed[1].Bytes := TBytes.Create(2,3);
  Managed[1].Item := TTracked.Create;
  ManagedCopy := Copy(Managed, 0, 2);
  Managed := nil;
  Check((Destroyed = 0) and (Length(ManagedCopy) = 2) and
    (ManagedCopy[0].Text = 'record-zero') and
    (ManagedCopy[0].Bytes[1] = 1) and
    (ManagedCopy[1].Text = 'record-one') and
    (ManagedCopy[1].Bytes[0] = 2), 'managed record Copy fields and lifetime');
  ManagedCopy := nil;
  Check(Destroyed = 2, 'managed record Copy releases every value once');
end;

procedure CheckNilSource;
var
  Source, Target: TCardinalArray;
begin
  SetLength(Target, 2);
  Target[0] := 10;
  Target := Copy(Source);
  Check(Target = nil, 'nil source clears destination');
end;

begin
  Check(SizeOf(TPackedValue) = 3, 'packed test element size');
  CheckUnmanagedSizes;
  CheckAliasing;
  CheckManagedElements;
  CheckNilSource;
  WriteLn('DYNARRAY_COPY_SEMANTIC_OK');
end.
