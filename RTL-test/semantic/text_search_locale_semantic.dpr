program text_search_locale_semantic;

{ Case-insensitive text search of the product String: AnsiSameText /
  UnicodeSameText, UnicodeSameTextBuffer, UnicodeIsPlainAscii, the
  rfIgnoreCase path of StringReplace, StrUtils StartsText / EndsText /
  ContainsText / ReplaceText and TStringList.IndexOf / IndexOfName with the
  default UseLocale.  The contract is AnsiSameText's: printable ASCII by ASCII
  case folding, everything else through the locale; the reference for every
  locale-dependent answer is the widestringmanager compare of the same text,
  so the test holds under any locale.  It also checks what the old
  AnsiString-overload path got wrong: text outside the ANSI code page
  compared after a lossy conversion. }

{$ifdef FPC}
  {$mode delphi}{$H+}
{$endif}

uses
  SysUtils, Classes, StrUtils;

type
  { a descendant with its own comparison: IndexOf must ask it for every item }
  TFirstCharList = class(TStringList)
  protected
    function DoCompareText(const s1, s2: string): PtrInt; override;
  end;

var
  Failures: Integer = 0;

function TFirstCharList.DoCompareText(const s1, s2: string): PtrInt;
begin
  If (s1 = '') or (s2 = '') then
    Exit(Length(s1) - Length(s2));
  Result := Ord(UpCase(s1[1])) - Ord(UpCase(s2[1]));
end;

procedure Check(Condition: Boolean; const MessageText: string);
begin
  If not Condition then
  begin
    Inc(Failures);
    If Failures <= 25 then
      WriteLn('FAIL ', MessageText);
  end;
end;

{ the reference: the locale compare the routines used before }
function RefSame(const A, B: UnicodeString): Boolean;
begin
  Result := widestringmanager.CompareUnicodeStringProc(A, B, [coIgnoreCase]) = 0;
end;

function Cyr(const Codes: array of Word): UnicodeString;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(Codes) do
    Result := Result + WideChar(Codes[I]);
end;

var
  State: Cardinal = 20260917;

function NextRandom: Cardinal;
begin
  State := State * 1664525 + 1013904223;
  Result := State shr 8;
end;

function RandomText(Len: Integer; Alphabet: UnicodeString): UnicodeString;
var
  I: Integer;
begin
  SetLength(Result, Len);
  for I := 1 to Len do
    Result[I] := Alphabet[1 + NextRandom mod Cardinal(Length(Alphabet))];
end;

function FlipCase(const S: UnicodeString): UnicodeString;
var
  I: Integer;
begin
  Result := S;
  for I := 1 to Length(Result) do
    If NextRandom and 1 = 1 then
    begin
      If (Result[I] >= 'a') and (Result[I] <= 'z') then
        Result[I] := WideChar(Ord(Result[I]) - 32)
      else If (Result[I] >= 'A') and (Result[I] <= 'Z') then
        Result[I] := WideChar(Ord(Result[I]) + 32);
    end;
end;

