program uri_query_edits_semantic;

{$APPTYPE CONSOLE}
uses System.SysUtils, System.Net.URLClient;

procedure Check(Value: Boolean; const Detail: string);
begin
  if not Value then raise Exception.Create(Detail);
end;

procedure CheckReparse(const URI: TURI);
var
  Parsed: TURI;
  I: Integer;
begin
  Parsed := TURI.Create('https://x.invalid/?' + URI.Query);
  Check(Length(Parsed.Params) = Length(URI.Params), 'reparsed field count: ' + URI.Query);
  for I := 0 to High(URI.Params) do
    Check((Parsed.Parameter[I].Name = URI.Parameter[I].Name) and
      (Parsed.Parameter[I].Value = URI.Parameter[I].Value), 'reparsed field: ' + URI.Query);
end;

var
  URI, Backup: TURI;
  Shared: TURIParameters;
begin
  URI := TURI.Create('https://x.invalid/?trace&filter=a+b&path=%2f&room=room%207');
  Check((URI.ParameterByName['filter'] = 'a b') and (URI.ParameterByName['room'] = 'room 7'), 'decoded getters');
  Backup := URI;
  URI.AddParameter('lang', 'en');
  Check(URI.Query = 'trace&filter=a+b&path=%2f&room=room%207&lang=en', 'append preserves raw fields');
  URI.ParameterByName['room'] := 'x &+';
  Check(URI.Query = 'trace&filter=a+b&path=%2f&room=x%20%26%2B&lang=en', 'replace one field');
  Check((Length(Backup.Params) = 4) and (Backup.ParameterByName['room'] = 'room 7'), 'append isolates copy');
  Backup := URI;
  URI.Parameter[1] := TURIParameter.Create('filter', 'x+y');
  Check((Backup.Parameter[1].Value = 'a b') and (URI.Parameter[1].Value = 'x+y'), 'set isolates copy');
  Backup := URI;
  URI.DeleteParameter('filter');
  Check((Backup.Parameter[1].Name = 'filter') and (URI.Parameter[1].Name = 'path'), 'delete isolates copy');
  Shared := URI.Params;
  Shared[1].Value := 'new value';
  URI.AddParameter('q','&=');
  Check(URI.Query = 'trace&path=new%20value&room=x%20%26%2B&lang=en&q=%26%3D', 'writable Params array');
  URI.Query := 'a&&b';
  URI.DeleteParameter(2);
  URI.AddParameter('c','1');
  Check((URI.Query = 'a&&c=1') and (Length(URI.Params) = 3), 'retained empty field at end');
  URI.Query := 'id=1&&id=2&';
  URI.DeleteParameter('id');
  URI.AddParameter('x','');
  Check((URI.Query = '&x=') and (URI.Parameter[0].Name = ''), 'delete repeated fields');
  URI.Query := '&a';
  URI.DeleteParameter(1);
  Check((Length(URI.Params) = 1) and (URI.Query = '&'), 'sole empty field survives');
  CheckReparse(URI);
  URI.AddParameter('a+b','a%20b');
  CheckReparse(URI);
  URI.DeleteParameter(0);
  CheckReparse(URI);
  URI.DeleteParameter(0);
  CheckReparse(URI);
  URI.Query := 'desk+%6Eame=a+%2f&f';
  URI.ParameterByName['desk name'] := 'x&y';
  Check(URI.Query = 'desk+%6Eame=x%26y&f', 'setting a value keeps the wire name');
  URI.Parameter[0] := TURIParameter.Create('desk name', 'v+x');
  Check(URI.Query = 'desk+%6Eame=v%2Bx&f', 'same indexed name retains its spelling');
  URI.Query := 'desk+%6Eame=a+%2f&f';
  URI.Parameter[0] := TURIParameter.Create('new key', 'a /');
  Check(URI.Query = 'new%20key=a+%2f&f', 'renaming keeps an unchanged wire value');
  CheckReparse(URI);
  URI.Query := '&&flag';
  URI.Parameter[2] := TURIParameter.Create('', '');
  CheckReparse(URI);
  WriteLn('URI_QUERY_EDITS_PASS');
end.
