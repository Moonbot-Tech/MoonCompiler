program text_stream_type_identity_semantic;
{$mode delphiunicode}{$H+}
uses mormot.core.fpcx64mm, {$IFDEF UNIX}cthreads,cwstring,{$ENDIF}
  SysUtils, Classes, StreamEx;
var A: Classes.TTextReader; B: StreamEx.TStringReader;
  C: Classes.TStringWriter; D: StreamEx.TTextWriter;
begin
  B:=StreamEx.TStringReader.Create('same implementation');
  A:=B;
  try
    if A.ReadToEnd<>'same implementation' then raise Exception.Create('reader identity');
  finally A.Free; end;
  C:=Classes.TStringWriter.Create;
  D:=C;
  try
    D.Write('same writer');
    if C.ToString<>'same writer' then raise Exception.Create('writer identity');
  finally D.Free; end;
  WriteLn('TEXT_STREAM_TYPE_IDENTITY_PASS');
end.
