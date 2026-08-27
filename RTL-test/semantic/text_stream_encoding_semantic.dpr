program text_stream_encoding_semantic;

{$mode delphiunicode}{$H+}
{$codepage utf8}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}cthreads,cwstring,{$endif UNIX}
  SysUtils, Classes, StreamEx, System.IOUtils;

type
  TOneByteReadStream = class(TMemoryStream)
  public
    function Read(var Buffer; Count: LongInt): LongInt; override;
  end;

  TShortWriteStream = class(TMemoryStream)
  public
    function Write(const Buffer; Count: LongInt): LongInt; override;
  end;

var
  Fails: Integer = 0;

procedure Check(const Name: AnsiString; Condition: Boolean);
begin
  If not Condition then begin
    WriteLn('FAIL ',Name);
    Inc(Fails);
  end;
end;

procedure CheckBytes(const Name: AnsiString; const Actual, Expected: TBytes);
var
  I: Integer;
begin
  If Length(Actual)<>Length(Expected) then begin
    WriteLn('BYTE_LENGTH ',Name,' actual=',Length(Actual),' expected=',Length(Expected));
    Check(Name,False);
    Exit;
  end;
  For I:=0 to High(Actual) do
    If Actual[I]<>Expected[I] then begin
      WriteLn('BYTE_VALUE ',Name,' index=',I,' actual=',Actual[I],
        ' expected=',Expected[I]);
      Check(Name,False);
      Exit;
    end;
end;

function TOneByteReadStream.Read(var Buffer; Count: LongInt): LongInt;
begin
  If Count>1 then
    Count:=1;
  Result:=inherited Read(Buffer,Count);
end;

function TShortWriteStream.Write(const Buffer; Count: LongInt): LongInt;
begin
  If Count>0 then
    Dec(Count);
  Result:=inherited Write(Buffer,Count);
end;

procedure PutBytes(Stream: TMemoryStream; const Bytes: TBytes);
begin
  Stream.Clear;
  If Length(Bytes)>0 then
    Stream.WriteBuffer(Bytes[0],Length(Bytes));
  Stream.Position:=0;
end;

function StreamBytes(Stream: TMemoryStream): TBytes;
begin
  Result:=nil;
  SetLength(Result,Stream.Size);
  If Stream.Size>0 then
    Move(Stream.Memory^,Result[0],Stream.Size);
end;

function WithPreamble(Encoding: TEncoding; const Text: UnicodeString): TBytes;
var
  Body, Preamble: TBytes;
begin
  Result:=nil;
  Preamble:=Encoding.GetPreamble;
  Body:=Encoding.GetBytes(Text);
  SetLength(Result,Length(Preamble)+Length(Body));
  If Length(Preamble)>0 then
    Move(Preamble[0],Result[0],Length(Preamble));
  If Length(Body)>0 then
    Move(Body[0],Result[Length(Preamble)],Length(Body));
end;

procedure TestStringStream;
var
  Stream: TStringStream;
begin
  Stream:=TStringStream.Create(UnicodeString('Ж€'),TEncoding.UTF8,False);
  try
    Check('tstringstream-native',Stream.ReadString(Stream.Size)='Ж€');
    Stream.Position:=-1;
    Check('tstringstream-negative',(Stream.ReadString(4)='') and
      (Stream.Position=-1));
    Stream.Position:=Stream.Size+1;
    Check('tstringstream-past-end',(Stream.ReadString(4)='') and
      (Stream.Position=Stream.Size+1));
  finally
    Stream.Free;
  end;
end;

procedure TestStringsRoundTrip;
var
  Bytes: TBytes;
  Lines: TStringList;
  Stream: TMemoryStream;
