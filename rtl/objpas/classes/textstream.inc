{ Text streams moved from FCL StreamEx; original implementation copyright
  2015 Michael Van Canneyt and Silvio Clecio. See COPYING.FPC.
  Character-reader extensions and Classes integration are MoonCompiler code. }
type
  TEncodingSinkAccess = class(TEncoding)
  public
    function SpanByteCount(Chars: PUnicodeChar; CharCount: Integer): Integer;
    function SpanGetBytes(Chars: PUnicodeChar; CharCount: Integer;
      Bytes: PByte; ByteCount: Integer): Integer;
  end;

function TEncodingSinkAccess.SpanByteCount(Chars: PUnicodeChar;
  CharCount: Integer): Integer;
begin
  Result:=GetByteCount(Chars,CharCount);
end;

function TEncodingSinkAccess.SpanGetBytes(Chars: PUnicodeChar;
  CharCount: Integer; Bytes: PByte; ByteCount: Integer): Integer;
begin
  Result:=GetBytes(Chars,CharCount,Bytes,ByteCount);
end;

{ TTextWriter }

procedure TTextWriter.Write(aValue: Char; aCount: Integer);
begin
  Write(StringOfChar(aValue,aCount));
end;

{ TStreamWriter }

procedure TStreamWriter.WriteBytes(const Bytes: TBytes);
var
  BufLen,Count,ToWrite: Integer;
  P : PByte;
begin
  BufLen:=Length(FBuffer);
  ToWrite:=Length(Bytes);
  P:=PByte(Bytes);
  while ToWrite>0 do
    begin
    Count:=ToWrite;
    if Count>BufLen-FBufferIndex then
      Count:=BufLen-FBufferIndex;
    Move(P^,FBuffer[FBufferIndex],Count);
    Inc(P,Count);
    Dec(ToWrite,Count);
    Inc(FBufferIndex,Count);
    if FBufferIndex>=BufLen  then
      Flush;
    end;
  if FAutoFlush then
    Flush;
end;

constructor TStreamWriter.Create(aStream: TStream);
begin
  If not Assigned(aStream) then
    raise EArgumentException.CreateFmt(SParamIsNil, ['aStream']);
  FStream:=aStream;
  FFreeStream:=False;
  FEncoding:=TEncoding.UTF8;
  SetLength(FBuffer,1024);
  FNewLine:=sLineBreak;
  FAutoFlush:=True;
end;

procedure TStreamWriter.WriteUnicodeSpan(Chars: PUnicodeChar;
  CharCount: Integer);
var
  Best,BestByteCount,BufferSpace,ByteCount,Candidate,High,Low,Probe,
    Written: Integer;
  Oversized: TBytes;

  function WholeScalarPrefix(Count: Integer): Integer;
  begin
    Result:=Count;
    if (Result<CharCount) and (Result>0) and
       (Ord(Chars[Result-1])>=$d800) and
       (Ord(Chars[Result-1])<=$dbff) and
       (Ord(Chars[Result])>=$dc00) and
       (Ord(Chars[Result])<=$dfff) then
      Dec(Result);
  end;

  procedure WriteOversizedScalar;
  begin
    Candidate:=1;
    if (CharCount>1) and (Ord(Chars[0])>=$d800) and
       (Ord(Chars[0])<=$dbff) and (Ord(Chars[1])>=$dc00) and
       (Ord(Chars[1])<=$dfff) then
      Candidate:=2;
    ByteCount:=TEncodingSinkAccess(FEncoding).SpanByteCount(Chars,Candidate);
    SetLength(Oversized,ByteCount);
    Written:=TEncodingSinkAccess(FEncoding).SpanGetBytes(Chars,Candidate,
      PByte(Oversized),ByteCount);
    if Written<>ByteCount then
      raise EEncodingError.CreateFmt(
        'Encoding wrote %d bytes instead of %d',[Written,ByteCount]);
    WriteBytes(Oversized);
    Inc(Chars,Candidate);
    Dec(CharCount,Candidate);
  end;
