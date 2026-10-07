program url_components_contract_semantic;
{$IFDEF FPC}{$mode delphiunicode}{$H+}{$ENDIF}
{$APPTYPE CONSOLE}
uses
  {$IFDEF FPC}mormot.core.fpcx64mm,{$IFDEF UNIX}cthreads,cwstring,{$ENDIF}{$ENDIF}
  System.SysUtils, System.NetEncoding;
procedure Check(OK: Boolean; const Name: string);
begin
  if not OK then raise Exception.Create('URL_COMPONENTS: '+Name);
end;
var
  URL: TURLEncoding;
  Latin: TEncoding;
  S: string;
  I: Integer;
begin
  URL:=TNetEncoding.URL;
  Check(URL.EncodePath('/a//b/')='/a//b/','preserve separators');
  Check(URL.EncodePath('///')='///','only separators');
  Check(URL.EncodePath('')='/','empty path');
  Check(URL.EncodePath('a b?c')='/a%20b%3Fc','path spaces');
  Check(URL.EncodePath('a+b c')='/a+b%20c','path plus');
  Check(URL.EncodePath('%2F%ZZ',[Ord('%')])='/%2F%25ZZ','path percent policy');
  Check(URL.EncodePath('a@b',[Ord('@')])='/a%40b','additional unsafe');
  Check(URL.EncodeQuery('a+b c')='a+b%20c','query plus');
  Check(URL.EncodeForm('a+b c')='a%2Bb+c','form plus');
  Check(URL.URLDecode('a+b%2Bc')='a+b+c','URL plus is data');
  Check(URL.FormDecode('a+b%2Bc')='a b+c','form plus is space');
  Check(URL.EncodeAuth('a:b+c@d e')='a%3Ab+c%40d%20e','authentication component');
  S:='';
  for I:=32 to 126 do S:=S+Char(I);
  Check(URL.EncodePath(S)='/%20!%22%23$%&''()*+,-./0123456789:;%3C=%3E%3F@ABCDEFGHIJKLMNOPQRSTUVWXYZ[%5C]%5E_%60abcdefghijklmnopqrstuvwxyz%7B%7C%7D~','path ASCII oracle');
  Check(URL.EncodeForm(S)='+%21%22%23%24%25%26%27%28%29*%2B%2C-.%2F0123456789%3A%3B%3C%3D%3E%3F%40ABCDEFGHIJKLMNOPQRSTUVWXYZ%5B%5C%5D%5E_%60abcdefghijklmnopqrstuvwxyz%7B%7C%7D%7E','form ASCII oracle');
  Check(URL.EncodePath(Char($20ac))='/%E2%82%AC','UTF8');
  Check(URL.FormDecode('%E2%82%AC')=Char($20ac),'UTF8 decode');
  Latin:=TEncoding.GetEncoding(1252);
  try
    Check(URL.EncodeForm(Char($e9),[],Latin)='%E9','explicit encoding');
    Check(URL.FormDecode('%E9',Latin)=Char($e9),'explicit decoding');
  finally Latin.Free; end;
  Check(URL.URLDecode('%ZZ%')='%ZZ%','malformed escape preserved');
  WriteLn('URL_COMPONENTS_CONTRACT_PASS');
end.
