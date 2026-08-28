program encoding_span_ranges_semantic;

{ Public TEncoding span overloads validate forward ranges without ever
  computing Index+Count.  Zero-length spans at the exact end are legal and do
  not form a pointer; out-of-range and overflowing counts fail before the
  virtual pointer kernel can read or write outside an array. }

{$APPTYPE CONSOLE}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  {$endif UNIX}
  SysUtils;

type
  TAction = reference to procedure;

procedure ExpectEncodingError(const Name: string; const Action: TAction);
begin
  try
    Action();
  except
    on E: EEncodingError do
      exit;
  end;
  raise Exception.Create(Name+' did not raise EEncodingError');
end;

var
  Bytes,DestinationBytes: TBytes;
  Chars,DestinationChars: TUnicodeCharArray;
  Ansi: AnsiString;
begin
  try
    Bytes:=TBytes.Create(Ord('A'));
    SetLength(Chars,1);
    Chars[0]:='A';
    SetLength(DestinationBytes,1);
    SetLength(DestinationChars,1);

    If TEncoding.UTF8.GetCharCount(Bytes,0,1)<>1 then
      raise Exception.Create('normal byte span');
    If TEncoding.UTF8.GetByteCount(Chars,0,1)<>1 then
      raise Exception.Create('normal char span');
    If TEncoding.UTF8.GetCharCount(Bytes,1,0)<>0 then
      raise Exception.Create('byte zero at end');
    If TEncoding.UTF8.GetByteCount(Chars,1,0)<>0 then
      raise Exception.Create('char zero at end');
    If TEncoding.UTF8.GetByteCount('A',2,0)<>0 then
      raise Exception.Create('string zero at end');
    If TEncoding.UTF8.GetChars(Bytes,1,0,DestinationChars,1)<>0 then
      raise Exception.Create('GetChars destination zero at end');
    If TEncoding.UTF8.GetBytes(Chars,1,0,DestinationBytes,1)<>0 then
      raise Exception.Create('GetBytes destination zero at end');
    If Length(TEncoding.UTF8.GetBytes(Chars,0,1))<>1 then
      raise Exception.Create('GetBytes array slice');
    If Length(TEncoding.UTF8.GetChars(Bytes,0,1))<>1 then
      raise Exception.Create('GetChars array slice');
    If TEncoding.UTF8.GetBytes('A',2,0,DestinationBytes,1)<>0 then
      raise Exception.Create('GetBytes string destination zero at end');
    Ansi:='A';
    If Length(TEncoding.UTF8.GetAnsiBytes(Ansi,1,1))<>1 then
      raise Exception.Create('GetAnsiBytes normal span');
    If Length(TEncoding.UTF8.GetAnsiBytes(Ansi,2,0))<>0 then
      raise Exception.Create('GetAnsiBytes zero at end');
    If TEncoding.UTF8.GetAnsiString(Bytes,0,1)<>'A' then
      raise Exception.Create('GetAnsiString normal span');
    If TEncoding.UTF8.GetAnsiString(Bytes,1,0)<>'' then
      raise Exception.Create('GetAnsiString zero at end');

    ExpectEncodingError('byte count beyond end',
      procedure begin TEncoding.UTF8.GetCharCount(Bytes,0,3); end);
    ExpectEncodingError('byte negative index',
      procedure begin TEncoding.UTF8.GetCharCount(Bytes,-1,1); end);
    ExpectEncodingError('byte index beyond end',
      procedure begin TEncoding.UTF8.GetCharCount(Bytes,2,0); end);
    ExpectEncodingError('byte negative count',
      procedure begin TEncoding.UTF8.GetCharCount(Bytes,0,-1); end);
    ExpectEncodingError('byte low count',
      procedure begin TEncoding.UTF8.GetCharCount(Bytes,0,Low(Integer)); end);
    ExpectEncodingError('byte overflowing count',
      procedure begin TEncoding.UTF8.GetCharCount(Bytes,1,High(Integer)); end);
    ExpectEncodingError('char count beyond end',
      procedure begin TEncoding.UTF8.GetByteCount(Chars,0,3); end);
    ExpectEncodingError('char negative index',
      procedure begin TEncoding.UTF8.GetByteCount(Chars,-1,1); end);
    ExpectEncodingError('char index beyond end',
      procedure begin TEncoding.UTF8.GetByteCount(Chars,2,0); end);
    ExpectEncodingError('string invalid index zero',
      procedure begin TEncoding.UTF8.GetByteCount('A',0,0); end);
    ExpectEncodingError('string count beyond end',
      procedure begin TEncoding.UTF8.GetByteCount('A',1,High(Integer)); end);
    ExpectEncodingError('GetChars destination too small',
      procedure begin TEncoding.UTF8.GetChars(Bytes,0,1,DestinationChars,1); end);
    ExpectEncodingError('GetChars destination negative',
      procedure begin TEncoding.UTF8.GetChars(Bytes,0,1,DestinationChars,-1); end);
    ExpectEncodingError('GetChars source count beyond end',
      procedure begin TEncoding.UTF8.GetChars(Bytes,1,1,DestinationChars,0); end);
    ExpectEncodingError('GetBytes destination too small',
      procedure begin TEncoding.UTF8.GetBytes(Chars,0,1,DestinationBytes,1); end);
    ExpectEncodingError('GetBytes destination beyond end',
      procedure begin TEncoding.UTF8.GetBytes(Chars,0,1,DestinationBytes,2); end);
    ExpectEncodingError('GetBytes source count beyond end',
      procedure begin TEncoding.UTF8.GetBytes(Chars,1,1,DestinationBytes,0); end);
    ExpectEncodingError('GetBytes string destination too small',
      procedure begin TEncoding.UTF8.GetBytes('A',1,1,DestinationBytes,1); end);
    ExpectEncodingError('GetAnsiBytes index zero',
      procedure begin TEncoding.UTF8.GetAnsiBytes(Ansi,0,0); end);
    ExpectEncodingError('GetAnsiBytes count beyond end',
      procedure begin TEncoding.UTF8.GetAnsiBytes(Ansi,1,3); end);
    ExpectEncodingError('GetAnsiBytes overflowing count',
      procedure begin TEncoding.UTF8.GetAnsiBytes(Ansi,2,High(Integer)); end);
    ExpectEncodingError('GetAnsiString negative index',
      procedure begin TEncoding.UTF8.GetAnsiString(Bytes,-1,0); end);
    ExpectEncodingError('GetAnsiString count beyond end',
      procedure begin TEncoding.UTF8.GetAnsiString(Bytes,0,3); end);
    ExpectEncodingError('GetAnsiString overflowing count',
      procedure begin TEncoding.UTF8.GetAnsiString(Bytes,1,High(Integer)); end);

    WriteLn('ENCODING_SPAN_RANGES_OK');
  except
    on E: Exception do begin
      WriteLn('ENCODING_SPAN_RANGES_FAIL ',E.ClassName,': ',E.Message);
      Halt(1);
    end;
  end;
end.