begin
  if CharCount=0 then
    begin
    if FAutoFlush then
      Flush;
    Exit;
    end;
  while CharCount>0 do
    begin
    BufferSpace:=Length(FBuffer)-FBufferIndex;
    if BufferSpace=0 then
      begin
      Flush;
      BufferSpace:=Length(FBuffer);
      end;
    Candidate:=WholeScalarPrefix(CharCount);
    if Candidate>BufferSpace then
      Candidate:=WholeScalarPrefix(BufferSpace);
    if Candidate=0 then
      begin
      if FBufferIndex>0 then
        Flush
      else
        WriteOversizedScalar;
      Continue;
      end;
    ByteCount:=TEncodingSinkAccess(FEncoding).SpanByteCount(Chars,Candidate);
    if ByteCount>BufferSpace then
      begin
      if FBufferIndex>0 then
        begin
        Flush;
        Continue;
        end;
      Best:=0;
      BestByteCount:=0;
      Low:=1;
      High:=Candidate;
      while Low<=High do
        begin
        Probe:=Low+(High-Low) div 2;
        Candidate:=WholeScalarPrefix(Probe);
        if Candidate=0 then
          Low:=Probe+1
        else
          begin
          ByteCount:=TEncodingSinkAccess(FEncoding).SpanByteCount(
            Chars,Candidate);
          if ByteCount<=BufferSpace then
            begin
            Best:=Candidate;
            BestByteCount:=ByteCount;
            Low:=Probe+1;
            end
          else
            High:=Probe-1;
          end;
        end;
      if Best=0 then
        begin
        WriteOversizedScalar;
        Continue;
        end;
      Candidate:=Best;
      ByteCount:=BestByteCount;
      end;
    Written:=TEncodingSinkAccess(FEncoding).SpanGetBytes(Chars,Candidate,
      @FBuffer[FBufferIndex],BufferSpace);
    if Written<>ByteCount then
      raise EEncodingError.CreateFmt('Encoding wrote %d bytes instead of %d',
        [Written,ByteCount]);
    Inc(FBufferIndex,Written);
    Inc(Chars,Candidate);
    Dec(CharCount,Candidate);
    end;
  if FAutoFlush then
    Flush;
end;

constructor TStreamWriter.Create(aStream: TStream; aEncoding: TEncoding;
  aBufferSize: Integer);
begin
  If not Assigned(aStream) then
    raise EArgumentException.CreateFmt(SParamIsNil, ['aStream']);
  If not Assigned(aEncoding) then
    raise EArgumentException.CreateFmt(SParamIsNil, ['aEncoding']);
  FStream:=aStream;
  FFreeStream:=False;
  FEncoding:=aEncoding;
  If aBufferSize<128 then
    aBufferSize:=128;
  SetLength(FBuffer,aBufferSize);
  FNewLine:=sLineBreak;
  FAutoFlush:=True;
  If FStream.Position=0 then
    WriteBytes(FEncoding.GetPreamble);
end;

constructor TStreamWriter.Create(const aFilename: string; aAppend: Boolean);
var
  F: TStream;
begin
  If aAppend and FileExists(aFilename) then
    begin
    F:=TFileStream.Create(aFilename,fmOpenWrite);
    F.Seek(0,soEnd);
    end
  else
    F:=TFileStream.Create(aFilename,fmCreate);
  try
    Create(F);
    OwnStream;
  except
    F.Free;
    raise;
  end;
end;

constructor TStreamWriter.Create(const aFilename: string; aAppend: Boolean;
  aEncoding: TEncoding; aBufferSize: Integer);

var
  F : TStream;
begin
  if (aAppend and FileExists(aFilename)) then
    begin
    F := TFileStream.Create(aFilename, fmOpenWrite);
    F.Seek(0, soEnd);
    end
  else
    F := TFileStream.Create(aFilename, fmCreate);
  try
    Create(F,aEncoding,aBufferSize);
    OwnStream;
  except
    F.Free;
    raise;
  end;
end;

destructor TStreamWriter.Destroy;
begin
  Close;
  inherited Destroy;
end;

procedure TStreamWriter.Close;
begin
  Flush;
  if FFreeStream then
    FreeAndNil(FStream);
end;

procedure TStreamWriter.Flush;

var
  aCount: Integer;
begin
  if (FStream=Nil) or (FBufferIndex=0) then
    exit;
  aCount:=FBufferIndex;
  FBufferIndex:=0;
  FStream.WriteBuffer(FBuffer,aCount);
end;

