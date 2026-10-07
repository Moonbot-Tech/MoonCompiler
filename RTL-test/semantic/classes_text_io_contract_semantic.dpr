program classes_text_io_contract_semantic;
{$IFDEF FPC}{$mode delphiunicode}{$H+}{$ENDIF}
{$APPTYPE CONSOLE}
uses
  {$IFDEF FPC}mormot.core.fpcx64mm,{$IFDEF UNIX}cthreads,cwstring,{$ENDIF}{$ENDIF}
  System.SysUtils, System.Classes;

type
  TShortStream = class(TMemoryStream)
  public
    function Read(var Buffer; Count: LongInt): LongInt; override;
  end;
  TReadyLineStream = class(TMemoryStream)
  public
    Reads: Integer;
    function Read(var Buffer; Count: LongInt): LongInt; override;
  end;
  TOwnedStream = class(TMemoryStream)
  public
    destructor Destroy; override;
  end;
  TShortReader = class(TStringReader)
  public
    function Read(var Buffer: TCharArray; Index, Count: Integer): Integer; override;
  end;
var
  Destroyed: Integer;

procedure Check(OK: Boolean; const Name: string);
begin
  if not OK then raise Exception.Create('TEXT_IO: '+Name);
end;

function TShortStream.Read(var Buffer; Count: LongInt): LongInt;
begin
  if Count>1 then Count:=1;
  Result:=inherited Read(Buffer,Count);
end;

function TReadyLineStream.Read(var Buffer; Count: LongInt): LongInt;
begin
  Inc(Reads);
  if Reads>1 then raise EStreamError.Create('Read would wait for the next producer message');
  Result:=inherited Read(Buffer,Count);
end;

procedure ReadyLine;
var M:TReadyLineStream; R:TStreamReader; Bytes:TBytes;
begin
  M:=TReadyLineStream.Create;
  Bytes:=TEncoding.UTF8.GetBytes('ready'+#10);
  M.WriteBuffer(Bytes[0],Length(Bytes));
  M.Position:=0;
  R:=TStreamReader.Create(M,TEncoding.UTF8,True);
  try
    Check(R.ReadLine='ready','available line without another read');
    Check(M.Reads=1,'short read does not force buffer fill');
  finally R.Free; M.Free; end;
end;

destructor TOwnedStream.Destroy;
begin
  Inc(Destroyed);
  inherited;
end;

function TShortReader.Read(var Buffer: TCharArray; Index, Count: Integer): Integer;
begin
  if Count>1 then Count:=1;
  Result:=inherited Read(Buffer,Index,Count);
end;

procedure StringReader;
var
  R: TTextReader;
  Buffer: TCharArray;
  Line, Joined: string;
  Failed: Boolean;
begin
  R:=TStringReader.Create('ab'+#13#10+'cd'+#10+'e'+#0+'f');
  try
    Check(R.Peek=Ord('a'),'peek');
    Check(R.Peek=Ord('a'),'peek does not consume');
    Check(R.Read=Ord('a'),'read character');
    Check(R.ReadLine='b','mixed character and line');
    SetLength(Buffer,5);
    Buffer[0]:='!'; Buffer[4]:='!';
    Check(R.ReadBlock(Buffer,1,3)=3,'read block');
    Check((Buffer[0]='!') and (Buffer[1]='c') and (Buffer[2]='d') and
      (Buffer[3]=#10) and (Buffer[4]='!'),'slice boundaries');
    Check(R.ReadToEnd='e'+#0+'f','tail preserves NUL');
    Check(R.EndOfStream and (R.Peek=-1) and (R.Read=-1),'EOF');
    Check(R.Read(Buffer,Length(Buffer),0)=0,'zero read at end');
    Failed:=False;
    try R.Read(Buffer,High(Integer),1); except on E:EArgumentOutOfRangeException do Failed:=True; end;
    Check(Failed,'range validation');
    R.Rewind;
    Joined:='';
    for Line in R do Joined:=Joined+'['+Line+']';
    Check(Joined='[ab][cd][e'+#0+'f]','enumeration');
  finally R.Free; end;
  R:=TShortReader.Create('abcd');
  try
    SetLength(Buffer,6);
    Check(R.ReadBlock(Buffer,1,4)=4,'ReadBlock combines short reads');
    Check((Buffer[1]='a') and (Buffer[4]='d'),'short-read content');
  finally R.Free; end;
end;

procedure StreamReader;
var
  M: TShortStream;
  R: TStreamReader;
  Bytes: TBytes;
  Text: string;
  Buffer: TCharArray;
begin
  M:=TShortStream.Create;
  Text:=StringOfChar('a',127)+Char($20ac)+Char($d83d)+Char($de80)+#0+'z'+#13#10+'last';
  Bytes:=TEncoding.UTF8.GetPreamble+TEncoding.UTF8.GetBytes(Text);
  M.WriteBuffer(Bytes[0],Length(Bytes));
  M.Position:=0;
  R:=TStreamReader.Create(M,TEncoding.ASCII,True,128);
  try
    SetLength(Buffer,127);
    Check(R.ReadBlock(Buffer,0,127)=127,'read across byte boundary');
    Check(R.Peek=$20ac,'split UTF8 scalar');
    Check(R.Read=$20ac,'consume scalar');
    Check(R.Read=$d83d,'surrogate high');
    Check(R.Read=$de80,'surrogate low');
    Check(R.Read=0,'embedded NUL');
    Check(R.ReadLine='z','line after block');
    Check(R.ReadToEnd='last','end after CRLF');
    R.Rewind;
    Check(R.ReadToEnd=Text,'rewind re-detects BOM');
  finally R.Free; end;
  Check(M.Size=Length(Bytes),'borrowed stream survives');
  M.Free;
  M:=TShortStream.Create;
  Bytes:=TEncoding.UTF8.GetBytes('abcdef');
  M.WriteBuffer(Bytes[0],Length(Bytes)); M.Position:=0;
  R:=TStreamReader.Create(M,TEncoding.UTF8);
  try
    Check(R.Read=Ord('a'),'initial buffered read');
    M.Position:=2;
    R.DiscardBufferedData;
    Check(R.ReadToEnd='cdef','external seek and discard');
  finally R.Free; M.Free; end;
end;

procedure WritersAndOwnership;
var
  W: TStringWriter;
  S: TStreamWriter;
  R: TStreamReader;
  M: TOwnedStream;
  Bytes: TBytes;
begin
  W:=TStringWriter.Create;
  try
    W.Write('x'); W.Write(Char($20ac)); W.Write(42);
    Check(W.ToString='x'+Char($20ac)+'42','Classes string writer');
  finally W.Free; end;
  M:=TOwnedStream.Create;
  S:=TStreamWriter.Create(M,TEncoding.UTF8,128);
  S.OwnStream;
  S.Write('text'); S.Flush;
  SetLength(Bytes,M.Size);
  M.Position:=0; M.ReadBuffer(Bytes[0],Length(Bytes));
  Check((Length(Bytes)=7) and (Bytes[0]=$ef) and (Bytes[3]=Ord('t')),'encoded bytes');
  S.Free;
  Check(Destroyed=1,'writer owns exactly once');
  M:=TOwnedStream.Create;
  R:=TStreamReader.Create(M);
  R.OwnStream; R.Close; R.Free;
  Check(Destroyed=2,'reader Close and Destroy own exactly once');
end;
begin
  StringReader;
  StreamReader;
  ReadyLine;
  WritersAndOwnership;
  WriteLn('CLASSES_TEXT_IO_CONTRACT_PASS');
end.
