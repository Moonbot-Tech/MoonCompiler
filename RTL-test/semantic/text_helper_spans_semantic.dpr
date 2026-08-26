program text_helper_spans_semantic;

{ Axis 2 of the text programme (R-004/R-011/R-012): proven spans and
  slice comparison for the string-helper facades and TextPos.
  DCC64 canvas (text_oracle probe): two-arg Compare tie-breaks on length
  (1/-1/0); the ranged facades never throw; IndexOfAnyUnquoted finds a
  separator in the LAST position; a quoted Split of 'x,y,' yields three
  fields; TextPos folds case in place and returns nil for an empty
  pattern.
  Deliberately STRICTER than DCC64 (measured defects, not canvas):
  embedded NUL is data for Compare/CompareTo/CompareOrdinal/LastIndexOf
  (DCC stops at #0); a negative index/length is an empty range instead
  of a garbage-pointer read; CopyTo proves both spans instead of copying
  garbage from past the source; TextPos(nil,...) returns nil instead of
  an AV. }

{$mode delphiunicode}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}cthreads,cwstring,{$endif UNIX}
  SysUtils, System.AnsiStrings;

var
  Fails: Integer = 0;

procedure Check(const Name: AnsiString; Cond: Boolean);
begin
  if not Cond then
  begin
    WriteLn('FAIL ', Name);
    Inc(Fails);
  end;
end;

var
  A, B, S: UnicodeString;
  AA: AnsiString;
  SS: ShortString;
  Arr: array[0..7] of WideChar;
  Parts: TUnicodeStringArray;
  Pw: PWideChar;
  Pa: PAnsiChar;
  M: SizeInt;
  I: Integer;