procedure TStreamWriter.OwnStream;
begin
  FFreeStream:=True;
end;

procedure TStreamWriter.Write(aValue: Boolean);
begin
  Write(BoolToStr(aValue,True));
end;

procedure TStreamWriter.Write(aValue: Char);
begin
{$if sizeof(char)=1}
  Write(String(aValue));
{$else}
  WriteUnicodeSpan(@aValue,1);
{$endif}
end;

procedure TStreamWriter.Write(const aValue: TCharArray);
begin
  Write(aValue,0,Length(aValue));
end;

procedure TStreamWriter.Write(aValue: Double);
begin
  Write(FloatToStr(aValue));
end;

procedure TStreamWriter.Write(aValue: Integer);
begin
  Write(IntToStr(aValue));
end;

procedure TStreamWriter.Write(aValue: Int64);
begin
  Write(IntToStr(aValue));
end;

procedure TStreamWriter.Write(aValue: TObject);
begin
  Write(aValue.ToString);
end;

procedure TStreamWriter.Write(aValue: Single);
begin
  Write(FloatToStr(aValue));
end;

procedure TStreamWriter.Write(const aValue: string);
begin
{$if sizeof(char)=1}
  WriteBytes(FEncoding.GetAnsiBytes(aValue));
{$else}
  WriteUnicodeSpan(PUnicodeChar(aValue),Length(aValue));
{$endif}
end;

procedure TStreamWriter.Write(aValue: Cardinal);
begin
  Write(IntToStr(aValue));
end;

procedure TStreamWriter.Write(aValue: UInt64);
begin
  Write(IntToStr(aValue));
end;

procedure TStreamWriter.Write(const Fmt: string; aArgs: array of const);
begin
  Write(Format(Fmt,aArgs));
end;

procedure TStreamWriter.Write(const aValue: TCharArray; aIndex, aCount: Integer);
{$if sizeof(char)=1}
var
  S: String;
{$endif}
begin
  if aCount=0 then exit;
  if (aIndex<0) or (aCount<0) or (aIndex>Length(aValue)) or
     (aCount>Length(aValue)-aIndex) then
    raise ERangeError.CreateFmt(SListIndexError,[aIndex]);
{$if sizeof(char)=1}
  SetLength(S,aCount);
  Move(aValue[aIndex],S[1],aCount);
  Write(S);
{$else}
  WriteUnicodeSpan(@aValue[aIndex],aCount);
{$endif}
end;

procedure TStreamWriter.WriteLine;
begin
  Write(NewLine);
end;

procedure TStreamWriter.WriteLine(aValue: Boolean);
begin
  Write(aValue);
  WriteLine;
end;

procedure TStreamWriter.WriteLine(aValue: Char);
begin
  Write(aValue);
  WriteLine;
end;

procedure TStreamWriter.WriteLine(const aValue: TCharArray);
begin
  Write(aValue);
  WriteLine;
end;

procedure TStreamWriter.WriteLine(aValue: Double);
begin
  Write(aValue);
  WriteLine;
end;

procedure TStreamWriter.WriteLine(aValue: Integer);
begin
  Write(aValue);
  WriteLine;
end;

procedure TStreamWriter.WriteLine(aValue: Int64);
begin
  Write(aValue);
  WriteLine;
end;

procedure TStreamWriter.WriteLine(aValue: TObject);
begin
  Write(aValue);
  WriteLine;
end;

procedure TStreamWriter.WriteLine(aValue: Single);
begin
  Write(aValue);
  WriteLine;
end;

procedure TStreamWriter.WriteLine(const aValue: string);
begin
  Write(aValue);
  WriteLine;
end;

procedure TStreamWriter.WriteLine(aValue: Cardinal);
begin
  Write(aValue);
  WriteLine;
end;

procedure TStreamWriter.WriteLine(aValue: UInt64);
begin
  Write(aValue);
  WriteLine;
end;

procedure TStreamWriter.WriteLine(const Fmt: string; Args: array of const);
begin
  Write(Fmt,Args);
  WriteLine;
end;

procedure TStreamWriter.WriteLine(const aValue: TCharArray; aIndex, aCount: Integer
  );
begin
  Write(aValue,aIndex,aCount);
  WriteLine;
end;

{ TStringWriter }

