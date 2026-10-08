program base64_size_boundaries_semantic;
{$APPTYPE CONSOLE}
{$mode delphiunicode}
uses SysUtils, Classes, Base64;
procedure Check(Value: Boolean; const Context: string);
begin
  if not Value then raise Exception.Create(Context);
end;
const
  Input: array[0..8] of RawByteString = ('','S','SA','SGk','SGk=','SGk=ignored','SGk'+#13#10,'-___','SGVsbG8');
  Expected: array[0..8] of RawByteString = ('','','H','Hi','Hi','Hi','Hi',#$FB#$FF#$FF,'Hello');
var Source: TBytesStream; Decoder: TBase64URLDecodingStream; I, Count: Integer; Output: RawByteString;
begin
  for I:=0 to High(Input) do
  begin
    Source:=TBytesStream.Create;
    try
      if Input[I]<>'' then Source.WriteBuffer(Input[I][1],Length(Input[I]));
      Source.Position:=0;
      Decoder:=TBase64URLDecodingStream.Create(Source,bdmMIME);
      try
        Check(Decoder.Size=Length(Expected[I]),'size before read');
        Check(Source.Position=0,'size restores input position');
        SetLength(Output,32);
        Count:=Decoder.Read(Output[1],Length(Output));
        SetLength(Output,Count);
        Check(Output=Expected[I],'read after size');
        Check(Decoder.Size=Count,'size after read');
      finally Decoder.Free; end;
    finally Source.Free; end;
  end;
  WriteLn('BASE64_SIZE_BOUNDARIES_PASS');
end.
