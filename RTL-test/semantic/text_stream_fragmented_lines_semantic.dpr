program text_stream_fragmented_lines_semantic;

{$mode delphiunicode}{$H+}
{$codepage utf8}

uses
  {$ifdef UNIX}cthreads, cwstring,{$endif}
  SysUtils, Classes;

type
  TFragmentStream = class(TMemoryStream)
  public
    Limit, FailAfter, CloseAfter, Calls: Integer;
    Reader: TStreamReader;
    function Read(var Buffer; Count: LongInt): LongInt; override;
  end;

function TFragmentStream.Read(var Buffer; Count: LongInt): LongInt;
begin
  Inc(Calls);
  If (FailAfter>0) and (Calls>FailAfter) then
    raise EReadError.Create('fixture read failure');
  If (Limit>0) and (Count>Limit) then
    Count:=Limit;
  Result:=inherited Read(Buffer,Count);
  If (CloseAfter>0) and (Calls=CloseAfter) then
    Reader.Close;
end;

procedure Check(Condition: Boolean; const Context: string);
begin
  If not Condition then begin
    Writeln('FAIL ',Context);
    Halt(1);
  end;
end;

procedure CheckLines(const Text: UnicodeString; Encoding: TEncoding; Fragment, BufferSize: Integer);
var
  Bytes: TBytes;
  Stream: TFragmentStream;
  Reader: TStreamReader;
  Actual, Expected: UnicodeString;
  I, Start, Pass: Integer;
begin
  Bytes:=Encoding.GetBytes(Text);
  Stream:=TFragmentStream.Create;
  Stream.Limit:=Fragment;
  If Length(Bytes)>0 then
    Stream.WriteBuffer(Bytes[0],Length(Bytes));
  Stream.Position:=0;
  Reader:=TStreamReader.Create(Stream,Encoding,False,BufferSize);
  try
    For Pass:=0 to 1 do begin
      I:=1;
      While I<=Length(Text) do begin
        Start:=I;
        While (I<=Length(Text)) and (Text[I]<>#13) and (Text[I]<>#10) do
          Inc(I);
        Expected:=Copy(Text,Start,I-Start);
        If I<=Length(Text) then begin
          If (Text[I]=#13) and (I<Length(Text)) and (Text[I+1]=#10) then
            Inc(I);
          Inc(I);
        end;
        Reader.ReadLine(Actual);
        If Actual<>Expected then
          Writeln('CASE cp=',Encoding.CodePage,' fragment=',Fragment,' start=',Start,' pass=',Pass);
        Check(Actual=Expected,'line contents and boundaries');
      end;
      Check(Reader.EndOfStream,'no phantom trailing line');
      Reader.ReadLine(Actual);
      Check(Actual='','read after EOF');
      Reader.Reset;
    end;
  finally
    Reader.Free;
    Stream.Free;
  end;
end;

procedure CheckReadBoundary(const Text, Expected: UnicodeString; Encoding: TEncoding;
  Fragment, AllowedReads: Integer; ExpectFailure: Boolean);
var
  Bytes: TBytes;
  Stream: TFragmentStream;
  Reader: TStreamReader;
  Actual: UnicodeString;
  Raised: Boolean;
begin
  Bytes:=Encoding.GetBytes(Text);
  Stream:=TFragmentStream.Create;
  Stream.Limit:=Fragment;
  Stream.FailAfter:=AllowedReads;
  Stream.WriteBuffer(Bytes[0],Length(Bytes));
  Stream.Position:=0;
  Reader:=TStreamReader.Create(Stream,Encoding,False,128);
  try
    Raised:=False;
    try
      Reader.ReadLine(Actual);
    except
      on EReadError do
        Raised:=True;
    end;
    Check(Raised=ExpectFailure,'stream error propagation / no unnecessary read');
    Check(Actual=Expected,'completed prefix preserved');
  finally
    Reader.Free;
    Stream.Free;
  end;
end;

procedure CheckCloseDuringRead(const Text, Expected: UnicodeString; Encoding: TEncoding;
  Fragment, CloseAfter: Integer);
var
  Bytes: TBytes;
  Stream: TFragmentStream;
  Reader: TStreamReader;
  Actual: UnicodeString;
begin
  Bytes:=Encoding.GetBytes(Text);
  Stream:=TFragmentStream.Create;
  Stream.Limit:=Fragment;
  Stream.CloseAfter:=CloseAfter;
  Stream.WriteBuffer(Bytes[0],Length(Bytes));
  Stream.Position:=0;
  Reader:=TStreamReader.Create(Stream,Encoding,False,128);
  Stream.Reader:=Reader;
  try
    Reader.ReadLine(Actual);
    Check(Actual=Expected,'close preserves decoded prefix');
    Check(Reader.EndOfStream,'closed reader is at EOF');
    Reader.ReadLine(Actual);
    Check(Actual='','closed reader cannot read again');
    Check(Stream.Calls=CloseAfter,'no read after close');
  finally
    Reader.Free;
    Stream.Free;
  end;
end;

const
  Sizes: array[0..9] of Integer = (0,1,126,127,128,129,255,256,4095,4096);
var
  I, Fragment, Size: Integer;
  Encoding: TEncoding;
begin
  For I:=0 to 2 do begin
    case I of
      0: Encoding:=TEncoding.UTF8;
      1: Encoding:=TEncoding.Unicode;
      else Encoding:=TEncoding.BigEndianUnicode;
    end;
    For Fragment in [0,1,7,127,128,129,255] do begin
      CheckLines('',Encoding,Fragment,128);
      CheckLines(#13#10#10#13'a'#0'b'#13'абв😀'#10'z',Encoding,Fragment,128);
      CheckLines('end'#13,Encoding,Fragment,128);
      CheckLines('end'#10,Encoding,Fragment,128);
      CheckLines('end'#13#10,Encoding,Fragment,128);
      For Size in Sizes do
        CheckLines(StringOfChar('x',Size)+#13#10+'é😀'+#13+'last',Encoding,Fragment,128);
    end;
    CheckLines(StringOfChar('x',65536)+#10+'tail',Encoding,0,4096);
  end;
  CheckReadBoundary('x'#10+'unread','x',TEncoding.UTF8,2,1,False);
  CheckReadBoundary('x'#13#10+'unread','x',TEncoding.Unicode,2,3,False);
  CheckReadBoundary('x'#13#10+'unread','x',TEncoding.Unicode,1,5,True);
  CheckReadBoundary(StringOfChar('q',1024),StringOfChar('q',256),TEncoding.UTF8,128,2,True);
  CheckCloseDuringRead('x'#13#10,'',TEncoding.Unicode,1,1);
  CheckCloseDuringRead('x'#13#10,'x',TEncoding.Unicode,1,5);
  CheckCloseDuringRead(StringOfChar('q',256),StringOfChar('q',128),TEncoding.UTF8,128,1);
  Writeln('TEXT_STREAM_FRAGMENTED_LINES_PASS');
end.