function TStringWriter.GetStringBuilder: TStringBuilder;
begin
  Result:=FBuilder;
end;

constructor TStringWriter.Create;
begin
  FBuilder := TStringBuilder.Create;
  FFreeBuilder := True;
end;

constructor TStringWriter.Create(aBuilder: TStringBuilder);
begin
  FBuilder := aBuilder;
  FFreeBuilder := False;
end;

destructor TStringWriter.Destroy;
begin
  if FFreeBuilder then
    FreeAndNil(FBuilder);
  inherited Destroy;
end;

procedure TStringWriter.Close;
begin
  // nothing to do
end;

procedure TStringWriter.Flush;
begin
  // Nothing to do
end;

procedure TStringWriter.Write(aValue: Boolean);
begin
  FBuilder.Append(aValue);
end;

procedure TStringWriter.Write(aValue: Char);
begin
  FBuilder.Append(aValue);
end;

procedure TStringWriter.Write(aValue: Char; aCount: Integer);
begin
  FBuilder.Append(aValue);
end;

procedure TStringWriter.Write(const aValue: TCharArray);
begin
  FBuilder.Append(aValue);
end;

procedure TStringWriter.Write(aValue: Double);
begin
  FBuilder.Append(aValue);
end;

procedure TStringWriter.Write(aValue: Integer);
begin
  FBuilder.Append(aValue);
end;

procedure TStringWriter.Write(aValue: Int64);
begin
  FBuilder.Append(aValue);
end;

procedure TStringWriter.Write(aValue: TObject);
begin
  FBuilder.Append(aValue.ToString);
end;

procedure TStringWriter.Write(aValue: Single);
begin
  FBuilder.Append(aValue);
end;

procedure TStringWriter.Write(const aValue: string);
begin
  FBuilder.Append(aValue);
end;

procedure TStringWriter.Write(aValue: Cardinal);
begin
  FBuilder.Append(aValue);
end;

procedure TStringWriter.Write(aValue: QWord);
begin
  FBuilder.Append(aValue);
end;

procedure TStringWriter.Write(const aFmt: string; aArgs: array of const);
begin
  FBuilder.Append(aFmt,aArgs);
end;

procedure TStringWriter.Write(const aValue: TCharArray; aIndex, aCount: Integer
  );
begin
  FBuilder.Append(aValue,aIndex,aCount);
end;

procedure TStringWriter.WriteLine;
begin
   FBuilder.AppendLine;
end;

procedure TStringWriter.WriteLine(aValue: Boolean);
begin
  Write(aValue);
  WriteLine;
end;

procedure TStringWriter.WriteLine(aValue: Char);
begin
  Write(aValue);
  WriteLine;
end;

procedure TStringWriter.WriteLine(const aValue: TCharArray);
begin
  Write(aValue);
  WriteLine;
end;

procedure TStringWriter.WriteLine(aValue: Double);
begin
  Write(aValue);
  WriteLine;
end;

procedure TStringWriter.WriteLine(aValue: Integer);
begin
  Write(aValue);
  WriteLine;
end;

procedure TStringWriter.WriteLine(aValue: Int64);
begin
  Write(aValue);
  WriteLine;
end;

procedure TStringWriter.WriteLine(aValue: TObject);
begin
  Write(aValue);
  WriteLine;
end;

procedure TStringWriter.WriteLine(aValue: Single);
begin
  Write(aValue);
  WriteLine;
end;

procedure TStringWriter.WriteLine(const aValue: string);
begin
  Write(aValue);
  WriteLine;
end;

procedure TStringWriter.WriteLine(aValue: Cardinal);
begin
  Write(aValue);
  WriteLine;
end;

procedure TStringWriter.WriteLine(aValue: UInt64);
begin
  Write(aValue);
  WriteLine;
end;

procedure TStringWriter.WriteLine(const aFmt: string; aArgs: array of const);
begin
  Write(aFmt,aArgs);
  WriteLine;
end;

procedure TStringWriter.WriteLine(const aValue: TCharArray; aIndex,
  aCount: Integer);
begin
  Write(aValue,aIndex,aCount);
  WriteLine;
end;

function TStringWriter.ToString: string;
begin
  Result:=FBuilder.ToString;
end;


{ TTextReader }