procedure CheckPlainAscii;
begin
  Check(UnicodeIsPlainAscii(nil, 0), 'plain: empty');
  Check(UnicodeIsPlainAscii(PWideChar(UnicodeString('abc')), 3), 'plain: abc');
  Check(UnicodeIsPlainAscii(PWideChar(UnicodeString(' !"#$%&''()*+,-./0123456789:;<=>?@[\]^_`{|}~')), 43), 'plain: punctuation');
  Check(UnicodeIsPlainAscii(PWideChar(UnicodeString('abcdefgh')), 8), 'plain: two blocks');
  Check(UnicodeIsPlainAscii(PWideChar(UnicodeString('abcdefghi')), 9), 'plain: two blocks and a tail');
  Check(not UnicodeIsPlainAscii(PWideChar(UnicodeString('abc'#31)), 4), 'plain: control in the block');
  Check(not UnicodeIsPlainAscii(PWideChar(UnicodeString('abcd'#9)), 5), 'plain: tab in the tail');
  Check(not UnicodeIsPlainAscii(PWideChar(UnicodeString('abc'#127)), 4), 'plain: DEL in the block');
  Check(not UnicodeIsPlainAscii(PWideChar(UnicodeString('abcd'#127)), 5), 'plain: DEL in the tail');
  Check(not UnicodeIsPlainAscii(PWideChar(UnicodeString('ab'#0'd')), 4), 'plain: NUL');
  Check(not UnicodeIsPlainAscii(PWideChar(Cyr([$0416, $043E])), 2), 'plain: Cyrillic');
  Check(not UnicodeIsPlainAscii(PWideChar(UnicodeString('abc') + WideChar($00E9)), 4), 'plain: Latin-1 letter');
  Check(not UnicodeIsPlainAscii(PWideChar(UnicodeString('abcd') + WideChar($4FA1)), 5), 'plain: CJK in the tail');
end;

procedure CheckSameText;
var
  I, Len: Integer;
  A, B, C: UnicodeString;
  CyrA, CyrB: UnicodeString;
begin
  Check(AnsiSameText('BTCusdt', 'btcUSDT'), 'same: fold');
  Check(AnsiSameText('', ''), 'same: empty');
  Check(not AnsiSameText('', 'a'), 'same: empty vs a');
  Check(not AnsiSameText('abc', 'abd'), 'same: last differs');
  Check(not AnsiSameText('abc', 'abcd'), 'same: length');
  Check(not AnsiSameText('a b', 'ab'), 'same: space is not ignorable');
  Check(not AnsiSameText('co-op', 'coop'), 'same: hyphen is not ignorable');
  Check(AnsiSameText('Market-12345', 'MARKET-12345'), 'same: 12 chars');
  Check(not AnsiSameText('Market-12345', 'MARKET-12346'), 'same: 12 chars, last digit');
  Check(not AnsiSameText('Market-12345', 'Xarket-12345'), 'same: 12 chars, first letter');
  Check(AnsiSameText('[a]', '[A]'), 'same: brackets around a letter');
  Check(not AnsiSameText('@', '`'), 'same: the characters next to the letters');
  Check(not AnsiSameText('[', '{'), 'same: bracket pair differs only in bit 5');
  Check(UnicodeSameTextBuffer(nil, nil, 0), 'buffer: empty');
  Check(UnicodeSameTextBuffer(PWideChar(UnicodeString('abcdEFGH')), PWideChar(UnicodeString('ABCDefgh')), 8), 'buffer: two blocks');
  Check(not UnicodeSameTextBuffer(PWideChar(UnicodeString('abcdEFGH')), PWideChar(UnicodeString('ABCDefgX')), 8), 'buffer: two blocks, last differs');
  Check(UnicodeSameTextBuffer(PWideChar(UnicodeString('abcdEFGHi')), PWideChar(UnicodeString('ABCDefghI')), 9), 'buffer: tail');
  Check(UnicodeSameTextBuffer(PWideChar(UnicodeString('abcdEFGHi')), PWideChar(UnicodeString('ABCDefghIzzz')), 9), 'buffer: only Len characters');

  { random plain-ASCII pairs against the reference, every length and
    every mismatch position around the four-character blocks }
  for Len := 0 to 21 do
    for I := 0 to 40 do
    begin
      A := RandomText(Len, 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -_./:@[]{}');
      B := FlipCase(A);
      Check(AnsiSameText(A, B) = RefSame(A, B), 'random same: ' + A + ' / ' + B);
      Check(AnsiSameText(A, B), 'random same must hold: ' + A + ' / ' + B);
      If Len > 0 then
      begin
        C := B;
        C[1 + NextRandom mod Cardinal(Len)] := WideChar(Ord('~') - (NextRandom mod 3));
        Check(AnsiSameText(A, C) = RefSame(A, C), 'random mismatch: ' + A + ' / ' + C);
      end;
      C := B + 'x';
      Check(AnsiSameText(A, C) = RefSame(A, C), 'random length: ' + A + ' / ' + C);
    end;

  { non-ASCII: whatever the locale says, the routines say the same }
  CyrA := Cyr([$0416, $043E, $043F, $0430]);
  CyrB := Cyr([$0436, $041E, $041F, $0410]);
  Check(AnsiSameText(CyrA, CyrB) = RefSame(CyrA, CyrB), 'cyrillic: same as the locale');
  Check(AnsiSameText(CyrA, CyrA), 'cyrillic: identical');
  Check(not AnsiSameText(CyrA, CyrB + 'x'), 'cyrillic: length');
  Check(AnsiSameText('abc' + CyrA, 'ABC' + CyrB) = RefSame('abc' + CyrA, 'ABC' + CyrB), 'mixed: same as the locale');
  Check(AnsiSameText('abcdefgh' + CyrA, 'ABCDEFGH' + CyrB) = RefSame('abcdefgh' + CyrA, 'ABCDEFGH' + CyrB), 'mixed after two blocks: same as the locale');
  A := 'abc' + WideChar($00E9);
  B := 'ABC' + WideChar($00C9);
  Check(AnsiSameText(A, B) = RefSame(A, B), 'latin-1: same as the locale');
  A := 'x' + WideChar($00DF);
  B := 'xss';
  Check(AnsiSameText(A, B) = RefSame(A, B), 'sharp s: same as the locale (length differs)');
end;

procedure CheckStringReplace;
var
  CyrA, CyrB: UnicodeString;
begin
  Check(StringReplace('The Cat and the cat', 'CAT', 'dog', [rfReplaceAll, rfIgnoreCase]) = 'The dog and the dog', 'replace: fold all');
  Check(StringReplace('The Cat and the cat', 'CAT', 'dog', [rfIgnoreCase]) = 'The dog and the cat', 'replace: fold first');
  Check(StringReplace('abc', 'x', 'y', [rfReplaceAll, rfIgnoreCase]) = 'abc', 'replace: miss');
  Check(StringReplace('abc', '', 'y', [rfReplaceAll, rfIgnoreCase]) = 'abc', 'replace: empty pattern');
  Check(StringReplace('aAaA', 'aa', '-', [rfReplaceAll, rfIgnoreCase]) = '--', 'replace: adjacent');
  Check(StringReplace('sym12345-QTY', 'qty', 'x', [rfReplaceAll, rfIgnoreCase]) = 'sym12345-x', 'replace: tail');
  CyrA := Cyr([$0416, $0020, $0438, $0020, $0436]);
  CyrB := Cyr([$0436]);
  { the locale decides whether the capital letter matches; ASCII text
    around it stays as it is }
  If RefSame(Cyr([$0416]), CyrB) then
    Check(StringReplace(CyrA, CyrB, 'x', [rfReplaceAll, rfIgnoreCase]) = 'x' + Cyr([$0020, $0438, $0020]) + 'x', 'replace: cyrillic fold')
  else
    Check(StringReplace(CyrA, CyrB, 'x', [rfReplaceAll, rfIgnoreCase]) = Cyr([$0416, $0020, $0438, $0020]) + 'x', 'replace: cyrillic exact');
end;

{ ASCII uppercase of both sides, then a plain scan: what the case-insensitive
  engine must answer for printable ASCII, found without any uppercase copy }
function NaiveReplaceText(const S, Old, New: UnicodeString; All: Boolean): UnicodeString;
var
  Subj, Pat: UnicodeString;
  I: Integer;
begin
  Result := '';
  If Old = '' then
    Exit(S);
  Subj := UpperCase(S);
  Pat := UpperCase(Old);
  I := 1;
  while I <= Length(S) do
    If (I + Length(Pat) - 1 <= Length(S)) and (Copy(Subj, I, Length(Pat)) = Pat) then
    begin
      Result := Result + New;
      Inc(I, Length(Pat));
      If not All then
        Exit(Result + Copy(S, I, MaxInt));
    end else begin
      Result := Result + S[I];
      Inc(I);
    end;
end;

procedure CheckReplaceFold;
const
  Alphabet: UnicodeString = 'aAbBx= [{@`';
var
  Seed: Cardinal;
  I: Integer;
  S, Old, New: UnicodeString;
  All: Boolean;
  Flags: TReplaceFlags;

  function Rnd(N: Integer): Integer;
  begin
    Seed := Seed * 1103515245 + 12345;
    Result := Integer((Seed shr 16) mod Cardinal(N));
  end;

  function RndText(MaxLen: Integer): UnicodeString;
  var
    J: Integer;
  begin
    SetLength(Result, Rnd(MaxLen + 1));
    for J := 1 to Length(Result) do
      Result[J] := Alphabet[1 + Rnd(Length(Alphabet))];
  end;

begin
  { characters that differ only in bit 5 but are not letters stay distinct }
  Check(StringReplace('@`[{', '@', 'x', [rfReplaceAll, rfIgnoreCase]) = 'x`[{', 'replace fold: @ is not `');
  Check(StringReplace('[{', '{', 'x', [rfReplaceAll, rfIgnoreCase]) = '[x', 'replace fold: { is not [');
  { a pattern that ends in a character that is not a letter }
  Check(StringReplace('x=1;X=2', 'x=', 'y=', [rfReplaceAll, rfIgnoreCase]) = 'y=1;y=2', 'replace fold: last character not a letter');
  { every character a match, one case everywhere and the other nowhere }
  Check(StringReplace(StringOfChar('t', 100) + 'T', 'T', 'x', [rfReplaceAll, rfIgnoreCase]) = StringOfChar('x', 101), 'replace fold: dense');
  { a candidate whose last character matches and whose prefix does not }
  Check(StringReplace('abXabxaBx', 'abx', '-', [rfReplaceAll, rfIgnoreCase]) = '---', 'replace fold: candidates');
  Check(StringReplace('zzzzzzzzzzzzABCzz', 'abc', '-', [rfIgnoreCase]) = 'zzzzzzzzzzzz-zz', 'replace fold: past the first steps');
  Seed := 12345;
  for I := 1 to 20000 do
  begin
    S := RndText(12);
    Old := RndText(4);
    New := RndText(3);
    All := Rnd(2) = 1;
    Flags := [rfIgnoreCase];
    If All then
      Include(Flags, rfReplaceAll);
    Check(StringReplace(S, Old, New, Flags) = NaiveReplaceText(S, Old, New, All),
      'replace fold: [' + S + '] [' + Old + '] [' + New + ']');
  end;
  Check(ReplaceText('a-A-a', 'A', 'b') = 'b-b-b', 'replacetext: fold');
end;

procedure CheckStrUtils;
var
  CyrText, CyrHead, CyrTail: UnicodeString;
begin
  Check(StartsText('bTc', 'BTCUSDT'), 'starts: fold');
  Check(StartsText('', 'x'), 'starts: empty prefix');
  Check(StartsText('', ''), 'starts: both empty');
  Check(not StartsText('abcd', 'abc'), 'starts: longer prefix');
  Check(not StartsText('usdt', 'BTCUSDT'), 'starts: suffix is not a prefix');
  Check(StartsText('BTCUSDT', 'btcusdt'), 'starts: whole string');
  Check(StartsText('Prefix-12345', 'prefix-12345mid-x123Suffix-54321'), 'starts: 12 of 32');
  Check(EndsText('UsDt', 'BTCUSDT'), 'ends: fold');
  Check(EndsText('', 'x'), 'ends: empty suffix');
  Check(not EndsText('btc', 'BTCUSDT'), 'ends: prefix is not a suffix');
  Check(not EndsText('xbtcusdt', 'BTCUSDT'), 'ends: longer suffix');
  Check(EndsText('Suffix-54321', 'Prefix-12345mid-x123suffix-54321'), 'ends: 12 of 32');
  Check(ContainsText('Bitcoin/USDT', 'COIN'), 'contains: fold inside');
  Check(ContainsText('Bitcoin/USDT', 'bitcoin'), 'contains: at the start');
  Check(ContainsText('Bitcoin/USDT', 'usdt'), 'contains: at the end');
  Check(not ContainsText('Bitcoin', 'x'), 'contains: miss');
  Check(not ContainsText('abc', ''), 'contains: empty pattern is never contained (Pos)');
  Check(not ContainsText('', 'a'), 'contains: empty text');
  Check(ContainsText('aaab', 'AAB'), 'contains: overlapping candidates');
  Check(not ContainsText('aab', 'aaab'), 'contains: pattern longer than text');
  Check(ReplaceText('The Cat and the cat', 'CAT', 'dog') = 'The dog and the dog', 'replacetext: fold all');
  Check(ReplaceText('abc', '', 'x') = 'abc', 'replacetext: empty pattern');

  { text outside the ANSI code page: the AnsiString overloads compared it
    after a lossy conversion (two CJK strings became '??' and matched) }
  CyrText := Cyr([$4FA1, $683C, $0020]) + 'BTC';
  Check(ContainsText(CyrText, 'btc'), 'cjk: ASCII inside CJK text');
  Check(not ContainsText(Cyr([$4FA1, $683C]), Cyr([$5929, $6C17])), 'cjk: different CJK text is not contained');
  Check(not StartsText(Cyr([$5929]), Cyr([$4FA1, $683C])), 'cjk: different CJK prefix');
  Check(StartsText(Cyr([$4FA1]), Cyr([$4FA1, $683C])), 'cjk: same CJK prefix');
  Check(not EndsText(Cyr([$5929]), Cyr([$4FA1, $683C])), 'cjk: different CJK suffix');
  Check(ReplaceText(Cyr([$4FA1, $683C]) + 'x', 'X', 'y') = Cyr([$4FA1, $683C]) + 'y', 'cjk: replace ASCII next to CJK');

  { Some locales compare compatibility characters equal although simple
    uppercasing leaves their UTF-16 code units different. ContainsText must
    use the same locale contract as StartsText/EndsText/SameText. }
  CyrHead := Cyr([$212A]); { Kelvin sign }
  CyrTail := 'K';
  Check(ContainsText('x' + CyrHead + 'y', CyrTail) = RefSame(CyrHead, CyrTail),
    'locale equivalent: Kelvin sign contains K');
  Check(ContainsText('x' + CyrTail + 'y', CyrHead) = RefSame(CyrTail, CyrHead),
    'locale equivalent: K contains Kelvin sign');
  CyrHead := Cyr([$212B]); { Angstrom sign }
  CyrTail := Cyr([$00C5]);
  Check(ContainsText(CyrHead, CyrTail) = RefSame(CyrHead, CyrTail),
    'locale equivalent: Angstrom sign');
  CyrHead := Cyr([$2126]); { Ohm sign }
  CyrTail := Cyr([$03A9]);
  Check(ContainsText(CyrHead, CyrTail) = RefSame(CyrHead, CyrTail),
    'locale equivalent: Ohm sign');
  CyrHead := Cyr([$03C2]); { final sigma }
  CyrTail := Cyr([$03C3]);
  Check(ContainsText(CyrHead, CyrTail) = RefSame(CyrHead, CyrTail),
    'locale equivalent: final sigma');

  { non-ASCII case folding follows the locale, as AnsiSameText does }
  CyrHead := Cyr([$0436, $043E]);
  CyrTail := Cyr([$043F, $0430]);
  CyrText := Cyr([$0416, $041E, $041F, $0410]);
  Check(StartsText(CyrHead, CyrText) = RefSame(CyrHead, Copy(CyrText, 1, 2)), 'cyrillic: starts as the locale');
  Check(EndsText(CyrTail, CyrText) = RefSame(CyrTail, Copy(CyrText, 3, 2)), 'cyrillic: ends as the locale');
  Check(StartsText(CyrText, CyrText), 'cyrillic: identical prefix');
  Check(ContainsText(CyrText, Copy(CyrText, 2, 2)), 'cyrillic: identical substring');
  Check(ContainsText('ab' + CyrText, 'AB' + CyrText) = RefSame('ab' + CyrText, 'AB' + CyrText), 'mixed: contains as the locale');
end;

procedure CheckStringList;
var
  List: TStringList;
  First: TFirstCharList;
  CyrA, CyrB: UnicodeString;
begin
  CyrA := Cyr([$0416, $043E, $043F, $0430]);
  CyrB := Cyr([$0436, $041E, $041F, $0410]);
  List := TStringList.Create;
  try
    Check(List.UseLocale and not List.CaseSensitive, 'list: defaults');
    List.Add('Alpha');
    List.Add('beta');
    List.Add('GAMMA');
    List.Add(CyrA);
    List.Add('');
    Check(List.IndexOf('ALPHA') = 0, 'list: fold first');
    Check(List.IndexOf('Beta') = 1, 'list: fold second');
    Check(List.IndexOf('gamma') = 2, 'list: fold third');
    Check(List.IndexOf('') = 4, 'list: empty');
    Check(List.IndexOf('delta') = -1, 'list: miss');
    Check(List.IndexOf('alph') = -1, 'list: prefix is not a hit');
    Check(List.IndexOf('alphaa') = -1, 'list: longer is not a hit');
    Check(List.IndexOf(CyrA) = 3, 'list: identical cyrillic');
    If RefSame(CyrA, CyrB) then
      Check(List.IndexOf(CyrB) = 3, 'list: cyrillic fold as the locale')
    else
      Check(List.IndexOf(CyrB) = -1, 'list: cyrillic exact as the locale');
    Check(List.Contains('GAMMA') and List.Contains('gamma'), 'list: Contains');
    List.CaseSensitive := True;
    Check(List.IndexOf('ALPHA') = -1, 'list: case sensitive miss');
    Check(List.IndexOf('Alpha') = 0, 'list: case sensitive hit');
    List.CaseSensitive := False;
    List.UseLocale := False;
    Check(List.IndexOf('ALPHA') = 0, 'list: no locale, fold');
    Check(List.IndexOf('gamma') = 2, 'list: no locale, fold third');
    List.UseLocale := True;

    List.Clear;
    List.Add('Key=1');
    List.Add('other=2');
    List.Add(CyrA + '=3');
    Check(List.IndexOfName('KEY') = 0, 'names: fold');
    Check(List.IndexOfName('key') = 0, 'names: lower');
    Check(List.IndexOfName('ke') = -1, 'names: prefix');
    Check(List.IndexOfName('Other') = 1, 'names: second');
    Check(List.IndexOfName('none') = -1, 'names: miss');
    Check(List.IndexOfName(CyrA) = 2, 'names: identical cyrillic');
    If RefSame(CyrA, CyrB) then
      Check(List.IndexOfName(CyrB) = 2, 'names: cyrillic fold as the locale')
    else
      Check(List.IndexOfName(CyrB) = -1, 'names: cyrillic exact as the locale');
    Check(List.Values['KEY'] = '1', 'names: Values');
    List.CaseSensitive := True;
    Check(List.IndexOfName('KEY') = -1, 'names: case sensitive miss');
    Check(List.IndexOfName('Key') = 0, 'names: case sensitive hit');
  finally
    List.Free;
  end;

  First := TFirstCharList.Create;
  try
    First.Add('Alpha');
    First.Add('beta');
    Check(First.IndexOf('axxxx') = 0, 'descendant: its own compare decides, not the length');
    Check(First.IndexOf('B') = 1, 'descendant: second');
    Check(First.IndexOf('c') = -1, 'descendant: miss');
  finally
    First.Free;
  end;
end;

begin
  CheckPlainAscii;
  CheckSameText;
  CheckStringReplace;
  CheckReplaceFold;
  CheckStrUtils;
  CheckStringList;
  If Failures <> 0 then
  begin
    WriteLn('TEXT_SEARCH_LOCALE_FAIL ', Failures);
    Halt(1);
  end;
  WriteLn('TEXT_SEARCH_LOCALE_PASS');
end.
