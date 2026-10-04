program inline_managed_getter_borrow_semantic;

{ The value of an inlined string or dynamic-array getter is read straight from
  its source when the consumer finishes reading before any code can run that
  could change the source: an element or a character by an index without
  calls, a comparison, the empty test, Length/High, the step of Inc, a store,
  and string helpers that consume an aliased source before invalidating it
  (compare, assign, concatenate, convert, Copy, Insert).  Each of them sees
  the source as it is between a change right before the expression and a
  change right after it.  Everything else
  keeps the result's own reference: a routine taking the value (or an element
  of it) as an argument, an index or an operand that calls a routine which
  replaces the source - those reads must survive the replaced and reused
  storage. }

{$mode delphi}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  cwstring,
  {$endif UNIX}
  System.SysUtils,
  System.Generics.Collections;

type
  TIntArray = array of Integer;
  TNameArray = array of UnicodeString;
  TBig = record
    A, B, C, D: Int64;
  end;
  TBigArray = array of TBig;

  TStore = class
  public
    FText: UnicodeString;
    FAnsi: AnsiString;
    FRaw: RawByteString;
    FWide: WideString;
    FValues: TIntArray;
    FNames: TNameArray;
    FBigs: TBigArray;
    FOther: UnicodeString;
    FOtherValues: TIntArray;
    function GetText: UnicodeString; inline;
    function GetAnsi: AnsiString; inline;
    function GetRaw: RawByteString; inline;
    function GetWide: WideString; inline;
    function GetValues: TIntArray; inline;
    function GetNames: TNameArray; inline;
    function GetBigs: TBigArray; inline;
    property Text: UnicodeString read GetText;
    property AnsiText: AnsiString read GetAnsi;
    property RawText: RawByteString read GetRaw;
    property WideText: WideString read GetWide;
    property Values: TIntArray read GetValues;
    property Names: TNameArray read GetNames;
    property Bigs: TBigArray read GetBigs;
  end;

var
  GlobalText, TextTrash: UnicodeString;
  ArrayTrash: TIntArray;
  BigTrash: TBigArray;

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create('INLINE_MANAGED_GETTER_BORROW_FAIL: ' + AMessage);
end;

function TStore.GetText: UnicodeString;
begin
  Result := FText;
end;

function TStore.GetAnsi: AnsiString;
begin
  Result := FAnsi;
end;

function TStore.GetRaw: RawByteString;
begin
  Result := FRaw;
end;

function TStore.GetWide: WideString;
begin
  Result := FWide;
end;

function TStore.GetValues: TIntArray;
begin
  Result := FValues;
end;

function TStore.GetNames: TNameArray;
begin
  Result := FNames;
end;

function TStore.GetBigs: TBigArray;
begin
  Result := FBigs;
end;

function GetGlobalText: UnicodeString; inline;
begin
  Result := GlobalText;
end;

{ Replaces every source with fresh storage marked by Seed and fills storage of
  the same sizes with garbage, so that a read through a released source
  pointer sees 'Z' or -1 instead of the value it should have kept. }
procedure Replace(S: TStore; Seed: Integer);
var
  I: Integer;
begin
  S.FText := StringOfChar(Char(Ord('a') + Seed), 64);
  GlobalText := StringOfChar(Char(Ord('A') + Seed), 64);
  SetLength(S.FValues, 0);
  SetLength(S.FValues, 64);
  for I := 0 to High(S.FValues) do
    S.FValues[I] := Seed * 1000 + I;
  SetLength(S.FNames, 0);
  SetLength(S.FNames, 4);
  for I := 0 to High(S.FNames) do
    S.FNames[I] := StringOfChar(Char(Ord('a') + Seed), I + 1);
  SetLength(S.FBigs, 0);
  SetLength(S.FBigs, 4);
  for I := 0 to High(S.FBigs) do
  begin
    S.FBigs[I].A := Seed;
    S.FBigs[I].D := Seed * 10 + I;
  end;
  TextTrash := StringOfChar('Z', 64);
  SetLength(ArrayTrash, 0);
  SetLength(ArrayTrash, 64);
  for I := 0 to High(ArrayTrash) do
    ArrayTrash[I] := -1;
  SetLength(BigTrash, 0);
  SetLength(BigTrash, 4);
  for I := 0 to High(BigTrash) do
    BigTrash[I].D := -1;