constructor TTextReader.Create;
begin
  inherited Create;
end;

function TTextReader.IsEof: Boolean;
begin
  Result:=GetEndOfStream;
end;

function TTextReader.GetEndOfStream: Boolean;
begin
  Result:=Peek<0;
end;

procedure TTextReader.Reset;
begin
  Rewind;
end;

procedure TTextReader.Rewind;
begin
  raise ENotSupportedException.Create('This reader cannot rewind');
end;

function TTextReader.Peek: Integer;
begin
  raise ENotSupportedException.Create('This reader cannot peek');
end;

function TTextReader.Read: Integer;
begin
  raise ENotSupportedException.Create('This reader cannot read characters');
end;

procedure CheckTextReadRange(const Buffer: TCharArray; Index, Count: Integer);
begin
  if (Index<0) or (Count<0) or (Index>Length(Buffer)) or (Count>Length(Buffer)-Index) then
    raise EArgumentOutOfRangeException.Create('Invalid character buffer range');
end;

function TTextReader.Read(var Buffer: TCharArray; Index, Count: Integer): Integer;
var
  C: Integer;
begin
  CheckTextReadRange(Buffer,Index,Count);
  Result:=0;
  while Result<Count do
    begin
    C:=Read;
    if C<0 then
      Break;
    Buffer[Index+Result]:=Char(C);
    Inc(Result);
    end;
end;

function TTextReader.ReadBlock(var Buffer: TCharArray; Index, Count: Integer): Integer;
var
  N: Integer;
begin
  CheckTextReadRange(Buffer,Index,Count);
  Result:=0;
  while Result<Count do
    begin
    N:=Read(Buffer,Index+Result,Count-Result);
    if N=0 then
      Break;
    Inc(Result,N);
    end;
end;

function TTextReader.ReadToEnd: RTLString;
var
  Buffer: TCharArray;
  Builder: TStringBuilder;
  N: Integer;
begin
  Builder:=TStringBuilder.Create;
  try
    SetLength(Buffer,4096);
    repeat
      N:=Read(Buffer,0,Length(Buffer));
      if N>0 then
        Builder.Append(Buffer,0,N);
    until N=0;
    Result:=RTLString(Builder.ToString);
  finally
    Builder.Free;
  end;
end;

function TTextReader.ReadLine: RTLString;
begin
  ReadLine(Result);
end;

procedure TTextReader.ReadLine(out AString: RTLString);
var
  Builder: TStringBuilder;
  C: Integer;
begin
  Builder:=TStringBuilder.Create;
  try
    while True do
      begin
      C:=Read;
      if (C<0) or (C=10) then
        Break;
      if C=13 then
        begin
        if Peek=10 then
          Read;
        Break;
        end;
      Builder.Append(Char(C));
      end;
    AString:=RTLString(Builder.ToString);
  finally
    Builder.Free;
  end;
end;

function TTextReader.GetEnumerator: TTextReaderEnumerator;
begin
  Result:=TTextReaderEnumerator.Create(Self);
end;

constructor TTextReaderEnumerator.Create(AReader: TTextReader);
begin
  inherited Create;
  FReader:=AReader;
end;

function TTextReaderEnumerator.MoveNext: Boolean;
begin
  Result:=not FReader.EndOfStream;
  if Result then
    FLine:=FReader.ReadLine;
end;

{ TStreamReader }

constructor TStreamReader.Create(AStream: TStream; ABufferSize: Integer;
  AOwnsStream: Boolean);
begin
  Create(AStream,TEncoding.UTF8,True,ABufferSize);
  FOwnsStream:=AOwnsStream;
end;

constructor TStreamReader.Create(AStream: TStream);
begin
  Create(AStream, 4096, False);
end;

constructor TStreamReader.Create(AStream: TStream; ADetectBOM: Boolean);
begin
  Create(AStream,TEncoding.UTF8,ADetectBOM,4096);
end;

constructor TStreamReader.Create(AStream: TStream; AEncoding: TEncoding;
  ADetectBOM: Boolean; ABufferSize: Integer);
