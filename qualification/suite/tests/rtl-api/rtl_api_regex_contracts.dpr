program rtl_api_regex_contracts;
{$APPTYPE CONSOLE}
{$IFDEF FPC}{$CODEPAGE UTF8}{$ENDIF}
uses System.SysUtils, System.RegularExpressions{$IFDEF FPC}, System.RegularExpressionsCore{$ENDIF};
procedure Check(Condition: Boolean; const MessageText: string);
begin
  If not Condition then
    raise Exception.Create(MessageText);
end;
type
  TEvaluator = class
    Calls: Integer;
    Fail: Boolean;
    function Evaluate(const Match: TMatch): string;
  end;
function TEvaluator.Evaluate(const Match: TMatch): string;
begin
  Inc(Calls);
  If Fail then
    raise Exception.Create('expected evaluator failure');
  Result := '<' + Match.Value + '>';
end;
procedure CheckReuse;
var R: TRegEx; E: TEvaluator; Failed: Boolean;
    {$IFDEF FPC}Core: TPerlRegEx; Ignored: string;{$ENDIF}
begin
  R := TRegEx.Create('a');
  E := TEvaluator.Create;
  try
    Check(R.Replace('aa', E.Evaluate) = '<a><a>', 'callback replacement');
    Check((R.Replace('aa', 'B') = 'BB') and (E.Calls = 2), 'callback does not survive its call');
    Check(R.Replace('a---a', E.Evaluate) = '<a>---<a>', 'replacement preserves a longer gap');
    Check(R.Replace('aa---a', '') = '---', 'shrinking adjacent and separated replacements');
    Check(TRegEx.Replace('ab', '(?=.)', '_', []) = '_a_b', 'zero-length insertion');
    Check((R.Replace('aa', 'B', 0) = 'BB') and (R.Replace('aa', E.Evaluate, 0) = '<a><a>'), 'zero count means unlimited');
    Check(R.Replace('aa', E.Evaluate, -1) = '<a><a>', 'negative replacement count is unlimited');
    Check(R.Replace('aa', E.Evaluate, 1) = '<a>a', 'bounded callback replacement');
    Check(R.Replace('aa', 'B') = 'BB', 'bounded callback is released');
    E.Fail := True;
    Failed := False;
    try R.Replace('a', E.Evaluate); except on Ex: Exception do Failed := True; end;
    Check(Failed and (R.Replace('a', 'B') = 'B'), 'reuse after evaluator exception');
  finally
    E.Free;
  end;
  {$IFDEF FPC}
  Core := TPerlRegEx.Create;
  try
    Core.RegEx := 'a';
    Core.Subject := 'a';
    Check(Core.Match, 'core initial pattern');
    Core.RegEx := 'b';
    Core.Subject := 'b';
    Check(Core.Match and (Core.MatchedText = 'b'), 'new pattern invalidates compiled code');
    Check(not Core.Match and not Core.FoundMatch, 'failed search clears success state');
    Failed := False;
    try Ignored := Core.Groups[0]; except on Ex: ERegularExpressionError do Failed := True; end;
    Check(Failed, 'group access after failure reports missing match');
    Failed := False;
    try Ignored := Core.MatchedText; except on Ex: ERegularExpressionError do Failed := True; end;
    Check(Failed, 'matched text after failure reports missing match');
    Core.Options := [preLiteral];
    Core.RegEx := 'a+';
    Core.Subject := 'a+';
    Check(Core.Match and (Core.MatchedText = 'a+'), 'literal pattern');
    Core.Options := [preLiteral, preCaseLess];
    Core.Subject := 'A+';
    Check(Core.Match and (Core.MatchedText = 'A+'), 'caseless literal pattern');
  finally
    Core.Free;
  end;
  {$ENDIF}
end;
var M: TMatch; Matches: TMatchCollection; S: string; I: Integer; Failed: Boolean;
begin
  Check(TRegEx.IsMatch('foo123', '\d+'), 'numeric match');
  Check(not TRegEx.IsMatch('foo', '\d+'), 'negative match');
  M := TRegEx.Match('цена=123.45;', '(?<=цена=)(?<amount>\d+\.\d+)(?=;)');
  Check(M.Success and (M.Value = '123.45'), 'lookaround');
  Check((M.Index = 6) and (M.Length = 6), 'UTF-16 indexes');
  Check(M.Groups['amount'].Success and (M.Groups['amount'].Value = '123.45'), 'named group');
  Check(TRegEx.IsMatch('ПрИвЕт', '^привет$', [roIgnoreCase]), 'Unicode case folding');
  S := #$D83D#$DE00 + 'ab';
  M := TRegEx.Match(S, 'ab');
  Check(M.Success and (M.Index = 3) and (M.Length = 2), 'surrogate code-unit offsets');
  Check(TRegEx.Replace('a12b34', '(\d+)', '<$1>') = 'a<12>b<34>', 'captured replacement');
  Matches := TRegEx.Matches('one two three', '\w+');
  Check((Matches.Count = 3) and (Matches[2].Value = 'three'), 'all matches');
  Matches := TRegEx.Matches('a' + #13 + 'b' + #10 + 'c' + #13#10 + 'd', '^.', [roMultiLine]);
  Check(Matches.Count = 4, 'multiline treats CR, LF and CRLF as line endings');
  Matches := TRegEx.Matches('ab', '(?=.)');
  Check(Matches.Count = 0, 'default excludes empty matches');
  Matches := TRegEx.Matches('ab', '(?=.)', []);
  Check(Matches.Count = 2, 'explicit empty matches make forward progress');
  Matches := TRegEx.Matches(S, '(?=.)', []);
  Check((Matches.Count = 4) and (Matches[1].Index = 2), 'default uses UTF-16 code units');
  {$IFDEF FPC}
  Matches := TRegEx.Matches(S, '(*UTF)(?=.)', []);
  Check((Matches.Count = 3) and (Matches[1].Index = 3), 'explicit UTF advances over surrogate pair');
  {$ENDIF}
  M := TRegEx.Match('ab', 'z');
  Check(not M.NextMatch.Success, 'no next match after failure');
  Matches := TRegEx.Matches(StringOfChar('x', 40), 'x');
  M := Matches[0];
  Matches := TRegEx.Matches('nothing', 'z');
  Check(M.Success and (M.Index = 1) and (M.Value = 'x'), 'saved match survives collection release');
  Check(not M.NextMatch.Success, 'collection matcher has been exhausted');
  M := TRegEx.Match('a' + #0 + 'b', 'b');
  Check(M.Success and (M.Index = 3), 'embedded NUL is data');
  for I := 1 to 100 do begin
    Failed := False;
    try
      TRegEx.IsMatch('test', '[');
    except
      on E: Exception do begin
        Failed := True;
        Check(Length(E.Message) > 5, 'useful invalid-pattern message');
        {$IFDEF FPC}
        Check(Pos('missing terminating ]', E.Message) > 0, 'complete engine error description');
        {$ENDIF}
      end;
    end;
    Check(Failed, 'invalid pattern is rejected');
    Check(TRegEx.IsMatch('ok123', '^ok\d+$'), 'error path leaves next compile intact');
  end;
  CheckReuse;
  Writeln('RTL_API_REGEX_CONTRACTS_OK');
end.
