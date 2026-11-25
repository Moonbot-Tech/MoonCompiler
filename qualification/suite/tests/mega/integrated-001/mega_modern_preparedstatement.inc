{$ifdef BREADTH_HAS_PRODUCT_IO}
{ Prepare a query and rewrite it after binding without consuming quoted colons. }

procedure RunBreadthPreparedStatement;
const
  Query = 'select ticket from routes where ticket = :Ticket and label = :"route name" and note = ''a''''b:literal''';
  Expected = 'select ticket from routes where ticket = ? and label = ? and note = ''a''''b:literal''';
var
  Params: TParams;
  Text, LabelValue: string;
begin
  Params := TParams.Create;
  try
    Text := Params.ParseSQL(Query, True);
    Check(Text = Expected, 'breadth-params-prepare-keeps-colon-inside-an-escaped-literal');
    Check((Params.Count = 2) and (Params[0].Name = 'Ticket') and (Params[1].Name = 'route name'),
      'breadth-params-prepare-orders-bare-and-quoted-parameter-names');
    Params.ParamByName('TICKET').AsLargeInt := OpaqueI(9007199254740993);
    LabelValue := 'entry:' + #$03BB + #$D83D + #$DE80;
    Params.ParamByName('route name').AsWideString := LabelValue;
    Text := Params.ParseSQL(Query, False);
    Check((Text = Expected) and (Params.Count = 2) and Params[0].Bound and Params[1].Bound,
      'breadth-params-rewrite-keeps-existing-bindings');
    Check((Params[0].AsLargeInt = 9007199254740993) and (Params[1].AsWideString = LabelValue),
      'breadth-params-rewrite-keeps-wide-id-and-unicode-value');
    Mix(UInt64(Params[0].AsLargeInt));
  finally
    FreeAndNil(Params);
  end;
end;
{$endif}