begin
  inherited Create;
  If not Assigned(AStream) then
    raise EArgumentException.CreateFmt(SParamIsNil, ['AStream']);
  If not Assigned(AEncoding) then
    raise EArgumentException.CreateFmt(SParamIsNil, ['AEncoding']);
  FStream:=AStream;
  FEncoding:=AEncoding;
  FInitialEncoding:=AEncoding;
  FDetectBOM:=ADetectBOM;
  FOwnsStream:=False;
  FClosed:=False;
  FStarted:=False;
  FNoDataInStream:=False;
  If ABufferSize<128 then
    ABufferSize:=128;
  FBufferSize:=ABufferSize;
end;

constructor TStreamReader.Create(const aFilename: string);
begin
  Create(aFileName,TEncoding.UTF8,True,4096);
end;

constructor TStreamReader.Create(const aFilename: string; aDetectBOM: Boolean);
begin
  Create(aFileName,TEncoding.UTF8,aDetectBOM,4096);
end;

constructor TStreamReader.Create(const aFilename: string; aEncoding: TEncoding; aDetectBOM: Boolean; aBufferSize: Integer);
var
  F : TFileStream;

begin
  F:=TFileStream.Create(aFileName,fmOpenRead or fmShareDenyWrite);
  try
    Create(F,aEncoding,aDetectBOM,aBufferSize);
    FOwnsStream:=True;
  except
    F.Free;
    raise;
  end;
end;

destructor TStreamReader.Destroy;
begin
  Close;
  inherited Destroy;
end;

procedure TStreamReader.CompactBufferedText;
begin
  If FBufferedTextPosition=0 then
    Exit;
  If FBufferedTextPosition>=Length(FBufferedText) then
    FBufferedText:=''
  else
    Delete(FBufferedText,1,FBufferedTextPosition);
  FBufferedTextPosition:=0;
end;

function TStreamReader.CompleteByteCount(const Bytes: TBytes;
  Count: Integer): Integer;
var
  ContinuationCount, ExpectedCount, I: Integer;
  Lead: Byte;
begin
  Result:=Count;
  If FNoDataInStream or (Count=0) then
    Exit;
  case FEncoding.CodePage of
    CP_UTF16,
    CP_UTF16BE:
      Result:=Count and not 1;
    CP_UTF8:
      begin
        I:=Count-1;
        ContinuationCount:=0;
        While (I>=0) and ((Bytes[I] and $c0)=$80) do
          begin
          Inc(ContinuationCount);
          Dec(I);
          end;
        If I<0 then
          Exit;
        Lead:=Bytes[I];
        If Lead<$80 then
          ExpectedCount:=1
        else If (Lead and $e0)=$c0 then
          ExpectedCount:=2
        else If (Lead and $f0)=$e0 then
          ExpectedCount:=3
        else If (Lead and $f8)=$f0 then
          ExpectedCount:=4
        else
          ExpectedCount:=0;
        If (ExpectedCount>0) and (ExpectedCount>ContinuationCount+1) then
          Result:=I;
      end;
    932, 936, 949, 950, 1361, 54936:
      begin
        I:=0;
        while I<Count do
          begin
          Lead:=Bytes[I];
          case FEncoding.CodePage of
            932: ExpectedCount:=1+Ord((Lead in [$81..$9F,$E0..$FC]));
            1361: ExpectedCount:=1+Ord((Lead in [$84..$D3,$D8..$DE,$E0..$F9]));
            else ExpectedCount:=1+Ord(Lead in [$81..$FE]);
          end;
          if (FEncoding.CodePage=54936) and (ExpectedCount=2) and (I+1<Count) and
             (Bytes[I+1] in [$30..$39]) then
            ExpectedCount:=4;
          if ExpectedCount>Count-I then
            Exit(I);
          Inc(I,ExpectedCount);
          end;
      end;
  end;
end;

procedure TStreamReader.FillBuffer;
var
  Bytes, DetectedPreamble: TBytes;
  CompleteCount, ReadCount, ReadTotal, StartIndex, TailCount: Integer;
  Decoded: UnicodeString;
  DetectedEncoding: TEncoding;

  function PartialPreamble(Encoding: TEncoding): Boolean;
  var
    Preamble: TBytes;
  begin
    Preamble:=Encoding.GetPreamble;
    Result:=(ReadTotal>0) and (ReadTotal<Length(Preamble)) and
      CompareMem(@Bytes[0],@Preamble[0],ReadTotal);
  end;
