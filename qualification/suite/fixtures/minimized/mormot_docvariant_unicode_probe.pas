program mormot_docvariant_unicode_probe;

{$mode delphiunicode}

uses
  mormot.core.fpcx64mm,
{$ifdef unix}
  cthreads,
{$endif}
  SysUtils,
  StrUtils,
  Variants,
  mormot.core.base,
  mormot.core.variants;

var
  Doc: Variant;
  Data: Variant;
  Text: UnicodeString;
  ServerTime: UInt64;
begin
  Doc := _Json('{"channel":"post","data":{"id":123,"response":' +
    '{"type":"info","payload":{"type":"l2Book","data":' +
    '{"coin":"BTC","time":456,"levels":[]}}}}}');
  Data := Doc.data.response.payload.data;
  if Data = Null then
    Halt(1);
  Text := Data;
  if not ContainsText(Text, '"coin":"BTC"') then
    Halt(2);
  if not ContainsText(Doc.data.response.payload.data, '}') then
    Halt(3);
  ServerTime := Doc.data.response.payload.data.time;
  if ServerTime <> 456 then
    Halt(4);
  Writeln('PASS mormot-docvariant-unicode');
end.
