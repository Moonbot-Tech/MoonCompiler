{
  Test program for issue #41574: verify System.RegularExpressionsCore
  works correctly when using libpcre2_8 with UnicodeString (NEED_UTF_CONVERSION).

  Compile with:
    fpc -dUSEWIDESTRING -dUSE_PCRE2_8 -Fu<path-to-libpcre2_8> tregex8.pp

  This forces the NEED_UTF_CONVERSION code path on any platform.
}
program testdarwin;

{$mode objfpc}{$H+}

uses
  SysUtils, System.RegularExpressionsCore;

var
  ErrorCount: Integer = 0;

procedure Check(const TestName: string; Condition: Boolean);
begin
  if not Condition then
  begin
    WriteLn('FAIL: ', TestName);
    Inc(ErrorCount);
  end
  else
    WriteLn('OK:   ', TestName);
end;

procedure CheckEquals(const TestName: string; const Expected, Actual: UnicodeString);
begin
  if Expected <> Actual then
  begin
    WriteLn('FAIL: ', TestName);
    WriteLn('  Expected: ', UTF8Encode(Expected));
    WriteLn('  Actual:   ', UTF8Encode(Actual));
    Inc(ErrorCount);
  end
  else
    WriteLn('OK:   ', TestName);
end;

procedure CheckEquals(const TestName: string; Expected, Actual: Integer);
begin
  if Expected <> Actual then
  begin
    WriteLn('FAIL: ', TestName);
    WriteLn('  Expected: ', Expected);
    WriteLn('  Actual:   ', Actual);
    Inc(ErrorCount);
  end
  else
    WriteLn('OK:   ', TestName);
end;

{ Test 1: Basic ASCII match }
procedure TestBasicASCII;
var
  RE: TPerlRegEx;
begin
  WriteLn('--- TestBasicASCII ---');
  RE := TPerlRegEx.Create;
  try
    RE.RegEx := 'hello (\w+)';
    RE.Subject := 'say hello world!';
    Check('Match found', RE.Match);
    CheckEquals('MatchedText', 'hello world', RE.MatchedText);
    CheckEquals('Group 1', 'world', RE.Groups[1]);
    CheckEquals('GroupCount', 1, RE.GroupCount);
    CheckEquals('MatchedOffset', 5, RE.MatchedOffset);
    CheckEquals('MatchedLength', 11, RE.MatchedLength);
  finally
    RE.Free;
  end;
end;

{ Test 2: BMP Unicode characters (multi-byte UTF-8, single UTF-16 code unit) }
procedure TestBMPUnicode;
var
  RE: TPerlRegEx;
  Subject: UnicodeString;
begin
  WriteLn('--- TestBMPUnicode ---');
  RE := TPerlRegEx.Create;
  try
    // German umlauts: each is 2 bytes in UTF-8, 1 code unit in UTF-16
    RE.RegEx := '(#\w+#)';
    Subject := 'x'#$00E4#$00F6#$00FC'#Welt#end';  // xäöü#Welt#end
    RE.Subject := Subject;
    Check('Match found', RE.Match);
    CheckEquals('MatchedText', '#Welt#', RE.MatchedText);
    // 'x' + 3 umlauts = 4 chars, then '#Welt#' starts at position 5 (1-based)
    CheckEquals('MatchedOffset', 5, RE.MatchedOffset);
    CheckEquals('MatchedLength', 6, RE.MatchedLength);
  finally
    RE.Free;
  end;
end;

{ Test 3: CJK characters (3 bytes UTF-8, 1 UTF-16 code unit) }
procedure TestCJK;
var
  RE: TPerlRegEx;
  Subject: UnicodeString;
begin
  WriteLn('--- TestCJK ---');
  RE := TPerlRegEx.Create;
  try
    // Chinese: U+4E2D U+6587 = 中文 (3 bytes each in UTF-8)
    RE.RegEx := '(\d+)';
    Subject := #$4E2D#$6587'abc123def';  // 中文abc123def
    RE.Subject := Subject;
    Check('Match found', RE.Match);
    CheckEquals('MatchedText', '123', RE.MatchedText);
    // 2 CJK + 'abc' = 5 chars, '123' starts at position 6 (1-based)
    CheckEquals('MatchedOffset', 6, RE.MatchedOffset);
    CheckEquals('MatchedLength', 3, RE.MatchedLength);
  finally
    RE.Free;
  end;