end;

{ consumers that read straight from the source }

function CharAt(S: TStore; I: Integer): Char; noinline;
begin
  Replace(S, 1);
  Result := S.Text[I];
  Replace(S, 2);
end;

function ValueAt(S: TStore; I: Integer): Integer; noinline;
begin
  Replace(S, 1);
  Result := S.Values[I];
  Replace(S, 2);
end;

function Compares(S: TStore; const Other: UnicodeString): Integer; noinline;
begin
  Result := 0;
  Replace(S, 1);
  if S.Text = StringOfChar('b', 64) then
    Inc(Result, 1);
  if S.Text <> Other then
    Inc(Result, 10);
  if S.Text < Other then
    Inc(Result, 100);
  if GetGlobalText = StringOfChar('B', 64) then
    Inc(Result, 1000);
  Replace(S, 2);
end;

function Empties(S: TStore): Integer; noinline;
begin
  Result := 0;
  Replace(S, 1);
  if S.Text <> '' then
    Inc(Result, 1);
  if S.Values <> nil then
    Inc(Result, 10);
  S.FText := '';
  S.FValues := nil;
  if S.Text = '' then
    Inc(Result, 100);
  if S.Values = nil then
    Inc(Result, 1000);
  Replace(S, 2);
end;

function Lengths(S: TStore): Integer; noinline;
begin
  Replace(S, 1);
  Result := Length(S.Text) + High(S.Values) * 100 + Length(S.Names[2]) * 10000;
  Replace(S, 2);
end;

function SumValues(S: TStore): Integer; noinline;
var
  I: Integer;
begin
  Result := 0;
  Replace(S, 1);
  for I := 0 to High(S.Values) do
    Inc(Result, S.Values[I]);
  Replace(S, 2);
end;

function Arithmetic(S: TStore; I: Integer): Integer; noinline;
begin
  Replace(S, 1);
  Result := S.Values[I] * 3 + S.Values[I + 1] + Ord(S.Text[I]);
  Replace(S, 2);
end;

function Projections(S: TStore): Integer; noinline;
begin
  Result := 0;
  Replace(S, 1);
  if S.Names[3] = 'bbbb' then
    Inc(Result, 1);
  Inc(Result, S.Bigs[2].D * 10);
  Replace(S, 2);
end;

procedure StoreCopy(S: TStore); noinline;
begin
  Replace(S, 1);
  S.FOther := S.Text;
  S.FValues := S.Values;
  Check((Length(S.FValues) = 64) and (S.FValues[63] = 1063), 'array self assignment');
  S.FOtherValues := S.Values;
  Replace(S, 2);
  Check(S.FOther = StringOfChar('b', 64), 'stored text copy');
  Check((Length(S.FOtherValues) = 64) and (S.FOtherValues[63] = 1063),
    'stored array copy');
end;

procedure UnicodeStringAliases(S: TStore); noinline;
begin
  Replace(S, 1);
  S.FText := S.Text;
  Check(S.FText = StringOfChar('b', 64), 'assign to the source');
  S.FText := S.Text + 'x';
  Check(S.FText = StringOfChar('b', 64) + 'x', 'append to the source');
  S.FText := 'y' + S.Text;
  Check(S.FText = 'y' + StringOfChar('b', 64) + 'x', 'prepend to the source');
  S.FText := Copy(S.Text, 2, 3);
  Check(S.FText = 'bbb', 'Copy from the source');
  Insert(S.Text, S.FText, 1);
  Check(S.FText = 'bbbbbb', 'Insert into the source');
  Replace(S, 2);
end;

