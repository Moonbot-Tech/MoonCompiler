program iso8601_validation_semantic;
{$mode delphiunicode}{$H+}
uses mormot.core.fpcx64mm, {$IFDEF UNIX}cthreads,cwstring,{$ENDIF}
  System.SysUtils, System.DateUtils;
procedure Check(OK: Boolean; const Name: string);
begin
  if not OK then raise Exception.Create('ISO_VALIDATION: '+Name);
end;
procedure Invalid(const Offset: string);
var D: TDateTime; Raised: Boolean; N: Integer;
begin
  Check(not TryISOTZStrToTZOffset(Offset,N),'invalid timezone '+Offset);
  Check(not TryISO8601ToDate('2024-01-01T00:00:00'+Offset,D),'Try rejects '+Offset);
  Raised:=False;
  try D:=ISO8601ToDate('2024-01-01T00:00:00'+Offset); except on E:EConvertError do Raised:=True; end;
  Check(Raised,'raising wrapper '+Offset);
end;
var D: TDateTime; H,M: Integer; Offset: string;
begin
  Check(TryISO8601ToDate('2024-01-01T01:00:00+02:30',D),'valid offset');
  Check(Abs(D-EncodeDateTime(2023,12,31,22,30,0,0))<1E-9,'day rollover');
  Check(TryISO8601ToDate('2024-01-01T01:00:00+0230',D),'compact offset');
  Check(TryISO8601ToDate('2024-01-01T01:00:00-02',D),'hour offset');
  Check(Abs(D-EncodeDateTime(2024,1,1,3,0,0,0))<1E-9,'negative offset');
  for H:=0 to 23 do
    for M:=0 to 59 do begin
      Offset:='+'+Format('%.2d:%.2d',[H,M]);
      Check(TryISO8601ToDate('2024-02-29T12:00:00'+Offset,D),'valid offset grid');
    end;
  Invalid('+25:00'); Invalid('+24:00'); Invalid('+00:60'); Invalid('-00:99');
  Invalid('+02x30'); Invalid('+ 2'); Invalid('+2 '); Invalid('+0+');
  WriteLn('ISO8601_VALIDATION_PASS');
end.