end;

{ Test 4: Supplementary plane characters (4 bytes UTF-8, surrogate pair in UTF-16) }
procedure TestSurrogatePairs;
var
  RE: TPerlRegEx;
  Subject: UnicodeString;
begin
  WriteLn('--- TestSurrogatePairs ---');
  RE := TPerlRegEx.Create;
  try
    // U+1F600 (Grinning Face) = F0 9F 98 80 in UTF-8 = D83D DE00 in UTF-16
    // U+1D11E (Musical Symbol G Clef) = F0 9D 84 9E in UTF-8 = D834 DD1E in UTF-16
    RE.RegEx := '(X+)';
    // surrogate pair (2 code units) + 'aXXb'
    Subject := #$D83D#$DE00'aXXb';
    RE.Subject := Subject;
    Check('Match found', RE.Match);
    CheckEquals('MatchedText', 'XX', RE.MatchedText);
    // Emoji = 2 code units, 'a' = 1, so 'XX' starts at offset 4 (1-based)
    CheckEquals('MatchedOffset', 4, RE.MatchedOffset);
    CheckEquals('MatchedLength', 2, RE.MatchedLength);
  finally
    RE.Free;
  end;
end;

{ Test 5: Multiple surrogate pairs before match }
procedure TestMultipleSurrogatePairs;
var
  RE: TPerlRegEx;
  Subject: UnicodeString;
begin
  WriteLn('--- TestMultipleSurrogatePairs ---');
  RE := TPerlRegEx.Create;
  try
    RE.RegEx := '(end)';
    // 3 emoji (each = 2 UTF-16 code units) + 'end'
    Subject := #$D83D#$DE00#$D83D#$DE01#$D83D#$DE02'end';
    RE.Subject := Subject;
    Check('Match found', RE.Match);
    CheckEquals('MatchedText', 'end', RE.MatchedText);
    // 3 emojis * 2 code units = 6, so 'end' starts at offset 7 (1-based)
    CheckEquals('MatchedOffset', 7, RE.MatchedOffset);
    CheckEquals('MatchedLength', 3, RE.MatchedLength);
  finally
    RE.Free;
  end;
end;

{ Test 6: MatchAgain - multiple matches with Unicode }
procedure TestMatchAgain;
var
  RE: TPerlRegEx;
  Subject: UnicodeString;
  Count: Integer;
begin
  WriteLn('--- TestMatchAgain ---');
  RE := TPerlRegEx.Create;
  try
    RE.RegEx := '\d+';
    Subject := #$00E4'12'#$00F6'34'#$00FC'56';  // ä12ö34ü56
    RE.Subject := Subject;
    Count := 0;
    Check('First match', RE.Match);
    if RE.FoundMatch then
    begin
      CheckEquals('Match 1', '12', RE.MatchedText);
      CheckEquals('Match 1 offset', 2, RE.MatchedOffset);
      Inc(Count);
      while RE.MatchAgain do
      begin
        Inc(Count);
        case Count of
          2: begin
               CheckEquals('Match 2', '34', RE.MatchedText);
               CheckEquals('Match 2 offset', 5, RE.MatchedOffset);
             end;
          3: begin
               CheckEquals('Match 3', '56', RE.MatchedText);
               CheckEquals('Match 3 offset', 8, RE.MatchedOffset);
             end;
        end;
      end;
    end;
    CheckEquals('Total matches', 3, Count);
  finally
    RE.Free;
  end;
end;

{ Test 7: Named groups }
procedure TestNamedGroups;
var
  RE: TPerlRegEx;
  Subject: UnicodeString;
begin
  WriteLn('--- TestNamedGroups ---');
  RE := TPerlRegEx.Create;
  try
    RE.RegEx := '(?P<year>\d{4})-(?P<month>\d{2})-(?P<day>\d{2})';
    Subject := #$00E4#$00F6'2025-03-15rest';  // äö2025-03-15rest
    RE.Subject := Subject;
    Check('Match found', RE.Match);
    CheckEquals('Full match', '2025-03-15', RE.MatchedText);
    CheckEquals('Named year', '2025', RE.NamedGroups['year']);
    CheckEquals('Named month', '03', RE.NamedGroups['month']);
    CheckEquals('Named day', '15', RE.NamedGroups['day']);
    CheckEquals('MatchedOffset', 3, RE.MatchedOffset);
  finally
    RE.Free;
  end;