procedure OtherStringAliases(S: TStore); noinline;
begin
  S.FAnsi := AnsiString(StringOfChar('a', 32));
  S.FAnsi := S.AnsiText;
  Check(S.FAnsi = AnsiString(StringOfChar('a', 32)), 'Ansi assign');
  S.FAnsi := S.AnsiText + AnsiString('!');
  Check(S.FAnsi = AnsiString(StringOfChar('a', 32) + '!'), 'Ansi append');
  S.FAnsi := AnsiString('!') + S.AnsiText;
  Check(S.FAnsi = AnsiString('!' + StringOfChar('a', 32) + '!'), 'Ansi prepend');
  S.FAnsi := Copy(S.AnsiText, 2, 3);
  Check(S.FAnsi = 'aaa', 'Ansi Copy');
  Insert(S.AnsiText, S.FAnsi, 1);
  Check(S.FAnsi = 'aaaaaa', 'Ansi Insert');

  S.FRaw := RawByteString(AnsiString(StringOfChar('b', 32)));
  S.FRaw := S.RawText;
  Check(S.FRaw = RawByteString(AnsiString(StringOfChar('b', 32))), 'Raw assign');
  S.FRaw := S.RawText + RawByteString('!');
  Check(S.FRaw = RawByteString(AnsiString(StringOfChar('b', 32) + '!')), 'Raw append');
  S.FRaw := RawByteString('!') + S.RawText;
  Check(S.FRaw = RawByteString(AnsiString('!' + StringOfChar('b', 32) + '!')), 'Raw prepend');
  S.FRaw := Copy(S.RawText, 2, 3);
  Check(S.FRaw = 'bbb', 'Raw Copy');
  Insert(S.RawText, S.FRaw, 1);
  Check(S.FRaw = 'bbbbbb', 'Raw Insert');

  S.FWide := WideString(StringOfChar('c', 32));
  S.FWide := S.WideText;
  Check(S.FWide = WideString(StringOfChar('c', 32)), 'Wide assign');
  S.FWide := S.WideText + WideString('!');
  Check(S.FWide = WideString(StringOfChar('c', 32) + '!'), 'Wide append');
  S.FWide := WideString('!') + S.WideText;
  Check(S.FWide = WideString('!' + StringOfChar('c', 32) + '!'), 'Wide prepend');
  S.FWide := Copy(S.WideText, 2, 3);
  Check(S.FWide = 'ccc', 'Wide Copy');
  Insert(S.WideText, S.FWide, 1);
  Check(S.FWide = 'cccccc', 'Wide Insert');
end;

function Convert(S: TStore): AnsiString; noinline;
begin
  Replace(S, 1);
  Result := AnsiString(S.Text);
  Replace(S, 2);
end;

function CopyOf(S: TStore): UnicodeString; noinline;
begin
  Replace(S, 1);
  Result := Copy(S.Text, 2, 3);
  Replace(S, 2);
end;

function ForIn(S: TStore): Integer; noinline;
var
  C: Char;
begin
  Result := 0;
  Replace(S, 1);
  for C in S.Text do
  begin
    { the loop owns the string it walks }
    Replace(S, 2);
    if C = 'b' then
      Inc(Result);
  end;
end;

function ListReads(L: TList<UnicodeString>; const Key: UnicodeString): Integer; noinline;
var
  I: Integer;
begin
  Result := 0;
  L[1] := 'key';
  for I := 0 to L.Count - 1 do
  begin
    if L[I] = Key then
      Inc(Result, 1);
    if L[I] <> '' then
      Inc(Result, Ord(L[I][1]) * 10);
    Inc(Result, Length(L[I]) * 10000);
  end;
  L[1] := 'other';
end;

{ The body reads straight from the source and keeps no temporary of its own,
  while its finally body - a routine of its own on Win64, first passed here -
  still has temporaries that this routine finalizes: the cleanup frame stays. }
function FinallyTemps(S: TStore; var Trail: AnsiString): Integer; noinline;
begin
  Replace(S, 1);
  try
    Result := Length(S.Text) + Ord(S.Text[1]);
  finally
    Trail := Trail + AnsiChar(Ord('A') + Length(Trail));
  end;
end;

