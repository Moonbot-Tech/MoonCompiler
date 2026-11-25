{$ifdef BREADTH_HAS_PRODUCT_IO}
{ Following a relative link on an IPv6 endpoint must keep the literal host and explicit port. }

procedure RunBreadthIPv6ReportLink;
const
  Stored = 'https://[2001:db8::7]:8443/v1/calendar?route=active#grid';
  Expected = 'https://[2001:db8::7]:8443/summary?mode=full#end';
var
  Uri, Resolved: TURI;
  Target: string;
begin
  Uri := TURI.Create(Stored);
  Check((Uri.Host = '[2001:db8::7]') and (Uri.Port = 8443) and (Uri.Path = '/v1/calendar') and (Uri.Fragment = 'grid'),
    'breadth-ipv6-report-link-loads-literal-authority-and-application-path');
  Check(Uri.ToString = Stored, 'breadth-ipv6-report-link-rebuilds-exact-stored-address');
  Target := TURI.PathRelativeToAbs('../summary?mode=full#end', Uri);
  Check(Target = Expected, 'breadth-ipv6-report-link-resolves-relative-path-and-keeps-authority');
  Resolved := TURI.Create(Target);
  Check((Resolved.ParameterByName['mode'] = 'full') and (Resolved.Fragment = 'end') and (Uri.Fragment = 'grid'),
    'breadth-ipv6-report-link-resolves-new-query-and-fragment-without-editing-base');
  Mix(UInt64(Length(Target)));
end;
{$endif}