begin
  Lines:=TStringList.Create;
  Stream:=TMemoryStream.Create;
  try
    Lines.Text:='Ж€'+LineEnding+'x'+#0+'y';
    Lines.WriteBOM:=True;
    Lines.SaveToStream(Stream,TEncoding.UTF8);
    Bytes:=StreamBytes(Stream);
    Stream.Position:=0;
    Lines.Clear;
    Lines.LoadFromStream(Stream,TEncoding.UTF8);
    Check('strings-utf8-roundtrip',Lines.Text='Ж€'+LineEnding+'x'+#0+'y'+LineEnding);
    Check('strings-utf8-bom',(Length(Bytes)>=3) and (Bytes[0]=$ef) and
      (Bytes[1]=$bb) and (Bytes[2]=$bf));

    PutBytes(Stream,WithPreamble(TEncoding.BigEndianUnicode,'Ж€'+LineEnding));
    Lines.Clear;
    Lines.LoadFromStream(Stream,nil);
    Check('strings-utf16be',Lines.Text='Ж€'+LineEnding);
  finally
    Stream.Free;
    Lines.Free;
  end;
end;

procedure TestStreamReader;
var
  Bytes, Prefix, TextBytes: TBytes;
  I: Integer;
  Line, LongLine: RTLString;
  Reader: TStreamReader;
  Stream: TOneByteReadStream;
begin
  SetLength(Prefix,127);
  For I:=0 to High(Prefix) do
    Prefix[I]:=Ord('a');
  TextBytes:=TEncoding.UTF8.GetBytes(UnicodeString('€'+#0+'z'+#13#10+'next'));
  Bytes:=TEncoding.UTF8.GetPreamble;
  I:=Length(Bytes);
  SetLength(Bytes,I+Length(Prefix)+Length(TextBytes));
  Move(Prefix[0],Bytes[I],Length(Prefix));
  Move(TextBytes[0],Bytes[I+Length(Prefix)],Length(TextBytes));

  Stream:=TOneByteReadStream.Create;
  PutBytes(Stream,Bytes);
  Reader:=TStreamReader.Create(Stream,TEncoding.ASCII,True,128);
  try
    Reader.ReadLine(Line);
    Check('reader-utf8-boundary',Length(Line)=130);
    Check('reader-utf8-euro',Line[128]='€');
    Check('reader-embedded-nul',(Line[129]=#0) and (Line[130]='z'));
    Check('reader-crlf',Reader.ReadLine='next');
    Check('reader-eof',Reader.EndOfStream);
    Check('reader-detected-encoding',Reader.CurrentEncoding.CodePage=CP_UTF8);
    PutBytes(Stream,TEncoding.ASCII.GetBytes('plain'));
    Reader.Reset;
    Check('reader-reset-text',Reader.ReadLine='plain');
    Check('reader-reset-encoding',Reader.CurrentEncoding.CodePage=TEncoding.ASCII.CodePage);
  finally
    Reader.Free;
    Stream.Free;
  end;

  LongLine:=StringOfChar('b',300);
  Stream:=TOneByteReadStream.Create;
  PutBytes(Stream,TEncoding.UTF8.GetBytes(UnicodeString('first'+#10+
    LongLine+#10+'last')));
  Reader:=TStreamReader.Create(Stream,False);
  try
    Check('reader-first-short-line',Reader.ReadLine='first');
    Check('reader-second-line-crosses-buffer',Reader.ReadLine=LongLine);
    Check('reader-after-crossed-buffer',Reader.ReadLine='last');
  finally
    Reader.Free;
    Stream.Free;
  end;

  Stream:=TOneByteReadStream.Create;
  PutBytes(Stream,WithPreamble(TEncoding.Unicode,'Ж'+#10));
  Reader:=TStreamReader.Create(Stream,TEncoding.Unicode,False,128);
  try
    Check('reader-utf16le',Reader.ReadLine='Ж');
  finally
    Reader.Free;
    Stream.Free;
  end;

  Stream:=TOneByteReadStream.Create;
  Bytes:=TEncoding.ASCII.GetBytes('xx');
  Stream.WriteBuffer(Bytes[0],Length(Bytes));
  Bytes:=WithPreamble(TEncoding.BigEndianUnicode,'€'+#10);
  Stream.WriteBuffer(Bytes[0],Length(Bytes));
  Stream.Position:=2;
  Reader:=TStreamReader.Create(Stream,TEncoding.UTF8,True,128);
  try
    Check('reader-nonzero-position',Reader.ReadLine='€');
    Check('reader-utf16be-detect',Reader.CurrentEncoding.CodePage=CP_UTF16BE);
  finally
    Reader.Free;
    Stream.Free;
  end;
end;

procedure TestStringReader;
var
  Reader: TStringReader;
begin
  Reader:=TStringReader.Create('Ж€'+#10+'next');
  try
    Check('string-reader-unicode',Reader.ReadLine='Ж€');
    Check('string-reader-next',Reader.ReadLine='next');
  finally
    Reader.Free;
  end;
end;

procedure TestStreamWriter;
var
  Bytes, Expected: TBytes;
  Name: string;
  Raised: Boolean;
  Stream: TMemoryStream;
  ShortStream: TShortWriteStream;
  Writer: TStreamWriter;
  X: Byte;
begin
  Stream:=TMemoryStream.Create;
  Writer:=TStreamWriter.Create(Stream,TEncoding.UTF8,128);
  try
    Writer.Write(UnicodeString('Ж€'));
    Bytes:=StreamBytes(Stream);
    Expected:=WithPreamble(TEncoding.UTF8,'Ж€');
    CheckBytes('writer-unicode-bytes',Bytes,Expected);
  finally
    Writer.Free;
    Stream.Free;
  end;

  Stream:=TMemoryStream.Create;
  Writer:=TStreamWriter.Create(Stream);
  try
    Writer.Write(UnicodeString('Ж'));
    Bytes:=StreamBytes(Stream);
    Expected:=TEncoding.UTF8.GetBytes(UnicodeString('Ж'));
    CheckBytes('writer-default-unicode',Bytes,Expected);
  finally
    Writer.Free;
    Stream.Free;
  end;

  Stream:=TMemoryStream.Create;
  X:=Ord('x');
  Stream.WriteBuffer(X,1);
  Writer:=TStreamWriter.Create(Stream,TEncoding.UTF8,128);
  try
    Writer.Write(UnicodeString('Ж'));
    Bytes:=StreamBytes(Stream);
    Expected:=TEncoding.UTF8.GetBytes(UnicodeString('xЖ'));
    CheckBytes('writer-nonzero-no-preamble',Bytes,Expected);
  finally
    Writer.Free;
    Stream.Free;
  end;

  Stream:=TMemoryStream.Create;
  Writer:=TStreamWriter.Create(Stream,TEncoding.BigEndianUnicode,128);
  try
    Writer.Write(UnicodeString('Ж€'));
    Bytes:=StreamBytes(Stream);
    Expected:=WithPreamble(TEncoding.BigEndianUnicode,'Ж€');
    CheckBytes('writer-utf16be',Bytes,Expected);
  finally
    Writer.Free;
    Stream.Free;
  end;

  ShortStream:=TShortWriteStream.Create;
  Writer:=TStreamWriter.Create(ShortStream,TEncoding.ASCII,128);
  try
    Raised:=False;
    try
      Writer.Write('x');
    except
      on EWriteError do
        Raised:=True;
    end;
    Check('writer-short-write-raises',Raised);
  finally
    Writer.Free;
    ShortStream.Free;
  end;

  Name:=TPath.Combine(TPath.GetTempPath,'mooncompiler-stream-writer-'+
    IntToHex(GetTickCount64,16)+'.txt');
  try
    Writer:=TStreamWriter.Create(Name,False);
    try
      Writer.Write(UnicodeString('Ж'));
    finally
      Writer.Free;
    end;
    Bytes:=TFile.ReadAllBytes(Name);
    Expected:=TEncoding.UTF8.GetBytes(UnicodeString('Ж'));
    CheckBytes('writer-default-file-no-preamble',Bytes,Expected);

    Writer:=TStreamWriter.Create(Name,False,TEncoding.UTF8,128);
    try
      Writer.Write(UnicodeString('Ж'));
    finally
      Writer.Free;
    end;
    Bytes:=TFile.ReadAllBytes(Name);
    Expected:=WithPreamble(TEncoding.UTF8,'Ж');
    CheckBytes('writer-explicit-file-preamble',Bytes,Expected);
  finally
    If TFile.Exists(Name) then
      TFile.Delete(Name);
  end;
end;

procedure TestIOUtils;
var
  Bytes: TBytes;
  Expected, Name: string;
begin
  Name:=TPath.Combine(TPath.GetTempPath,'mooncompiler-text-stream-'+
    IntToHex(GetTickCount64,16)+'.txt');
  try
    Bytes:=WithPreamble(TEncoding.BigEndianUnicode,'Ж€'+#0+'z');
    TFile.WriteAllBytes(Name,Bytes);
    Check('ioutils-detect-bom',TFile.ReadAllText(Name)='Ж€'+#0+'z');
    Check('ioutils-explicit-own-bom',
      TFile.ReadAllText(Name,TEncoding.BigEndianUnicode)='Ж€'+#0+'z');

    Bytes:=TEncoding.UTF8.GetBytes(UnicodeString('Ж€'));
    TFile.WriteAllBytes(Name,Bytes);
    Check('ioutils-explicit-no-bom',
      TFile.ReadAllText(Name,TEncoding.UTF8)='Ж€');

    SetLength(Bytes,1);
    Bytes[0]:=$ff;
    TFile.WriteAllBytes(Name,Bytes);
    Expected:=TEncoding.ANSI.GetString(Bytes);
    Check('ioutils-invalid-utf8-ansi-fallback',TFile.ReadAllText(Name)=Expected);
  finally
    If TFile.Exists(Name) then
      TFile.Delete(Name);
  end;
end;

begin
  TestStringStream;
  TestStringsRoundTrip;
  TestStreamReader;
  TestStringReader;
  TestStreamWriter;
  TestIOUtils;
  If Fails<>0 then
    Halt(1);
  WriteLn('TEXT_STREAM_ENCODING_PASS');
end.
