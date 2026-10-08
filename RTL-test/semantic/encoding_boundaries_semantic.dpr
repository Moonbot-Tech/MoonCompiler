program encoding_boundaries_semantic;
{$APPTYPE CONSOLE}
{$IFDEF FPC}{$mode delphiunicode}{$ENDIF}
uses
  {$IFDEF UNIX}cthreads, cwstring,{$ENDIF}
  SysUtils, Classes, System.NetEncoding;

type
  TChunkStream = class(TBytesStream)
    Chunk: Integer;
    function Read(var Buffer; Count: LongInt): LongInt; override;
  end;

function TChunkStream.Read(var Buffer; Count: LongInt): LongInt;
begin
  if Count>Chunk then Count:=Chunk;
  Result:=inherited Read(Buffer,Count);
end;

procedure Check(Value: Boolean; const Context: string);
begin
  if not Value then raise Exception.Create(Context);
end;

procedure EqualBytes(const Actual, Expected: TBytes; const Context: string);
begin
  Check(Length(Actual)=Length(Expected),Context+' length');
  if Length(Actual)>0 then
    Check(CompareMem(@Actual[0],@Expected[0],Length(Actual)),Context+' bytes');
end;

procedure CheckBase64;
var
  Data, Encoded, Actual: TBytes;
  Text: string;
  Raw: RawByteString;
  Source: TChunkStream;
  Dest: TBytesStream;
  N, I, Chunk: Integer;
begin
  for N:=0 to 130 do
  begin
    SetLength(Data,N);
    for I:=0 to N-1 do Data[I]:=Byte((I*61+251) and 255);
    Text:=TNetEncoding.Base64URL.EncodeBytesToString(Data);
    Check((Pos('=',Text)=0) and (Pos(#13,Text)=0) and (Pos(#10,Text)=0),'URL framing');
    Check((Pos('+',Text)=0) and (Pos('/',Text)=0),'URL alphabet');
    EqualBytes(TNetEncoding.Base64URL.DecodeStringToBytes(Text),Data,'URL string');
    Encoded:=TEncoding.ASCII.GetBytes(Text);
    EqualBytes(TNetEncoding.Base64URL.Decode(Encoded),Data,'URL array');
    Raw:=RawByteString(Text);
    Raw:=TNetEncoding.Base64URL.Decode(Raw);
    Check(Length(Raw)=N,'URL raw string length');
    if N>0 then Check(CompareMem(@Raw[1],@Data[0],N),'URL raw string data');
    for Chunk:=1 to 5 do
    begin
      Source:=TChunkStream.Create(Encoded);
      Dest:=TBytesStream.Create;
      try
        Source.Chunk:=Chunk;
        Check(TNetEncoding.Base64URL.Decode(Source,Dest)=N,'URL stream count');
        Actual:=Copy(Dest.Bytes,0,Dest.Size);
        EqualBytes(Actual,Data,'URL chunk stream');
      finally
        Dest.Free;
        Source.Free;
      end;
    end;
    EqualBytes(TNetEncoding.Base64.DecodeStringToBytes(
      TNetEncoding.Base64.EncodeBytesToString(Data)),Data,'MIME control');
  end;
  Check(TNetEncoding.Base64URL.EncodeBytesToString(TBytes.Create($FB))='-w','one-byte URL vector');
  Check(TNetEncoding.Base64URL.EncodeBytesToString(TBytes.Create($FB,$FF))='-_8','two-byte URL vector');
end;

procedure CheckStrict;
const
  Bad: array[0..7] of RawByteString = (#$C3#$28, #$C0#$AF, #$ED#$A0#$80,
    #$F4#$90#$80#$80, #$F0#$9F, #$80, #$FF, #$E0#$80#$80);
var
  Encoding, Clone: TEncoding;
  Bytes: TBytes;
  Text: UnicodeString;
  I, J: Integer;
  Raised: Boolean;
begin
  Encoding:=TMBCSEncoding.Create(65001,8,$80);
  Clone:=Encoding.Clone;
  try
    Text:='A'+UnicodeChar($03BB)+UnicodeChar($D83D)+UnicodeChar($DE00)+#0+'Z';
    Bytes:=Encoding.GetBytes(Text);
    Check(Clone.GetString(Bytes)=Text,'strict valid Unicode roundtrip');
    for I:=Low(Bad) to High(Bad) do
    begin
      SetLength(Bytes,Length(Bad[I]));
      Move(Bad[I][1],Bytes[0],Length(Bytes));
      for J:=0 to 2 do
      begin
        Raised:=False;
        try
          case J of
            0: Encoding.GetCharCount(Bytes);
            1: Encoding.GetString(Bytes);
            2: Clone.GetChars(Bytes);
          end;
        except on E: EEncodingError do Raised:=True; end;
        Check(Raised,'strict malformed UTF8 was accepted');
      end;
    end;
    for I:=0 to 2 do
    begin
      case I of
        0: Text:=UnicodeChar($D800);
        1: Text:=UnicodeChar($DC00);
        2: Text:=UnicodeChar($D800)+'x';
      end;
      Raised:=False;
      try Encoding.GetBytes(Text); except on E: EEncodingError do Raised:=True; end;
      Check(Raised,'strict unmatched surrogate was accepted');
    end;
    Check(Length(Encoding.GetBytes(''))=0,'strict empty input');
  finally
    Clone.Free;
    Encoding.Free;
  end;
end;

procedure CheckStreamBoundaries;
const
  Pages: array[0..2] of Integer = (932,936,65001);
var
  Encoding: TEncoding;
  Source: TChunkStream;
  Reader: TStreamReader;
  Bytes: TBytes;
  Expected: UnicodeString;
  P, Chunk: Integer;
begin
  for P in Pages do
  begin
    Encoding:=TEncoding.GetEncoding(P);
    try
      Expected:=StringOfChar('x',127)+UnicodeChar($3042)+#0+UnicodeChar($3042)+'z';
      Bytes:=Encoding.GetBytes(Expected);
      Check(Encoding.GetString(Bytes)=Expected,'codepage fixture roundtrip');
      for Chunk:=1 to 130 do
      begin
        Source:=TChunkStream.Create(Bytes);
        Source.Chunk:=Chunk;
        try
          Reader:=TStreamReader.Create(Source,Encoding,False,128);
          try
            Check(Reader.ReadToEnd=Expected,'split multibyte text');
          finally Reader.Free; end;
        finally Source.Free; end;
      end;
    finally Encoding.Free; end;
  end;
end;

begin
  CheckBase64;
  CheckStrict;
  CheckStreamBoundaries;
  WriteLn('ENCODING_BOUNDARIES_PASS');
end.