begin
  If FClosed or FNoDataInStream then
    Exit;
  CompactBufferedText;
  SetLength(Bytes,Length(FByteTail)+FBufferSize);
  ReadTotal:=Length(FByteTail);
  If ReadTotal>0 then
    Move(FByteTail[0],Bytes[0],ReadTotal);
  SetLength(FByteTail,0);
  ReadCount:=FStream.Read(Bytes[ReadTotal],Length(Bytes)-ReadTotal);
  If ReadCount<=0 then
    FNoDataInStream:=True
  else
    Inc(ReadTotal,ReadCount);
  SetLength(Bytes,ReadTotal);
  { A short read can already contain a complete line from a live stream.
    Only an undecidable BOM prefix or incomplete character needs more input. }
  If not FStarted and not FNoDataInStream then
    begin
    If (FDetectBOM and (PartialPreamble(TEncoding.UTF8) or
        PartialPreamble(TEncoding.Unicode) or PartialPreamble(TEncoding.BigEndianUnicode))) or
       (not FDetectBOM and PartialPreamble(FEncoding)) then
      begin
      FByteTail:=Bytes;
      Exit;
      end;
    end;

  StartIndex:=0;
  If not FStarted then
    begin
    If FDetectBOM then
      begin
      DetectedEncoding:=nil;
      StartIndex:=TEncoding.GetBufferEncoding(Bytes,DetectedEncoding,nil);
      If Assigned(DetectedEncoding) then
        FEncoding:=DetectedEncoding;
      end
    else
      begin
      DetectedPreamble:=FEncoding.GetPreamble;
      If (Length(DetectedPreamble)>0) and
         (ReadTotal>=Length(DetectedPreamble)) and
         CompareMem(@Bytes[0],@DetectedPreamble[0],Length(DetectedPreamble)) then
        StartIndex:=Length(DetectedPreamble);
      end;
    FStarted:=True;
    end;

  CompleteCount:=CompleteByteCount(Bytes,ReadTotal);
  If CompleteCount<StartIndex then
    CompleteCount:=StartIndex;
  TailCount:=ReadTotal-CompleteCount;
  If TailCount>0 then
    begin
    SetLength(FByteTail,TailCount);
    Move(Bytes[CompleteCount],FByteTail[0],TailCount);
    end;
  If CompleteCount>StartIndex then
    begin
    Decoded:=FEncoding.GetString(Bytes,StartIndex,CompleteCount-StartIndex);
    FBufferedText:=FBufferedText+RTLString(Decoded);
    end;
end;

procedure TStreamReader.Reset;
begin
  FBufferedText:='';
  FBufferedTextPosition:=0;
  SetLength(FByteTail,0);
  FStarted:=False;
  FNoDataInStream:=False;
  FEncoding:=FInitialEncoding;
  if Assigned(FStream) then
    FStream.Seek(0, 0);
end;

procedure TStreamReader.Close;
begin
  if FOwnsStream then
    FreeAndNil(FStream);
  FClosed:=True;
end;

function TStreamReader.IsEof: Boolean;
begin
  if FClosed or not Assigned(FStream) then
    Exit(True);
  While (FBufferedTextPosition>=Length(FBufferedText)) and not FNoDataInStream do
    FillBuffer;
  Result:=(FBufferedTextPosition>=Length(FBufferedText)) and FNoDataInStream;
end;

procedure TStreamReader.ReadLine(out AString: RTLString);
var
  C: Char;
  SegmentEnd, SegmentStart: Integer;
