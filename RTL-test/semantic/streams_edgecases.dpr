program streams_edgecases;

{$mode delphi}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  {$endif UNIX}
  SysUtils,
  Classes,
  BufStream;

type
  TShortReadStream = class(TStream)
  private
    FData: TBytes;
    FPosition: Int64;
    FChunk: Integer;
    FRaiseAfter: Integer;
  public
    constructor Create(const AData: TBytes; AChunk: Integer;
      ARaiseAfter: Integer=-1);
    function Read(var Buffer; Count: Longint): Longint; override;
    function Write(const Buffer; Count: Longint): Longint; override;
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; override;
  end;

  TRaisingUTF8Encoding = class(TUTF8Encoding)
  strict protected
    function GetChars(Bytes: PByte; ByteCount: Integer; Chars: PUnicodeChar;
      CharCount: Integer): Integer; override;
  end;

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create('STREAMS_EDGECASES_FAIL: '+AMessage);
end;

constructor TShortReadStream.Create(const AData: TBytes; AChunk: Integer;
  ARaiseAfter: Integer);
begin
  inherited Create;
  FData:=Copy(AData);
  FChunk:=AChunk;
  FRaiseAfter:=ARaiseAfter;
end;

function TShortReadStream.Read(var Buffer; Count: Longint): Longint;
begin
  if (FRaiseAfter>=0) and (FPosition>=FRaiseAfter) then
    raise EReadError.Create('injected read failure');
  Result:=Length(FData)-FPosition;
  if Result>Count then
    Result:=Count;
  if Result>FChunk then
    Result:=FChunk;
  if Result>0 then
    begin
    Move(FData[FPosition],Buffer,Result);
    Inc(FPosition,Result);
    end;
end;

function TShortReadStream.Write(const Buffer; Count: Longint): Longint;
begin
  Result:=0;
  raise EWriteError.Create('read-only source');
end;

function TShortReadStream.Seek(const Offset: Int64;
  Origin: TSeekOrigin): Int64;
begin
  case Origin of
    soBeginning: FPosition:=Offset;
    soCurrent: Inc(FPosition,Offset);
    soEnd: FPosition:=Length(FData)+Offset;
  end;
  if FPosition<0 then
    FPosition:=0;
  if FPosition>Length(FData) then
    FPosition:=Length(FData);
  Result:=FPosition;
end;

function TRaisingUTF8Encoding.GetChars(Bytes: PByte; ByteCount: Integer;
  Chars: PUnicodeChar; CharCount: Integer): Integer;
begin
  Result:=0;
  raise EEncodingError.Create('injected decode failure');
end;

procedure CheckCopyFrom;
var
  Data, Output: TBytes;
  Dest: TMemoryStream;
  I: Integer;
  Raised: Boolean;
  Source: TShortReadStream;
begin
  SetLength(Data,200003);
  for I:=0 to High(Data) do
    Data[I]:=Byte(I*37+11);
  Source:=TShortReadStream.Create(Data,7);
  Dest:=TMemoryStream.Create;
  try
    Source.Position:=123;
    Check(Dest.CopyFrom(Source,0)=Length(Data),'short-read copy count');
    Check(Dest.Size=Length(Data),'short-read destination size');
    SetLength(Output,Dest.Size);
    Dest.Position:=0;
    Dest.ReadBuffer(Output[0],Length(Output));
    Check(CompareMem(@Data[0],@Output[0],Length(Data)),'short-read bytes');
  finally
    Dest.Free;
    Source.Free;
  end;

  Source:=TShortReadStream.Create(nil,1);
  Dest:=TMemoryStream.Create;
  try
    Check(Dest.CopyFrom(Source,0)=0,'empty source');
  finally
    Dest.Free;
    Source.Free;
  end;

  Source:=TShortReadStream.Create(Data,3,10);
  Dest:=TMemoryStream.Create;
  try
    Raised:=False;
    try
      Dest.CopyFrom(Source,0);
    except
      on EReadError do
        Raised:=True;
    end;
    Check(Raised,'read exception propagation');
    Check(Dest.Size=12,'bytes before read exception preserved');
  finally
    Dest.Free;
    Source.Free;
  end;

  Source:=TShortReadStream.Create(Data,3);
  Dest:=TMemoryStream.Create;
  try
    Check(Dest.CopyFrom(Source,100)=100,'explicit count');
    Check((Dest.Size=100) and (Source.Position=100),'explicit positions');
  finally
    Dest.Free;
    Source.Free;
  end;
end;

procedure CheckStringStream;
var
  First, Rest, Whole: UnicodeString;
  Raised: Boolean;
  Stream: TStringStream;
begin
  Whole:='ASCII '+UnicodeString(#$041F#$0440#$0438#$0432#$0435#$0442)+
    UnicodeString(#$D83D#$DE80)+' tail';
  Stream:=TStringStream.Create(Whole,TEncoding.UTF8,False);
  try
    Check(Stream.Position=0,'initial string position');
    First:=Stream.ReadUnicodeString(6);
    Check((First='ASCII ') and (Stream.Position=6),'first byte span');
    Rest:=Stream.ReadUnicodeString(MaxInt);
    Check((First+Rest=Whole) and (Stream.Position=Stream.Size),
      'remaining byte span');
    Check(Stream.ReadUnicodeString(10)='','read at EOF');
    Check(Stream.Position=Stream.Size,'EOF position');
    Stream.Position:=0;
    Check(Stream.ReadUnicodeString(0)='','zero count');
    Check(Stream.Position=0,'zero count position');
  finally
    Stream.Free;
  end;

  Stream:=TStringStream.Create(UnicodeString('abc'),TRaisingUTF8Encoding.Create,
    True);
  try
    Raised:=False;
    try
      Stream.ReadUnicodeString(3);
    except
      on EEncodingError do
        Raised:=True;
    end;
    Check(Raised,'decode exception propagation');
    Check(Stream.Position=0,'decode exception preserves byte position');
  finally
    Stream.Free;
  end;
end;

procedure CheckBufferedSetSize;
var
  Buffer: array[0..31] of Byte;
  FileName: string;
  I: Integer;
  Stream: TBufferedFileStream;
begin
  FileName:=GetTempDir(False)+'mooncompiler-buffered-'+IntToStr(GetTickCount64)+'.tmp';
  for I:=0 to High(Buffer) do
    Buffer[I]:=Byte(I+1);
  Stream:=TBufferedFileStream.Create(FileName,fmCreate);
  try
    Stream.WriteBuffer(Buffer,SizeOf(Buffer));
    Stream.Size:=4097;
    Check(Stream.Size=4097,'grow cached size');
    Check(Stream.Position=4097,'grow physical seek position');
    Stream.Position:=4096;
    Buffer[0]:=99;
    Stream.WriteBuffer(Buffer[0],1);
    Stream.Size:=17;
    Check(Stream.Size=17,'shrink cached size');
    Check(Stream.Position=17,'shrink physical seek position');
    Stream.Size:=0;
    Check((Stream.Size=0) and (Stream.Position=0),'zero size');
  finally
    Stream.Free;
  end;
  Stream:=TBufferedFileStream.Create(FileName,fmOpenReadWrite);
  try
    Check(Stream.Size=0,'reopen physical zero size');
  finally
    Stream.Free;
  end;
  DeleteFile(FileName);
end;

begin
  try
    CheckCopyFrom;
    CheckStringStream;
    CheckBufferedSetSize;
    WriteLn('STREAMS_EDGECASES_PASS');
  except
    on E: Exception do
      begin
      WriteLn(ErrOutput,E.ClassName,': ',E.Message);
      Halt(1);
      end;
  end;
end.