begin
  { two-arg Compare: DCC64 length tie-break }
  Check('cmp-shorter', UnicodeString.Compare('abc', 'ab') > 0);
  Check('cmp-longer', UnicodeString.Compare('ab', 'abc') < 0);
  Check('cmp-equal', UnicodeString.Compare('ab', 'ab') = 0);

  { embedded NUL is data (stricter than DCC64's #0 stop) }
  A := 'a'#0'b';
  B := 'a'#0'c';
  Check('cmp-nul', UnicodeString.Compare(A, B) < 0);
  Check('cmpto-nul', A.CompareTo(B) < 0);
  Check('cmpord-nul', UnicodeString.CompareOrdinal(A, B) < 0);
  Check('lastindexof-nul', A.LastIndexOf(UnicodeString(#0'b')) = 1);
  Check('lastindexof-nul-miss', A.LastIndexOf(UnicodeString(#0'c')) = -1);

  { CompareOrdinal: length tie-break, ranged clamps, empty negatives }
  Check('cmpord-shorter', UnicodeString.CompareOrdinal('abc', 'ab') > 0);
  Check('cmpord-longer', UnicodeString.CompareOrdinal('ab', 'abc') < 0);
  Check('cmpord-range-past', UnicodeString.CompareOrdinal('abc', 1, 'abd', 1, 100) < 0);
  Check('cmpord-neg-index', UnicodeString.CompareOrdinal('abc', -2, 'abd', 0, 2) < 0);
  Check('cmpord-neg-both', UnicodeString.CompareOrdinal('abc', -2, 'abd', -1, 2) = 0);

  { ranged Compare: negative index/length are empty ranges; case fold }
  Check('cmp-range-neg-index', UnicodeString.Compare('abc', -2, 'abd', 0, 0) = 0);
  Check('cmp-range-neg-len', UnicodeString.Compare('abc', 0, 'abd', 0, -5) = 0);
  Check('cmp-range-valid', UnicodeString.Compare('abc', 1, 'xbc', 1, 2) = 0);
  Check('cmp-range-icase', UnicodeString.Compare('ABC', 0, 'abd', 0, 3, [coIgnoreCase]) < 0);
  Check('cmp-range-icase-eq', UnicodeString.Compare('ABC', 0, 'abc', 0, 3, [coIgnoreCase]) = 0);

  { EndsText uses the existing fold directly on the tail.  Its historic
    static-facade contract keeps an empty subtext false. }
  Check('endstext-unicode-hit', UnicodeString.EndsText('Bc', 'aBC'));
  Check('endstext-unicode-long', not UnicodeString.EndsText('abcd', 'abc'));
  Check('endstext-unicode-empty', not UnicodeString.EndsText('', 'abc'));
  Check('endstext-unicode-nonascii', UnicodeString.EndsText(#$0416, 'a'#$0416));
  AA := 'aBC';
  Check('endstext-ansi-hit', AnsiString.EndsText('Bc', AA));
  Check('endstext-ansi-empty', not AnsiString.EndsText('', AA));
  SS := 'aBC';
  Check('endstext-short-hit', ShortString.EndsText('Bc', SS));
  Check('endstext-short-empty', not ShortString.EndsText('', SS));

  { quoted window: the separator in the last position is found }
  A := 'ab,';
  Check('unq-last-sep', A.IndexOfAnyUnquoted([','], '"', '"') = 2);
  Check('unq-acount1', A.IndexOfAnyUnquoted([','], '"', '"', 2, 1) = 2);
  Check('unq-acount0', A.IndexOfAnyUnquoted([','], '"', '"', 2, 0) = -1);
  Check('unq-neg-start', A.IndexOfAnyUnquoted(['a'], '"', '"', -1, 1) = -1);
  Check('unq-high-count', A.IndexOfAnyUnquoted([','], '"', '"', 1, High(SizeInt)) = 2);
  Check('unq-past-start', A.IndexOfAnyUnquoted([','], '"', '"', High(SizeInt), 1) = -1);
  Check('unq-neg-count', A.IndexOfAnyUnquoted([','], '"', '"', 0, Low(SizeInt)) = -1);
  A := '"a,b",c';
  Check('unq-quoted-skip', A.IndexOfAnyUnquoted([','], '"', '"') = 5);

  { quoted Split: the trailing separator now yields the trailing field }
  A := 'x,y,';
  Parts := A.Split([','], '"', '"');
  Check('split-quoted-trailing', (Length(Parts) = 3) and (Parts[0] = 'x') and
    (Parts[1] = 'y') and (Parts[2] = ''));
  A := '"a,b",c';
  Parts := A.Split([','], '"', '"');
  Check('split-quoted-fields', (Length(Parts) = 2) and (Parts[0] = '"a,b"') and
    (Parts[1] = 'c'));

  { empty needle never matches the quoted search (it used to read
    AValue[1] past an empty string) }
  A := 'abc';
  Check('unq-empty-needle', A.IndexOfAnyUnquoted([UnicodeString('')], '"', '"', 0, M) = -1);
  Check('unquoted-neg-start', A.IndexOfUnquoted('a', '"', '"', Low(SizeInt)) = -1);
  Check('indexofany-neg-start', A.IndexOfAny(['a'], -1, 1) = -1);
  Check('indexofany-high-count', A.IndexOfAny(['c'], 1, High(SizeInt)) = 2);
  Check('indexofany-past-start', A.IndexOfAny(['a'], High(SizeInt), High(SizeInt)) = -1);
  Check('indexofany-string-low-start',
    A.IndexOfAny([UnicodeString('a')], Low(SizeInt)) = -1);

  { reverse facades: an oversized start index clamps instead of reading
    past the string }
  A := 'abcab';
  Check('lastindexof-clamp', A.LastIndexOf('b', 100, 200) = 4);
  Check('lastindexofany-clamp', A.LastIndexOfAny(['a', 'b'], 100, 200) = 4);
  Check('lastindexof-clamp-one', A.LastIndexOf('b', High(SizeInt), 1) = 4);
  Check('lastindexofany-clamp-one', A.LastIndexOfAny(['b'], High(SizeInt), 1) = 4);
  Check('lastindexof-high-count', A.LastIndexOf('a', 4, High(SizeInt)) = 3);
  Check('lastindexof-neg-count', A.LastIndexOf('a', 4, Low(SizeInt)) = -1);
  Check('lastindexof-empty-sentinel', UnicodeString('').LastIndexOf('a', -1, 0) = -1);
  Check('lastindexof-window', A.LastIndexOf('a', 4, 2) = 3);
  Check('lastindexof-miss', A.LastIndexOf('c', 1, 2) = -1);

  { CopyTo: proven spans, no-throw; the old form copied garbage from
    past the source }
  A := 'hello';
  for I := 0 to 7 do
    Arr[I] := '#';
  A.CopyTo(3, Arr, 0, 4);
  Check('copyto-clamped', (Arr[0] = 'l') and (Arr[1] = 'o') and (Arr[2] = '#'));
  A.CopyTo(0, Arr, -2, 3);
  Check('copyto-neg-dest-noop', Arr[0] = 'l');
  A.CopyTo(0, Arr, 0, -3);
  Check('copyto-neg-count-noop', Arr[0] = 'l');
  A.CopyTo(1, Arr, 0, 3);
  Check('copyto-valid', (Arr[0] = 'e') and (Arr[1] = 'l') and (Arr[2] = 'l'));

  { TextPos: in-place fold, DCC-measured hit and empty-pattern nil,
    nil-safe (stricter than DCC's AV) }
  S := 'Hello World';
  Pw := TextPos(PWideChar(S), 'world');
  Check('textpos-hit', (Pw <> nil) and (Pw - PWideChar(S) = 6));
  Check('textpos-nil-str', TextPos(nil, 'x') = nil);
  Check('textpos-nil-sub', TextPos(PWideChar(S), nil) = nil);
  B := '';
  Check('textpos-empty-sub', TextPos(PWideChar(S), PWideChar(B)) = nil);
  Check('textpos-miss', TextPos(PWideChar(S), 'worlds') = nil);

  { the System.AnsiStrings twin returned a garbage pointer on every hit
    (offset against the wrong base) - now it delegates }
  AA := 'Hello World';
  Pa := System.AnsiStrings.TextPos(PAnsiChar(AA), 'world');
  Check('ansistrings-textpos-hit', (Pa <> nil) and (Pa - PAnsiChar(AA) = 6));
  Check('ansistrings-textpos-nil', System.AnsiStrings.TextPos(nil, 'x') = nil);

  if Fails <> 0 then
    Halt(1);
  WriteLn('TEXT_HELPER_SPANS_OK');
end.