end;

{ Test 8: Replace with Unicode }
procedure TestReplace;
var
  RE: TPerlRegEx;
  Subject: UnicodeString;
begin
  WriteLn('--- TestReplace ---');
  RE := TPerlRegEx.Create;
  try
    RE.RegEx := 'world';
    RE.Replacement := 'Welt';
    Subject := #$00E4'hello world'#$00F6;  // ähello worldö
    RE.Subject := Subject;
    Check('ReplaceAll', RE.ReplaceAll);
    CheckEquals('Result', #$00E4'hello Welt'#$00F6, RE.Subject);
  finally
    RE.Free;
  end;
end;

{ Test 9: ReplaceAll with multiple Unicode matches }
procedure TestReplaceAll;
var
  RE: TPerlRegEx;
  Subject: UnicodeString;
begin
  WriteLn('--- TestReplaceAll ---');
  RE := TPerlRegEx.Create;
  try
    RE.RegEx := 'x';
    RE.Replacement := 'Y';
    Subject := #$4E2D'x'#$6587'x'#$4E2D;  // 中x文x中
    RE.Subject := Subject;
    Check('ReplaceAll', RE.ReplaceAll);
    CheckEquals('Result', #$4E2D'Y'#$6587'Y'#$4E2D, RE.Subject);
  finally
    RE.Free;
  end;
end;

{ Test 10: Groups with Unicode content }
procedure TestGroupsUnicode;
var
  RE: TPerlRegEx;
  Subject: UnicodeString;
begin
  WriteLn('--- TestGroupsUnicode ---');
  RE := TPerlRegEx.Create;
  try
    RE.RegEx := '(\w+)\s+(\w+)';
    // preUseOffsetLimit is not needed; just test with ASCII words after Unicode prefix
    Subject := #$00C0#$00C1' abc def rest';  // ÀÁ abc def rest
    RE.Subject := Subject;
    Check('Match found', RE.Match);
    CheckEquals('Group 0 (full)', 'abc def', RE.Groups[0]);
    CheckEquals('Group 1', 'abc', RE.Groups[1]);
    CheckEquals('Group 2', 'def', RE.Groups[2]);
    CheckEquals('GroupCount', 2, RE.GroupCount);
    CheckEquals('Group 1 offset', 4, RE.GroupOffsets[1]);
    CheckEquals('Group 1 length', 3, RE.GroupLengths[1]);
    CheckEquals('Group 2 offset', 8, RE.GroupOffsets[2]);
    CheckEquals('Group 2 length', 3, RE.GroupLengths[2]);
  finally
    RE.Free;
  end;
end;

{ Test 11: Many matches across multi-byte boundaries }
procedure TestManyMatches;
var
  RE: TPerlRegEx;
  Subject: UnicodeString;
  Count: Integer;
begin
  WriteLn('--- TestManyMatches ---');
  RE := TPerlRegEx.Create;
  try
    RE.RegEx := '.';  // match every character
    // 3 BMP chars (2-byte UTF-8 each) + 2 ASCII
    Subject := #$00E4#$00F6#$00FC'ab';  // äöüab = 5 chars
    RE.Subject := Subject;
    Count := 0;
    if RE.Match then
    begin
      Inc(Count);
      while RE.MatchAgain do
        Inc(Count);
    end;
    CheckEquals('Match count', 5, Count);
  finally
    RE.Free;
  end;
end;

{ Test 16: Empty match advancement with Unicode }
procedure TestEmptyMatch;
var
  RE: TPerlRegEx;
  Subject: UnicodeString;
  Count: Integer;
begin
  WriteLn('--- TestEmptyMatch ---');
  RE := TPerlRegEx.Create;
  try
    RE.RegEx := 'x*';  // matches empty string and 'x' sequences
    Subject := 'axb';
    RE.Subject := Subject;
    Count := 0;
    if RE.Match then
    begin
      Inc(Count);
      while RE.MatchAgain do
        Inc(Count);
    end;
    // 'x*' on 'axb': '' at 0, 'x' at 1, '' at 2, '' at 3 = 4 matches
    Check('Empty match count >= 3', Count >= 3);
  finally
    RE.Free;
  end;
end;

{ Test 12: Unicode regex pattern itself }
procedure TestUnicodePattern;
var
  RE: TPerlRegEx;
  Subject: UnicodeString;
begin
  WriteLn('--- TestUnicodePattern ---');
  RE := TPerlRegEx.Create;
  try
    // Pattern contains Unicode characters
    RE.RegEx := #$00E4'(\w+)'#$00FC;  // ä(\w+)ü
    Subject := 'xx'#$00E4'hello'#$00FC'yy';  // xxähelloüyy
    RE.Subject := Subject;
    Check('Match found', RE.Match);
    CheckEquals('Group 1', 'hello', RE.Groups[1]);
  finally
    RE.Free;
  end;
end;

{ Test 13: StoreGroups with Unicode }
procedure TestStoreGroups;
var
  RE: TPerlRegEx;
  Subject: UnicodeString;
begin
  WriteLn('--- TestStoreGroups ---');
  RE := TPerlRegEx.Create;
  try
    RE.RegEx := '(\w+)-(\w+)';
    Subject := #$4E2D'abc-def'#$6587;  // 中abc-def文
    RE.Subject := Subject;
    Check('Match found', RE.Match);
    RE.StoreGroups;
    // Verify stored groups survive
    CheckEquals('Stored group 0', 'abc-def', RE.Groups[0]);
    CheckEquals('Stored group 1', 'abc', RE.Groups[1]);
    CheckEquals('Stored group 2', 'def', RE.Groups[2]);
  finally
    RE.Free;
  end;
end;

{ Test 14: SubjectLeft and SubjectRight with Unicode }
procedure TestSubjectLeftRight;
var
  RE: TPerlRegEx;
  Subject: UnicodeString;
begin
  WriteLn('--- TestSubjectLeftRight ---');
  RE := TPerlRegEx.Create;
  try
    RE.RegEx := 'MATCH';
    Subject := #$00E4#$00F6'MATCH'#$00FC;  // äöMATCHü
    RE.Subject := Subject;
    Check('Match found', RE.Match);
    CheckEquals('SubjectLeft', #$00E4#$00F6, RE.SubjectLeft);
    CheckEquals('SubjectRight', #$00FC, RE.SubjectRight);
  finally
    RE.Free;
  end;
end;

{ Test 15: No match }
procedure TestNoMatch;
var
  RE: TPerlRegEx;
begin
  WriteLn('--- TestNoMatch ---');
  RE := TPerlRegEx.Create;
  try
    RE.RegEx := 'xyz';
    RE.Subject := #$00E4#$00F6#$00FC'abcdef';
    Check('No match', not RE.Match);
  finally
    RE.Free;
  end;
end;

begin
  WriteLn('=== System.RegularExpressionsCore UTF-8 conversion tests ===');
  WriteLn('TREString = ', {$IFDEF USEWIDESTRING}'UnicodeString'{$ELSE}'AnsiString'{$ENDIF});
  WriteLn('Library   = ', {$IFDEF USE_PCRE2_8}'libpcre2_8'{$ELSE}'libpcre2_16'{$ENDIF});
  WriteLn('Conversion= ', {$IFDEF NEED_UTF_CONVERSION}'YES'{$ELSE}'no'{$ENDIF});
  WriteLn;

  TestBasicASCII;
  TestBMPUnicode;
  TestCJK;
  TestSurrogatePairs;
  TestMultipleSurrogatePairs;
  TestMatchAgain;
  TestNamedGroups;
  TestReplace;
  TestReplaceAll;
  TestGroupsUnicode;
  TestManyMatches;
  TestEmptyMatch;
  TestUnicodePattern;
  TestStoreGroups;
  TestSubjectLeftRight;
  TestNoMatch;

  WriteLn;
  if ErrorCount = 0 then
    WriteLn('All tests passed.')
  else
    WriteLn('FAILED: ', ErrorCount, ' test(s) failed.');

  Halt(ErrorCount);
end.
