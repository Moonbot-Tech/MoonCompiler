program rtl_api_product_semantic;

{$mode delphi}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  cwstring,
  {$endif UNIX}
  System.SysUtils,
  System.Classes,
  System.Threading,
  System.Hash,
  System.NetEncoding;

procedure Check(aCondition: Boolean; const aMessage: string);
begin
  if not aCondition then
    raise Exception.Create('RTL_API_PRODUCT_FAIL: '+aMessage);
end;

procedure CheckTaskAndParallel;
var
  I,Value: Integer;
  LoopResult: TParallel.TLoopResult;
  Task: ITask;
  Visited: array of Boolean;
begin
  Value:=0;
  Task:=TTask.Create(
    procedure
    begin
      Value:=42;
    end);
  Task.Start;
  Check(Task.Wait(2000),'TTask.Create/Start/Wait');
  Check(Value=42,'TTask.Create body');

  SetLength(Visited,32);
  LoopResult:=TParallel.&For(0,High(Visited),
    procedure(aIndex: Integer)
    begin
      Visited[aIndex]:=True;
    end);
  Check(LoopResult.Completed,'TParallel.For completion');
  for I:=0 to High(Visited) do
    Check(Visited[I],'TParallel.For index '+IntToStr(I));
end;

procedure CheckHashAndEncoding;
const
  Hmac256 = '5031fe3d989c6d1537a013fa6e739da23463fdaec3b70137d828e36ace221bd0';
  Hmac512 = '3c5953a18f7303ec653ba170ae334fafa08e3846f2efe317b87efce82376253c'+
    'b52a8c31ddcde5a3a2eee183c2b34cb91f85e64ddbc325f7692b199473579c58';
  SHA512_224_ABC = '4634270f707b6a54daae7530460842e20e37ed265ceee9a43e8924aa';
  SHA512_256_ABC = '53048e2681941ef99b2e29b76b4c7dabe4c2d0c634fc6d46e0e2f13107e7af23';
  Hmac512_224 = '8b6657a9d03419b965477ba8149782c7d8e58ac4c79a9646e191c1d5';
  Hmac512_256 = 'e1d10dee05c387bc0407b77dead2b0626e46d9993ab3a6157cabc805c84f0e09';
var
  Decoded,Encoded: string;
begin
  Check(SameText(THashSHA2.GetHMAC('data','key',THashSHA2.TSHA2Version.SHA256),
    Hmac256),'SHA-256 HMAC');
  Check(SameText(THashSHA2.GetHMAC('data','key',THashSHA2.TSHA2Version.SHA512),
    Hmac512),'SHA-512 HMAC');
  Check(SameText(THashSHA2.GetHashString('abc',
    THashSHA2.TSHA2Version.SHA512_224),SHA512_224_ABC),'SHA-512/224');
  Check(SameText(THashSHA2.GetHashString('abc',
    THashSHA2.TSHA2Version.SHA512_256),SHA512_256_ABC),'SHA-512/256');
  Check(SameText(THashSHA2.GetHMAC('data','key',
    THashSHA2.TSHA2Version.SHA512_224),Hmac512_224),'SHA-512/224 HMAC');
  Check(SameText(THashSHA2.GetHMAC('data','key',
    THashSHA2.TSHA2Version.SHA512_256),Hmac512_256),'SHA-512/256 HMAC');

  Encoded:=TNetEncoding.Base64.Encode('Moon');
  Check(Encoded='TW9vbg==','Base64 encode');
  Check(TNetEncoding.Base64.Decode(Encoded)='Moon','Base64 decode');
  Check(TNetEncoding.URL.Encode('Moon '+#$0416)='Moon+%D0%96',
    'URL UTF-8 encode');
  Encoded:='Moon%20%D0%96';
  Decoded:=TNetEncoding.URL.Decode(UnicodeString(Encoded));
  Check(Decoded='Moon '+#$0416,'URL UTF-8 decode');
end;

begin
  CheckTaskAndParallel;
  CheckHashAndEncoding;
  WriteLn('RTL_API_PRODUCT_PASS');
end.