begin
  AString:='';
  If IsEof then
    Exit;
  While True do
    begin
    SegmentStart:=FBufferedTextPosition+1;
    SegmentEnd:=SegmentStart;
    While SegmentEnd<=Length(FBufferedText) do
      begin
      C:=FBufferedText[SegmentEnd];
      If (C=#10) or (C=#13) then
        begin
        AString:=AString+Copy(FBufferedText,SegmentStart,
          SegmentEnd-SegmentStart);
        FBufferedTextPosition:=SegmentEnd;
        If C=#13 then
          begin
          If (FBufferedTextPosition>=Length(FBufferedText)) and
             not FNoDataInStream then
            FillBuffer;
          If (FBufferedTextPosition<Length(FBufferedText)) and
             (FBufferedText[FBufferedTextPosition+1]=#10) then
            Inc(FBufferedTextPosition);
          end;
        Exit;
        end;
      Inc(SegmentEnd);
      end;
    AString:=AString+Copy(FBufferedText,SegmentStart,
      Length(FBufferedText)-SegmentStart+1);
    FBufferedTextPosition:=Length(FBufferedText);
    If FNoDataInStream then
      Exit;
    FillBuffer;
    end;
end;


{ TStringReader }

constructor TStringReader.Create(const AString: RTLString; ABufferSize: Integer);
begin
  inherited Create;
  FData:=AString;
  If FData='' then
    FPosition:=0
  else
    FPosition:=1;
end;

constructor TStringReader.Create(const AString: RTLString);
begin
  Create(AString, 4096);
end;

destructor TStringReader.Destroy;
begin
  inherited Destroy;
end;

procedure TStringReader.Reset;
begin
  If FData='' then
    FPosition:=0
  else
    FPosition:=1;
end;

procedure TStringReader.Close;
begin
  FData:='';
  FPosition:=0;
end;

function TStringReader.IsEof: Boolean;
begin
  Result:=FPosition=0;
end;

procedure TStringReader.ReadLine(out AString: RTLString);
var
  LineEnd, LineStart: Integer;
begin
  AString:='';
  If FPosition=0 then
    Exit;
  LineStart:=FPosition;
  LineEnd:=LineStart;
  While (LineEnd<=Length(FData)) and (FData[LineEnd]<>#10) and
        (FData[LineEnd]<>#13) do
    Inc(LineEnd);
  AString:=Copy(FData,LineStart,LineEnd-LineStart);
  If LineEnd>Length(FData) then
    FPosition:=0
  else
    begin
    FPosition:=LineEnd+1;
    If (FData[LineEnd]=#13) and (FPosition<=Length(FData)) and
       (FData[FPosition]=#10) then
      Inc(FPosition);
    If FPosition>Length(FData) then
      FPosition:=0;
    end;
end;


function TStreamReader.Peek: Integer;
begin
  if IsEof then
    Result:=-1
  else
    Result:=Ord(FBufferedText[FBufferedTextPosition+1]);
end;

function TStreamReader.Read: Integer;
begin
  Result:=Peek;
  if Result>=0 then
    Inc(FBufferedTextPosition);
end;

function TStreamReader.Read(var Buffer: TCharArray; Index, Count: Integer): Integer;
var
  N: Integer;
begin
  CheckTextReadRange(Buffer,Index,Count);
  Result:=0;
  while (Result<Count) and not IsEof do
    begin
    N:=Length(FBufferedText)-FBufferedTextPosition;
    if N>Count-Result then
      N:=Count-Result;
    Move(FBufferedText[FBufferedTextPosition+1],Buffer[Index+Result],N*SizeOf(Char));
    Inc(FBufferedTextPosition,N);
    Inc(Result,N);
    end;
end;

procedure TStreamReader.Rewind;
begin
  Reset;
end;

procedure TStreamReader.DiscardBufferedData;
begin
  FBufferedText:='';
  FBufferedTextPosition:=0;
  FByteTail:=nil;
  FNoDataInStream:=False;
end;

procedure TStreamReader.OwnStream;
begin
  FOwnsStream:=True;
end;

function TStringReader.Peek: Integer;
begin
  if FPosition=0 then
    Result:=-1
  else
    Result:=Ord(FData[FPosition]);
end;

function TStringReader.Read: Integer;
begin
  Result:=Peek;
  if Result>=0 then
    begin
    Inc(FPosition);
    if FPosition>Length(FData) then
      FPosition:=0;
    end;
end;

function TStringReader.Read(var Buffer: TCharArray; Index, Count: Integer): Integer;
begin
  CheckTextReadRange(Buffer,Index,Count);
  Result:=0;
  if (Count=0) or (FPosition=0) then
    Exit;
  Result:=Length(FData)-FPosition+1;
  if Result>Count then
    Result:=Count;
  Move(FData[FPosition],Buffer[Index],Result*SizeOf(Char));
  Inc(FPosition,Result);
  if FPosition>Length(FData) then
    FPosition:=0;
end;

procedure TStringReader.Rewind;
begin
  Reset;
end;
