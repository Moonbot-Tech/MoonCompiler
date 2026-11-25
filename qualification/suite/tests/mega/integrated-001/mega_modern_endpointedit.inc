{$ifdef BREADTH_HAS_PRODUCT_IO}
{ Edit search options without changing the stored endpoint, filter, or port. }

procedure RunBreadthEndpointEdit;
const
  Stored = 'https://example.invalid:8443/calendar?filter=room%207&mode=old';
  Updated = 'https://example.invalid:8443/calendar?filter=room%207&mode=live&region=eu-west';
var
  Uri, Restored: TURI;
  Wire: string;
begin
  Uri := TURI.Create(Stored);
  Check((Uri.Scheme = 'https') and (Uri.Host = 'example.invalid') and (Uri.Port = 8443) and (Uri.Path = '/calendar'),
    'breadth-endpoint-loads-explicit-port-and-path');
  Check((Length(Uri.Params) = 2) and (Uri.Query = 'filter=room%207&mode=old') and (Uri.Parameter[1].Value = 'old'),
    'breadth-endpoint-preserves-wire-query-and-parameter-order');

  Uri.ParameterByName['mode'] := 'live';
  Uri.AddParameter('region', 'eu-west');
  Wire := Uri.ToString;
  Check(Wire = Updated, 'breadth-endpoint-edits-options-without-changing-filter-or-port');
  Restored := TURI.Create(Wire);
  Check((Restored.ParameterByName['mode'] = 'live') and (Restored.Parameter[2].Value = 'eu-west'),
    'breadth-endpoint-edited-url-recovers-new-options');
  Mix(UInt64(Length(Wire)));
end;
{$endif}
