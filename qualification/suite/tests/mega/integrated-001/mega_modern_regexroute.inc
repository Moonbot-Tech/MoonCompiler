{$ifdef BREADTH_HAS_PRODUCT_IO}
{ Capture offsets count UTF-16 units and callback replacement keeps the suffix. }

const
  BreadthRegexRule = 'tag=(?<name>[A-Za-z]+)(?<code>[0-9]{2})';
  BreadthRegexInput: UnicodeString = #$D83D#$DE00 + ' tag=alpha17; tag=beta24; tail';

procedure RunBreadthRegexGroups;
var
  Expr: TRegEx;
  Match, Next: TMatch;
  Name, Code: TGroup;
begin
  Expr := TRegEx.Create(BreadthRegexRule);
  Match := Expr.Match(BreadthRegexInput);
  Check(Match.Success and (Match.Index = 4) and (Match.Length = 11) and (Match.Value = 'tag=alpha17'),
    'breadth-regex-offset-counts-utf16-units-before-first-match');
  If not Match.Success then
    Exit;
  Name := Match.Groups['name'];
  Code := Match.Groups['code'];
  Check(Name.Success and (Name.Index = 8) and (Name.Length = 5) and (Name.Value = 'alpha')
    and Code.Success and (Code.Index = 13) and (Code.Value = '17'), 'breadth-regex-named-captures-retain-value-and-position');
  Next := Match.NextMatch;
  Check(Next.Success and (Next.Index = 17) and (Next.Length = 10) and (Next.Groups['code'].Value = '24'),
    'breadth-regex-next-match-keeps-original-subject-and-absolute-offset');
  Check(not Next.NextMatch.Success and (Name.Value = 'alpha') and (Match.Value = 'tag=alpha17'),
    'breadth-regex-advancing-does-not-overwrite-earlier-results');
  Mix(UInt64(Next.Index * 100 + Name.Index));
end;

type
  TBreadthRegexWriter = class
    Calls: Integer;
    function Mark(const Match: TMatch): string;
  end;

function TBreadthRegexWriter.Mark(const Match: TMatch): string;
begin
  Inc(Calls);
  Result := '[' + Match.Groups['name'].Value + ':' + Match.Groups['code'].Value + ']';
end;

procedure RunBreadthRegexReplacement;
const
  Expected: UnicodeString = #$D83D#$DE00 + ' [alpha:17]; tag=beta24; tail';
var
  Expr: TRegEx;
  Writer: TBreadthRegexWriter;
  Updated: string;
begin
  Expr := TRegEx.Create(BreadthRegexRule);
  Writer := TBreadthRegexWriter.Create;
  try
    Updated := Expr.Replace(BreadthRegexInput, Writer.Mark, Integer(OpaqueI(1)));
    Check((Writer.Calls = 1) and (Updated = Expected), 'breadth-regex-callback-count-limit-preserves-unmatched-unicode-and-tail');
    Mix(UInt64(Length(Updated)));
  finally
    Writer.Free;
  end;
end;
{$endif}
