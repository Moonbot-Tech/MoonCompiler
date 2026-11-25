program string_split_count_semantic;

{$APPTYPE CONSOLE}
uses System.SysUtils;

procedure Check(const Fields, Expected: TArray<string>);
var I: Integer;
begin
  if Length(Fields) <> Length(Expected) then raise Exception.Create('field count');
  for I := 0 to High(Expected) do
    if Fields[I] <> Expected[I] then raise Exception.CreateFmt('field %d', [I]);
end;

var
  Row, Delimiter: string;
begin
  Row := 'prod||"tag|x"|';
  Check(Row.Split([Char('|')], 2, TStringSplitOptions.ExcludeLastEmpty), ['prod', '']);
  Check(Row.Split([Char('|')], '"', '"', 2, TStringSplitOptions.ExcludeLastEmpty), ['prod', '']);
  Check(Row.Split([Char('|')], '"', '"', 0, TStringSplitOptions.None), []);
  Row := 'prod::::"tag::x"::';
  Delimiter := '::';
  Check(Row.Split([Delimiter], 2, TStringSplitOptions.ExcludeLastEmpty), ['prod', '']);
  Check(Row.Split([Delimiter], '"', '"', 2, TStringSplitOptions.ExcludeLastEmpty), ['prod', '']);
  Check(Row.Split([Delimiter], -1, TStringSplitOptions.None), []);
  Check(Row.Split([Delimiter], '"', '"', 8, TStringSplitOptions.ExcludeLastEmpty), ['prod', '', '"tag::x"']);
  WriteLn('STRING_SPLIT_COUNT_OK');
end.
