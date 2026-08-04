unit utcregex;

{$mode objfpc}{$H+}
{ $DEFINE USEWIDESTRING}

interface

uses
  Classes, SysUtils, fpcunit, testutils, testregistry, system.regularexpressionscore;

type

  { TTestRegExpCore }

  TTestRegExpCore = class(TTestCase)
  private
    FRegex: TPerlRegEx;
    FMatchEventCount : Integer;
    FSplitSubject: TStrings;
    procedure AssertMatch(const Msg, aMatch: TREString; aPos, aLength: Integer; Groups: array of TREString);
    procedure DoMatch(Sender: TObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
    Property RegEx : TPerlRegEx Read FRegex;
    Property SplitSubject : TStrings Read FSplitSubject;
  published
    Procedure TestHookup;
    procedure TestMatch;
    procedure TestMatchStart;
    procedure TestMatchStop;
    procedure TestNamedGroups;
    procedure TestReplace;
    procedure TestReplaceAll;
    procedure TestSplitAll;
    procedure TestSplitLimit;
    procedure TestInitialCaps;
    procedure TestReplaceGroupBackslash;
    procedure TestReplaceGroupDollar;
    procedure TestReplaceGroupQuoted;
    procedure TestReplaceGroupNamed;
    procedure TestReplaceGroupNamed2;
    procedure TestReplaceGroupNamedInvalidName;
    procedure TestReplaceWholeSubject;
    procedure TestReplaceLeftOfMatch;
    procedure TestReplaceRightOfMatch;
    procedure TestReplaceWholeMatch;
    procedure TestReplaceLastMatch;
    // Tests added after issue 41574
    {$IF DEFINED(USEWIDESTRING) AND DEFINED(USE_PCRE2_8)}
    procedure TestBasicASCII;
    procedure TestBMPUnicode;
    procedure TestCJK;
    procedure TestSurrogatePairs;
    procedure TestMultipleSurrogatePairs;
    procedure TestMatchAgain;
    procedure TestNamedGroups2;
    procedure TestReplace2;
    procedure TestReplaceAll2;
    procedure TestGroupsUnicode;
    procedure TestManyMatches;
    procedure TestEmptyMatch;
    procedure TestUnicodePattern;
    procedure TestStoreGroups;
    procedure TestSubjectLeftRight;
    procedure TestNoMatch;
    {$ENDIF}
  end;

implementation

Const
  TestStr = 'xyz abba abbba abbbba zyx';
  TestExpr = 'a(b*)a';

procedure TTestRegExpCore.AssertMatch(const Msg, aMatch: TREString; aPos, aLength: Integer; Groups: array of TREString);

var
  I : Integer;
begin
  AssertTrue(Msg+': Found match',Regex.FoundMatch);
  AssertEquals(Msg+': matched text',aMatch,Regex.MatchedText);
  AssertEquals(Msg+': offset',aPos,Regex.MatchedOffset);
  AssertEquals(Msg+': length',aLength,Regex.MatchedLength);
  AssertEquals(Msg+': group count',Length(Groups),Regex.GroupCount);
  For I:=1 to Regex.GroupCount do
    AssertEquals(Msg+' group['+IntToStr(I)+']',Groups[I-1],Regex.Groups[I]);
end;

procedure TTestRegExpCore.DoMatch(Sender: TObject);
begin
  Inc(FMatchEventCount);
end;

procedure TTestRegExpCore.TestMatch;

begin
  Regex.subject:=TestStr;
  Regex.RegEx:=TestExpr;
  AssertTrue('First match found',Regex.Match);
  AssertEquals('Match event called',1,FMatchEventCount);
  AssertMatch('Match 1','abba',5,4,['bb']);
  AssertEquals('Left of match','xyz ',Regex.SubjectLeft);
  AssertEquals('Right of match',' abbba abbbba zyx',Regex.SubjectRight);
  AssertTrue('Second match found',Regex.MatchAgain);
  AssertMatch('Match 2','abbba',10,5,['bbb']);
  AssertTrue('Third match found',Regex.MatchAgain);
  AssertMatch('Match 3','abbbba',16,6,['bbbb']);
  AssertFalse('No more matches',Regex.MatchAgain);
  AssertEquals('Match event called',3,FMatchEventCount);
end;

procedure TTestRegExpCore.TestMatchStart;

begin
  Regex.subject:=TestStr;
  Regex.RegEx:=TestExpr;
  Regex.Start:=Pos('abbba',TestStr);
  AssertTrue('First match found',Regex.Match);
  AssertMatch('Match 1','abbba',10,5,['bbb']);

  AssertTrue('Second match found',Regex.MatchAgain);
  AssertMatch('Match 3','abbbba',16,6,['bbbb']);
  AssertFalse('No more matches',Regex.MatchAgain);

end;

procedure TTestRegExpCore.TestMatchStop;
begin
  Regex.subject:=TestStr;
  Regex.RegEx:=TestExpr;
  Regex.Stop:=4;
  AssertFalse('No match found',Regex.Match);
  Regex.Stop:=9;
  AssertTrue('First match found',Regex.Match);
  AssertEquals('Match event called',1,FMatchEventCount);
  AssertMatch('Match 1','abba',5,4,['bb']);
  AssertFalse('No more matches',Regex.MatchAgain);
  AssertEquals('Match event not called again',1,FMatchEventCount);
end;

procedure TTestRegExpCore.TestNamedGroups;

Const
  Rec1 = 'Name:"John" Surname:"Doe" Email:"john@example.com"';
  Rec2 = 'Name:"Jane" Surname:"Dolina" Email:"jane@doe.com"';

begin
  Regex.Subject:=Rec1+#10+Rec2;
  Regex.RegEx:='Name:"(?<Name>[\w]+?)".*?Surname:"(?<Surname>[\w]+?)".*?Email:"(?<Email>\b[\w.%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,6}\b)"';
  AssertTrue('First match found',Regex.Match);
  AssertMatch('Match 1',Rec1,1,Length(Rec1),['John','Doe','john@example.com']);
  AssertEquals('Nonexisting group','',Regex.NamedGroups['nonexisting']);
  AssertEquals('Name group','John',Regex.NamedGroups['Name']);
  AssertEquals('Surname group','Doe',Regex.NamedGroups['Surname']);
  AssertEquals('Email group','john@example.com',Regex.NamedGroups['Email']);
  AssertTrue('Second match found',Regex.MatchAgain);
  AssertMatch('Match 2',Rec2,Length(Rec1)+2,Length(Rec2),['Jane','Dolina','jane@doe.com']);
  AssertFalse('No more matches',Regex.MatchAgain);
end;

procedure TTestRegExpCore.TestReplace;
begin
  Regex.subject:=TestStr;
  Regex.RegEx:=TestExpr;
  Regex.Replacement:='c';
  AssertTrue('First match found',Regex.Match);
  AssertEquals('Replace','c',Regex.Replace);
  AssertEquals('Replace result','xyz c abbba abbbba zyx',Regex.Subject);
  AssertTrue('Second match found',Regex.MatchAgain);
  AssertEquals('Replace 2','c',Regex.Replace);
  AssertEquals('Replace 2 result','xyz c c abbbba zyx',Regex.Subject);
  AssertTrue('Third match found',Regex.MatchAgain);
  AssertEquals('Replace 3','c',Regex.Replace);
  AssertEquals('Replace 3 result','xyz c c c zyx',Regex.Subject);
  AssertFalse('No more matches',Regex.MatchAgain);
end;

procedure TTestRegExpCore.TestReplaceAll;
begin
  Regex.subject:=TestStr;
  Regex.RegEx:=TestExpr;
  Regex.Replacement:='c';
  AssertTrue('Replacements done',Regex.ReplaceAll);
  AssertEquals('ReplaceAll result','xyz c c c zyx',Regex.Subject);
end;


procedure TTestRegExpCore.TestReplaceGroupBackslash;
// \n
begin
  Regex.subject:='*abba*';
  Regex.RegEx:=TestExpr;
  Regex.Replacement:='\1';
  AssertTrue('Match',Regex.Match);
  AssertEquals('ReplaceText','bb',Regex.Replace);
  AssertEquals('Result','*bb*',Regex.Subject);
end;

procedure TTestRegExpCore.TestReplaceGroupDollar;
// $N
begin
  Regex.subject:='*abba*';
  Regex.RegEx:=TestExpr;
  Regex.Replacement:='$1';
  AssertTrue('Match',Regex.Match);
  AssertEquals('ReplaceText','bb',Regex.Replace);
  AssertEquals('Result','*bb*',Regex.Subject);
end;

procedure TTestRegExpCore.TestReplaceGroupQuoted;
// \{N}
begin
  Regex.subject:='*abba*';
  Regex.RegEx:=TestExpr;
  Regex.Replacement:='\{1}';
  AssertTrue('Match',Regex.Match);
  AssertEquals('ReplaceText','bb',Regex.Replace);
  AssertEquals('Result','*bb*',Regex.Subject);
end;

procedure TTestRegExpCore.TestReplaceGroupNamed;
// \{name}

begin
  Regex.subject:='*abba*';
  Regex.RegEx:='a(?<Name>b*?)a';
  Regex.Replacement:='\{Name}';
  AssertTrue('Match',Regex.Match);
  AssertEquals('ReplaceText','bb',Regex.Replace);
  AssertEquals('Result','*bb*',Regex.Subject);
end;

procedure TTestRegExpCore.TestReplaceGroupNamed2;
// \{name}
begin
  Regex.subject:='*abba*';
  Regex.RegEx:='a(?<Name>b*?)a';
  Regex.Replacement:='<\{Name}>';
  AssertTrue('Match',Regex.Match);
  AssertEquals('ReplaceText','<bb>',Regex.Replace);
  AssertEquals('Result','*<bb>*',Regex.Subject);
end;

procedure TTestRegExpCore.TestReplaceGroupNamedInvalidName;
// \{name} with invalid name
begin
  Regex.subject:='*abba*';
  Regex.RegEx:='a(?<Name>b*?)a';
  Regex.Replacement:='<\{NameX}>';
  AssertTrue('Match',Regex.Match);
  AssertEquals('ReplaceText','<>',Regex.Replace);
  AssertEquals('Result','*<>*',Regex.Subject);
end;

procedure TTestRegExpCore.TestReplaceWholeSubject;
begin
  Regex.subject:='*abba*';
  Regex.RegEx:=TestExpr;
  Regex.Replacement:='<\_>';
  AssertTrue('Match',Regex.Match);
  AssertEquals('ReplaceText','<*abba*>',Regex.Replace);
  AssertEquals('Result','*<*abba*>*',Regex.Subject);
end;

procedure TTestRegExpCore.TestReplaceLeftOfMatch;
// \`
begin
  Regex.subject:='x*abba*';
  Regex.RegEx:=TestExpr;
  Regex.Replacement:='<\`>';
  AssertTrue('Match',Regex.Match);
  AssertEquals('ReplaceText','<x*>',Regex.Replace);
  AssertEquals('Result','x*<x*>*',Regex.Subject);
end;

procedure TTestRegExpCore.TestReplaceRightOfMatch;
// \'
begin
  Regex.subject:='*abba*x';
  Regex.RegEx:=TestExpr;
  Regex.Replacement:='<\''>';
  AssertTrue('Match',Regex.Match);
  AssertEquals('ReplaceText','<*x>',Regex.Replace);
  AssertEquals('Result','*<*x>*x',Regex.Subject);
end;

procedure TTestRegExpCore.TestReplaceWholeMatch;
// \&
begin
  Regex.subject:='*abba*';
  Regex.RegEx:=TestExpr;
  Regex.Replacement:='<\&>';
  AssertTrue('Match',Regex.Match);
  AssertEquals('ReplaceText','<abba>',Regex.Replace);
  AssertEquals('Result','*<abba>*',Regex.Subject);
end;

procedure TTestRegExpCore.TestReplaceLastMatch;
// \&
begin
  Regex.subject:='*abbcca*';
  Regex.RegEx:='a(b*)(c*)a';
  Regex.Replacement:='<\+>';
  AssertTrue('Match',Regex.Match);
  AssertEquals('ReplaceText','<cc>',Regex.Replace);
  AssertEquals('Result','*<cc>*',Regex.Subject);
end;


procedure TTestRegExpCore.TestSplitAll;
begin
  Regex.subject:=TestStr;
  Regex.RegEx:='\s';
  Regex.Split(SplitSubject,0);
  AssertEquals('Count',5,SplitSubject.Count);
  AssertEquals('Item 0','xyz',SplitSubject[0]);
  AssertEquals('Item 1','abba',SplitSubject[1]);
  AssertEquals('Item 2','abbba',SplitSubject[2]);
  AssertEquals('Item 3','abbbba',SplitSubject[3]);
  AssertEquals('Item 4','zyx',SplitSubject[4]);
end;

procedure TTestRegExpCore.TestSplitLimit;

begin
  Regex.subject:=TestStr;
  Regex.RegEx:='\s';
  Regex.Split(SplitSubject,2);
  AssertEquals('Count',2,SplitSubject.Count);
  AssertEquals('Item 0','xyz',SplitSubject[0]);
  AssertEquals('Item 1','abba abbba abbbba zyx',SplitSubject[1]);
end;

procedure TTestRegExpCore.TestInitialCaps;
begin
  AssertEquals('Initialcaps 1','Abc',InitialCaps('aBc'));
  AssertEquals('Initialcaps 2',' Abc',InitialCaps(' aBc'));
  AssertEquals('Initialcaps 3','Dad Abc',InitialCaps('dAd aBc'));
  AssertEquals('Initialcaps 4','Dad Abc ',InitialCaps('dAd aBc '));
end;

procedure TTestRegExpCore.SetUp;
begin
  FRegex:=TPerlRegEx.Create;
  FRegEx.OnMatch:=@DoMatch;
  FMatchEventCount:=0;
  FSplitSubject:=TStringList.Create;
end;

procedure TTestRegExpCore.TearDown;

begin
  FreeAndNil(FSplitSubject);
  FreeAndNil(FRegex);
end;

procedure TTestRegExpCore.TestHookup;
begin
  AssertNotNull('Regex',Regex);
  AssertTrue('Assigned OnMatch event',Assigned(Regex.OnMatch));
  AssertEquals('Match event count',0,FMatchEventCount);
end;

{$IF DEFINED(USEWIDESTRING) AND DEFINED(USE_PCRE2_8)}

procedure TTestRegExpCore.TestBasicASCII;
var
  RE: TPerlRegEx;
begin
  RE := TPerlRegEx.Create;
  try
    RE.RegEx := 'hello (\w+)';
    RE.Subject := 'say hello world!';
    AssertTrue('Match found', RE.Match);
    AssertEquals('MatchedText', 'hello world', RE.MatchedText);
    AssertEquals('Group 1', 'world', RE.Groups[1]);
    AssertEquals('GroupCount', 1, RE.GroupCount);
    AssertEquals('MatchedOffset', 5, RE.MatchedOffset);
    AssertEquals('MatchedLength', 11, RE.MatchedLength);
  finally
    RE.Free;
  end;
end;

procedure TTestRegExpCore.TestBMPUnicode;
var
  RE: TPerlRegEx;
  Subject: UnicodeString;
begin
  RE := TPerlRegEx.Create;
  try
    // German umlauts: each is 2 bytes in UTF-8, 1 code unit in UTF-16
    RE.RegEx := '(#\w+#)';
    Subject := 'x'#$00E4#$00F6#$00FC'#Welt#end';  // xäöü#Welt#end
    RE.Subject := Subject;
    AssertTrue('Match found', RE.Match);
    AssertEquals('MatchedText', '#Welt#', RE.MatchedText);
    // 'x' + 3 umlauts = 4 chars, then '#Welt#' starts at position 5 (1-based)
    AssertEquals('MatchedOffset', 5, RE.MatchedOffset);
    AssertEquals('MatchedLength', 6, RE.MatchedLength);
  finally
    RE.Free;
  end;
end;

procedure TTestRegExpCore.TestCJK;
var
  RE: TPerlRegEx;
  Subject: UnicodeString;
begin
  RE := TPerlRegEx.Create;
  try
    // Chinese: U+4E2D U+6587 = 中文 (3 bytes each in UTF-8)
    RE.RegEx := '(\d+)';
    Subject := #$4E2D#$6587'abc123def';  // 中文abc123def
    RE.Subject := Subject;
    AssertTrue('Match found', RE.Match);
    AssertEquals('MatchedText', '123', RE.MatchedText);
    // 2 CJK + 'abc' = 5 chars, '123' starts at position 6 (1-based)
    AssertEquals('MatchedOffset', 6, RE.MatchedOffset);
    AssertEquals('MatchedLength', 3, RE.MatchedLength);
  finally
    RE.Free;
  end;
end;

procedure TTestRegExpCore.TestSurrogatePairs;
var
  RE: TPerlRegEx;
  Subject: UnicodeString;
begin
  RE := TPerlRegEx.Create;
  try
    // U+1F600 (Grinning Face) = F0 9F 98 80 in UTF-8 = D83D DE00 in UTF-16
    // U+1D11E (Musical Symbol G Clef) = F0 9D 84 9E in UTF-8 = D834 DD1E in UTF-16
    RE.RegEx := '(X+)';
    // surrogate pair (2 code units) + 'aXXb'
    Subject := #$D83D#$DE00'aXXb';
    RE.Subject := Subject;
    AssertTrue('Match found', RE.Match);
    AssertEquals('MatchedText', 'XX', RE.MatchedText);
    // Emoji = 2 code units, 'a' = 1, so 'XX' starts at offset 4 (1-based)
    AssertEquals('MatchedOffset', 4, RE.MatchedOffset);
    AssertEquals('MatchedLength', 2, RE.MatchedLength);
  finally
    RE.Free;
  end;
end;

procedure TTestRegExpCore.TestMultipleSurrogatePairs;
var
  RE: TPerlRegEx;
  Subject: UnicodeString;
begin
  RE := TPerlRegEx.Create;
  try
    RE.RegEx := '(end)';
    // 3 emoji (each = 2 UTF-16 code units) + 'end'
    Subject := #$D83D#$DE00#$D83D#$DE01#$D83D#$DE02'end';
    RE.Subject := Subject;
    AssertTrue('Match found', RE.Match);
    AssertEquals('MatchedText', 'end', RE.MatchedText);
    // 3 emojis * 2 code units = 6, so 'end' starts at offset 7 (1-based)
    AssertEquals('MatchedOffset', 7, RE.MatchedOffset);
    AssertEquals('MatchedLength', 3, RE.MatchedLength);
  finally
    RE.Free;
  end;
end;

procedure TTestRegExpCore.TestMatchAgain;
var
  RE: TPerlRegEx;
  Subject: UnicodeString;
  Count: Integer;
begin
  RE := TPerlRegEx.Create;
  try
    RE.RegEx := '\d+';
    Subject := #$00E4'12'#$00F6'34'#$00FC'56';  // ä12ö34ü56
    RE.Subject := Subject;
    Count := 0;
    AssertTrue('First match', RE.Match);
    if RE.FoundMatch then
    begin
      AssertEquals('Match 1', '12', RE.MatchedText);
      AssertEquals('Match 1 offset', 2, RE.MatchedOffset);
      Inc(Count);
      while RE.MatchAgain do
      begin
        Inc(Count);
        case Count of
          2: begin
               AssertEquals('Match 2', '34', RE.MatchedText);
               AssertEquals('Match 2 offset', 5, RE.MatchedOffset);
             end;
          3: begin
               AssertEquals('Match 3', '56', RE.MatchedText);
               AssertEquals('Match 3 offset', 8, RE.MatchedOffset);
             end;
        end;
      end;
    end;
    AssertEquals('Total matches', 3, Count);
  finally
    RE.Free;
  end;
end;

procedure TTestRegExpCore.TestNamedGroups2;
var
  RE: TPerlRegEx;
  Subject: UnicodeString;
begin
  RE := TPerlRegEx.Create;
  try
    RE.RegEx := '(?P<year>\d{4})-(?P<month>\d{2})-(?P<day>\d{2})';
    Subject := #$00E4#$00F6'2025-03-15rest';  // äö2025-03-15rest
    RE.Subject := Subject;
    AssertTrue('Match found', RE.Match);
    AssertEquals('Full match', '2025-03-15', RE.MatchedText);
    AssertEquals('Named year', '2025', RE.NamedGroups['year']);
    AssertEquals('Named month', '03', RE.NamedGroups['month']);
    AssertEquals('Named day', '15', RE.NamedGroups['day']);
    AssertEquals('MatchedOffset', 3, RE.MatchedOffset);
  finally
    RE.Free;
  end;
end;

procedure TTestRegExpCore.TestReplace2;
var
  RE: TPerlRegEx;
  Subject: UnicodeString;
begin
  RE := TPerlRegEx.Create;
  try
    RE.RegEx := 'world';
    RE.Replacement := 'Welt';
    Subject := #$00E4'hello world'#$00F6;  // ähello worldö
    RE.Subject := Subject;
    AssertTrue('ReplaceAll', RE.ReplaceAll);
    AssertEquals('Result', #$00E4'hello Welt'#$00F6, RE.Subject);
  finally
    RE.Free;
  end;
end;

procedure TTestRegExpCore.TestReplaceAll2;
var
  RE: TPerlRegEx;
  Subject: UnicodeString;
begin
  RE := TPerlRegEx.Create;
  try
    RE.RegEx := 'x';
    RE.Replacement := 'Y';
    Subject := #$4E2D'x'#$6587'x'#$4E2D;  // 中x文x中
    RE.Subject := Subject;
    AssertTrue('ReplaceAll', RE.ReplaceAll);
    AssertEquals('Result', #$4E2D'Y'#$6587'Y'#$4E2D, RE.Subject);
  finally
    RE.Free;
  end;
end;

procedure TTestRegExpCore.TestGroupsUnicode;
var
  RE: TPerlRegEx;
  Subject: UnicodeString;
begin
  RE := TPerlRegEx.Create;
  try
    RE.RegEx := '(\w+)\s+(\w+)';
    // preUseOffsetLimit is not needed; just test with ASCII words after Unicode prefix
    Subject := #$00C0#$00C1' abc def rest';  // ÀÁ abc def rest
    RE.Subject := Subject;
    AssertTrue('Match found', RE.Match);
    AssertEquals('Group 0 (full)', 'abc def', RE.Groups[0]);
    AssertEquals('Group 1', 'abc', RE.Groups[1]);
    AssertEquals('Group 2', 'def', RE.Groups[2]);
    AssertEquals('GroupCount', 2, RE.GroupCount);
    AssertEquals('Group 1 offset', 4, RE.GroupOffsets[1]);
    AssertEquals('Group 1 length', 3, RE.GroupLengths[1]);
    AssertEquals('Group 2 offset', 8, RE.GroupOffsets[2]);
    AssertEquals('Group 2 length', 3, RE.GroupLengths[2]);
  finally
    RE.Free;
  end;
end;

procedure TTestRegExpCore.TestManyMatches;
var
  RE: TPerlRegEx;
  Subject: UnicodeString;
  Count: Integer;
begin
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
    AssertEquals('Match count', 5, Count);
  finally
    RE.Free;
  end;
end;

procedure TTestRegExpCore.TestEmptyMatch;
var
  RE: TPerlRegEx;
  Subject: UnicodeString;
  Count: Integer;
begin
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
    AssertTrue('Empty match count >= 3', Count >= 3);
  finally
    RE.Free;
  end;
end;


procedure TTestRegExpCore.TestUnicodePattern;
var
  RE: TPerlRegEx;
  Subject: UnicodeString;
begin
  RE := TPerlRegEx.Create;
  try
    // Pattern contains Unicode characters
    RE.RegEx := #$00E4'(\w+)'#$00FC;  // ä(\w+)ü
    Subject := 'xx'#$00E4'hello'#$00FC'yy';  // xxähelloüyy
    RE.Subject := Subject;
    AssertTrue('Match found', RE.Match);
    AssertEquals('Group 1', 'hello', RE.Groups[1]);
  finally
    RE.Free;
  end;
end;


procedure TTestRegExpCore.TestStoreGroups;
var
  RE: TPerlRegEx;
  Subject: UnicodeString;
begin
  RE := TPerlRegEx.Create;
  try
    RE.RegEx := '(\w+)-(\w+)';
    Subject := #$4E2D'abc-def'#$6587;  // 中abc-def文
    RE.Subject := Subject;
    AssertTrue('Match found', RE.Match);
    RE.StoreGroups;
    // Verify stored groups survive
    AssertEquals('Stored group 0', 'abc-def', RE.Groups[0]);
    AssertEquals('Stored group 1', 'abc', RE.Groups[1]);
    AssertEquals('Stored group 2', 'def', RE.Groups[2]);
  finally
    RE.Free;
  end;
end;


procedure TTestRegExpCore.TestSubjectLeftRight;
var
  RE: TPerlRegEx;
  Subject: UnicodeString;
begin
  RE := TPerlRegEx.Create;
  try
    RE.RegEx := 'MATCH';
    Subject := #$00E4#$00F6'MATCH'#$00FC;  // äöMATCHü
    RE.Subject := Subject;
    AssertTrue('Match found', RE.Match);
    AssertEquals('SubjectLeft', #$00E4#$00F6, RE.SubjectLeft);
    AssertEquals('SubjectRight', #$00FC, RE.SubjectRight);
  finally
    RE.Free;
  end;
end;

procedure TTestRegExpCore.TestNoMatch;
var
  RE: TPerlRegEx;
begin
  RE := TPerlRegEx.Create;
  try
    RE.RegEx := 'xyz';
    RE.Subject := #$00E4#$00F6#$00FC'abcdef';
    AssertTrue('No match', not RE.Match);
  finally
    RE.Free;
  end;
end;
{$ENDIF}

initialization

  RegisterTest(TTestRegExpCore);
end.

