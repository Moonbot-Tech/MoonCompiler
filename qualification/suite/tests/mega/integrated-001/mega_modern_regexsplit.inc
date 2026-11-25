{$ifdef BREADTH_HAS_PRODUCT_IO}
{ A limited split hands the unparsed suffix to the next stage with its exact text. }

procedure RunBreadthRegexSplit;
var
  Expr: TRegEx;
  Parts: TArray<string>;
begin
  Expr := TRegEx.Create('\|');
  Parts := Expr.Split('header|' + #$03BB + '||' + #$D83D + #$DE80 + '|tail', Integer(OpaqueI(3)));
  Check((Length(Parts) = 3) and (Parts[0] = 'header') and (Parts[1] = #$03BB)
    and (Parts[2] = '|' + #$D83D + #$DE80 + '|tail'), 'breadth-regex-split-limit-keeps-unparsed-utf16-suffix');
  Parts := Expr.Split('H|a|b|', 0, Integer(OpaqueI(3)));
  Check((Length(Parts) = 3) and (Parts[0] = 'H|a') and (Parts[1] = 'b') and (Parts[2] = ''),
    'breadth-regex-split-search-origin-skips-earlier-delimiter-and-keeps-trailing-empty-field');
  Expr := TRegEx.Create('(\|)');
  Parts := Expr.Split('H|a|b|', Integer(OpaqueI(2)));
  Check((Length(Parts) = 3) and (Parts[0] = 'H') and (Parts[1] = '|') and (Parts[2] = 'a|b|'),
    'breadth-regex-split-capture-preserves-separator-with-limited-fields');
  Mix(UInt64(Length(Parts[2])));
end;
{$endif}