{ consumers that keep the result's own reference }

procedure ConsumeText(S: TStore; const T: UnicodeString); noinline;
begin
  Replace(S, 2);
  Check(T = StringOfChar('b', 64), 'const text argument');
end;

procedure ConsumeValues(S: TStore; const V: TIntArray); noinline;
begin
  Replace(S, 2);
  Check((Length(V) = 64) and (V[0] = 1000) and (V[63] = 1063), 'const array argument');
end;

procedure ConsumeBig(S: TStore; constref B: TBig); noinline;
begin
  Replace(S, 2);
  Check((B.A = 1) and (B.D = 12), 'element by reference');
end;

procedure ConsumeChar(S: TStore; C: Char); noinline;
begin
  Replace(S, 2);
  Check(C = 'b', 'character argument');
end;

function MutateIndex(S: TStore): Integer; noinline;
begin
  Replace(S, 2);
  Result := 5;
end;

function MutateText(S: TStore): UnicodeString; noinline;
begin
  Replace(S, 2);
  Result := StringOfChar('d', 64);
end;

procedure Escapes(S: TStore); noinline;
var
  C: Char;
  T: UnicodeString;
  V: Integer;
begin
  Replace(S, 1);
  ConsumeText(S, S.Text);
  Replace(S, 1);
  ConsumeValues(S, S.Values);
  Replace(S, 1);
  ConsumeBig(S, S.Bigs[2]);
  Replace(S, 1);
  ConsumeChar(S, S.Text[3]);
  { an index or an operand that replaces the source: whichever state is read,
    it must not be the released storage }
  Replace(S, 1);
  C := S.Text[MutateIndex(S)];
  Check((C = 'b') or (C = 'c'), 'index that replaces the source');
  Replace(S, 1);
  V := S.Values[MutateIndex(S)];
  Check((V = 1005) or (V = 2005), 'element index that replaces the source');
  Replace(S, 1);
  T := S.Text + MutateText(S);
  Check(((Copy(T, 1, 64) = StringOfChar('b', 64)) or
    (Copy(T, 1, 64) = StringOfChar('c', 64))) and
    (Copy(T, 65, 64) = StringOfChar('d', 64)), 'operand that replaces the source');
end;

var
  Store: TStore;
  List: TList<UnicodeString>;
  Trail: AnsiString;
begin
  Store := TStore.Create;
  try
    Check(CharAt(Store, 7) = 'b', 'character');
    Check(ValueAt(Store, 9) = 1009, 'element');
    Check(Compares(Store, StringOfChar('c', 64)) = 1111, 'comparisons');
    Check(Empties(Store) = 1111, 'empty tests');
    Check(Lengths(Store) = 30000 + 6300 + 64, 'Length and High');
    Check(SumValues(Store) = 64 * 1000 + 63 * 64 div 2, 'Inc by elements');
    Check(Arithmetic(Store, 4) = 1004 * 3 + 1005 + Ord('b'), 'operators');
    Check(Projections(Store) = 1 + 12 * 10, 'element fields');
    StoreCopy(Store);
    UnicodeStringAliases(Store);
    OtherStringAliases(Store);
    Check(Convert(Store) = AnsiString(StringOfChar('b', 64)), 'conversion');
    Check(CopyOf(Store) = 'bbb', 'Copy');
    Check(ForIn(Store) = 64, 'for-in');
    Trail := '';
    Check(FinallyTemps(Store, Trail) = 64 + Ord('b'), 'finally temporaries');
    Check(FinallyTemps(Store, Trail) = 64 + Ord('b'), 'finally temporaries again');
    Check(Trail = 'AB', 'finally trail');
    Escapes(Store);
  finally
    Store.Free;
  end;
  List := TList<UnicodeString>.Create;
  try
    List.Add('alpha');
    List.Add('');
    List.Add('key');
    Check(ListReads(List, 'key') = 2 + (Ord('a') + Ord('k') * 2) * 10 + (5 + 3 + 3) * 10000,
      'list reads');
    Check(List[1] = 'other', 'list after reads');
  finally
    List.Free;
  end;
  WriteLn('INLINE_MANAGED_GETTER_BORROW_SEMANTIC_PASS');
end.
