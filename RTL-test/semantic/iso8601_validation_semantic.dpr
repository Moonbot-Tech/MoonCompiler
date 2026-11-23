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

procedure ExpectDate(const Text: string; Expected: TDateTime);
var D: TDateTime;
begin
  Check(TryISO8601ToDate(Text,D), 'parse '+Text);
  Check(Abs(D-Expected)<1E-9, 'UTC value '+Text);
  Check(Abs(ISO8601ToDate(Text)-Expected)<1E-9, 'raising wrapper '+Text);
end;

procedure RejectDate(const Text: string);
var D: TDateTime;
begin
  Check(not TryISO8601ToDate(Text,D), 'reject '+Text);
  Check(ISO8601ToDateDef(Text,-123.0)=-123.0, 'default on invalid '+Text);
end;

var D: TDateTime; H,M: Integer; Offset: string;
begin
  ExpectDate('2024-01-01T24:00:00Z',EncodeDate(2024,1,2));
  ExpectDate('2023-12-31T24:00Z',EncodeDate(2024,1,1));
  ExpectDate('20240229T240000Z',EncodeDate(2024,3,1));
  ExpectDate('2024-001T24:01:00.125+02:00',EncodeDateTime(2024,1,1,22,1,0,125));
  ExpectDate('2024-01-01T24:59:60Z',EncodeDateTime(2024,1,2,1,0,0,0));
  ExpectDate('2024-W01-1',EncodeDate(2024,1,1));
  ExpectDate('2020W01',EncodeDate(2019,12,30));
  ExpectDate('2020-W1-7',EncodeDate(2020,1,5));
  ExpectDate('2020W537T2400-02',EncodeDateTime(2021,1,4,2,0,0,0));
  ExpectDate('2024-001',EncodeDate(2024,1,1));
  ExpectDate('2024060',EncodeDate(2024,2,29));
  ExpectDate('2024-366',EncodeDate(2024,12,31));
  ExpectDate('1900-060',EncodeDate(1900,3,1));
  ExpectDate('2024-01-01 12:30',EncodeDateTime(2024,1,1,12,30,0,0));
  ExpectDate('2024-01-01Z',EncodeDate(2024,1,1));
  ExpectDate('T12:30',EncodeTime(12,30,0,0));
  ExpectDate('T23:59:60Z',1.0);
  ExpectDate('T235960.5Z',1.0+0.5*OneSecond);
  Check(TryISO8601ToDate('1899-12-29T23:59:59.999999Z',D),'fraction near epoch');
  Check(PQWord(@D)^=$3DA973A000000000,'preserve SDK fractional rounding');
  Check(TryISO8601ToDate('2024-W01-1T24:00:00+02:30',D,False),'week date to local');
  Check(Abs(D-UniversalTimeToLocal(EncodeDateTime(2024,1,1,21,30,0,0)))<1E-9,'local value after UTC rollover');
  RejectDate('2021-W53-1'); RejectDate('2024-W00-1'); RejectDate('2024-W01-0');
  RejectDate('2024W018'); RejectDate('2024-W1-01'); RejectDate('2024-W011');
  RejectDate('0000-W01-1'); RejectDate('0000-001'); RejectDate('2024-000');
  RejectDate('2023-366'); RejectDate('2024-367'); RejectDate('2024-$01');
  RejectDate('2024-001T25:00Z'); RejectDate('2024-W01-1T24:60Z');
  RejectDate('2024-001T24:00:61Z'); RejectDate('2024-001T24:00:00+99');
  RejectDate('2024-001T24:00:00+01+02'); RejectDate('T'); RejectDate('T+');
  RejectDate('T24:00'); RejectDate('2024-001Z'); RejectDate('2024-W01-1Z');
  RejectDate('2024-W01-1 12:30'); RejectDate('2024-001 12:30'); RejectDate('2024-001T24');
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
