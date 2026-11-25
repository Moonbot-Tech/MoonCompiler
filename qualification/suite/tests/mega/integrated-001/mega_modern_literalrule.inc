{$ifdef BREADTH_HAS_PRODUCT_IO}
{ A saved literal rule may contain characters meaningful to the regex engine. }

procedure RunBreadthLiteralRule;
const
  Search: UnicodeString = 'a+b[7]$' + #$03BB;
  Input: UnicodeString = 'aaab7' + #$03BB + #10 + 'A+B[7]$' + #$03BB + #10
    + 'xA+B[7]$' + #$03BB + #10 + 'a+b[7]$' + #$03BB;
var
  Expr: TRegEx;
  Hits: TMatchCollection;
begin
  Expr := TRegEx.Create('^' + TRegEx.Escape(Search) + '$', [roIgnoreCase, roMultiLine]);
  Hits := Expr.Matches(Input);
  Check(Hits.Count = 2, 'breadth-regex-literal-ignores-metacharacters-and-requires-whole-line');
  If Hits.Count <> 2 then
    Exit;
  Check((Hits[0].Index = 8) and (Hits[0].Value = 'A+B[7]$' + #$03BB),
    'breadth-regex-literal-first-match-preserves-original-case');
  Check((Hits[1].Index = 27) and (Hits[1].Length = 8) and (Hits[1].Value = Search),
    'breadth-regex-literal-next-match-keeps-absolute-utf16-offset');
  Mix(UInt64(Hits[0].Index * 100 + Hits[1].Index));
end;
{$endif}
