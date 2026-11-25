{$ifdef BREADTH_HAS_PRODUCT_IO}
{ A quoted feed label may contain the field separator and needs its empty optional columns. }

procedure RunBreadthQuotedFeedLayout;
const
  LabelText = '"tag|' + #$03BB + '"';
var
  Row: string;
  Parts: TArray<string>;
begin
  Row := 'prod||' + LabelText + '|';
  Parts := Row.Split([Char('|')], '"', '"', TStringSplitOptions.None);
  Check((Length(Parts) = 4) and (Parts[0] = 'prod') and (Parts[1] = '') and (Parts[2] = LabelText) and (Parts[3] = ''),
    'breadth-quoted-layout-preserves-separator-in-label-and-empty-columns');
  Parts := Row.Split([Char('|')], '"', '"', TStringSplitOptions.ExcludeLastEmpty);
  Check((Length(Parts) = 3) and (Parts[1] = '') and (Parts[2] = LabelText),
    'breadth-quoted-layout-exclude-last-keeps-interior-empty-column');
  Parts := Row.Split([Char('|')], '"', '"', Integer(OpaqueI(2)), TStringSplitOptions.None);
  Check((Length(Parts) = 2) and (Parts[0] = 'prod') and (Parts[1] = ''),
    'breadth-quoted-layout-limited-result-counts-interior-empty-field');
  Mix(UInt64(Length(Parts)));
end;
{$endif}
