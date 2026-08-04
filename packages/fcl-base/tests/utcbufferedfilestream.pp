unit utcBufferedFileStream;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, punit, bufstream;

procedure RegisterTests;

implementation

const
  TEST_RANDOM_READS=10000;
  TEST_SEQUENTIAL_READS=1000000;
  TEST_FILENAME='testfile.bin';
  TEST_WRITEC_FILE='testwritecache.bin';
  TEST_WRITEF_FILE='testwritedirec.bin';

function CompareStreams(const aStream1: TStream; const aStream2: TStream): Boolean;
const
  BUFFER_SIZE=5213; // Odd number
var
  b1: array [0..BUFFER_SIZE-1] of BYTE;
  b2: array [0..BUFFER_SIZE-1] of BYTE;
  lReadBytes: integer;
  lAvailable: integer;
  lEffectiveRead1: integer;
  lEffectiveRead2: integer;
begin
  b1[0]:=0; // Avoid initialization hint
  b2[0]:=0; // Avoid initialization hint
  Result:=false;
  if aStream1.Size<>aStream2.Size then exit;
  aStream1.Position:=0;
  aStream2.Position:=0;
  while aStream1.Position<aStream1.Size do begin
    lAvailable:=aStream1.Size-aStream1.Position;
    if lAvailable>=BUFFER_SIZE then begin
      lReadBytes:=BUFFER_SIZE;
    end else begin
      lReadBytes:=aStream1.Size-aStream1.Position;
    end;
    lEffectiveRead1:=aStream1.Read(b1[0],lReadBytes);
    lEffectiveRead2:=aStream2.Read(b2[0],lReadBytes);
    if lEffectiveRead1<>lEffectiveRead2 then exit;
    if not CompareMem(@b1[0],@b2[0],lEffectiveRead1) then exit;
  end;
  Result:=true;
end;

function Setup: TTestString;
var
  F: TFileStream;
  b: array [0..10000-1] of AnsiChar;
  j: integer;
begin
  Result := '';
  for j := 0 to Pred(10000) do begin
    b[j]:=AnsiChar(ord('0')+j mod 10);
  end;
  try
    F:=TFileStream.Create(TEST_FILENAME,fmCreate);
    try
      for j := 0 to Pred(1000) do begin
        F.Write(b,sizeof(b));
      end;
    finally
      F.Free;
    end;
  except
    On E: Exception do
      Result := 'Setup failed: ' + E.Message;
  end;
end;

function TearDown: TTestString;
begin
  Result := '';
  try
    DeleteFile(TEST_FILENAME);
    DeleteFile(TEST_WRITEC_FILE);
    DeleteFile(TEST_WRITEF_FILE);
  except
    On E: Exception do
      Result := 'TearDown failed: ' + E.Message;
  end;
end;

function TBufferedFileStream_TestCacheRead : TTestString;
var
  lBufferedStream: TBufferedFileStream;
  lStream: TFileStream;
  b: array [0..10000-1] of AnsiChar;
  j,k: integer;
  lBytesToRead: integer;
  lEffectiveRead: integer;
  lReadPosition: int64;
  lCheckInitV: integer;
begin
  Result := '';
  b[0]:=#0; // Avoid initialization hint
  lBufferedStream:=TBufferedFileStream.Create(TEST_FILENAME,fmOpenRead or fmShareDenyWrite);
  lStream:=TFileStream.Create(TEST_FILENAME,fmOpenRead or fmShareDenyWrite);
  try
    RandSeed:=1;
    Randomize;
    for j := 0 to Pred(TEST_RANDOM_READS) do begin
      lBytesToRead:=Random(10000);
      lReadPosition:=Random(lBufferedStream.Size);
      lBufferedStream.Position:=lReadPosition;
      lEffectiveRead:=lBufferedStream.Read(b,lBytesToRead);

      lCheckInitV:=lReadPosition mod 10;
      for k := 0 to Pred(lEffectiveRead) do begin
        if b[k]<>AnsiChar(ord('0')+lCheckInitV mod 10) then
        begin
          Result := 'Expected data error in random read test';
          Exit;
        end;
        inc(lCheckInitV);
      end;
    end;

    lBytesToRead:=1;
    lReadPosition:=0;
    lBufferedStream.Position:=lReadPosition;
    for j := 0 to Pred(TEST_SEQUENTIAL_READS) do begin
      lEffectiveRead:=lBufferedStream.Read(b,lBytesToRead);
      lCheckInitV:=lReadPosition mod 10;
      for k := 0 to Pred(lEffectiveRead) do begin
        if b[k]<>AnsiChar(ord('0')+lCheckInitV mod 10) then
        begin
          Result := 'Expected data error in sequential read test';
          Exit;
        end;
        inc(lCheckInitV);
      end;
      inc(lReadPosition,lBytesToRead);
    end;

    lBufferedStream.Position:=lBufferedStream.Size-1;
    lEffectiveRead:=lBufferedStream.Read(b,2);
    if lEffectiveRead<>1 then
    begin
      Result := 'Read beyond limits, returned bytes: '+inttostr(lEffectiveRead);
      Exit;
    end;
  finally
    lBufferedStream.Free;
    lStream.Free;
  end;
end;

function TBufferedFileStream_TestCacheWrite : TTestString;
const
  EXPECTED_SIZE=10000000;
  TEST_ROUNDS=100000;
var
  lBufferedStream: TBufferedFileStream;
  lStream: TFileStream;
  lVerifyStream1,lVerifyStream2: TFileStream;
  b: array [0..10000-1] of AnsiChar;
  j: integer;
  lBytesToWrite: integer;
  lWritePosition: int64;
begin
  Result := '';
  RandSeed:=1;
  Randomize;
  for j := 0 to Pred(10000) do
    b[j]:='0';

  lBufferedStream:=TBufferedFileStream.Create(TEST_WRITEC_FILE,fmCreate);
  lStream:=TFileStream.Create(TEST_WRITEF_FILE,fmCreate);
  try
    for j := 0 to Pred(EXPECTED_SIZE div Sizeof(b)) do
    begin
      lBufferedStream.Write(b,sizeof(b));
      lStream.Write(b,sizeof(b));
    end;
    for j := 0 to Pred(Sizeof(b)) do
      b[j]:=AnsiChar(ord('0')+j mod 10);
  finally
    lBufferedStream.Free;
    lStream.Free;
  end;

  lBufferedStream:=TBufferedFileStream.Create(TEST_WRITEC_FILE,fmOpenReadWrite);
  lStream:=TFileStream.Create(TEST_WRITEF_FILE,fmOpenWrite);
  try
    for j := 0 to Pred(TEST_ROUNDS) do
    begin
      if lStream.Size<>lBufferedStream.Size then
      begin
        Result := 'Mismatched lengths during write';
        Exit;
      end;
      lWritePosition:=Random(EXPECTED_SIZE);
      lBytesToWrite:=Random(sizeof(b));
      lBufferedStream.Position:=lWritePosition;
      lStream.Position:=lWritePosition;
      lBufferedStream.Write(b,lBytesToWrite);
      lStream.Write(b,lBytesToWrite);
    end;
    if lStream.Size<>lBufferedStream.Size then
    begin
      Result := 'Mismatched lengths after write';
      Exit;
    end;
  finally
    lBufferedStream.Free;
    lStream.Free;
  end;

  lVerifyStream1:=TFileStream.Create(TEST_WRITEC_FILE,fmOpenRead or fmShareDenyWrite);
  lVerifyStream2:=TFileStream.Create(TEST_WRITEF_FILE,fmOpenRead or fmShareDenyWrite);
  try
    if not CompareStreams(lVerifyStream1,lVerifyStream2) then
    begin
      Result := 'Streams are different after write test!';
      Exit;
    end;
  finally
    lVerifyStream1.Free;
    lVerifyStream2.Free;
  end;
end;

function TBufferedFileStream_TestCacheSeek : TTestString;
var
  lBufferedStream: TBufferedFileStream;
  lStream: TFileStream;
  bBuffered: array [0..10000] of BYTE;
  bStream: array [0..10000] of BYTE;
  bread : Integer;
begin
  Result := '';
  bBuffered[0]:=0;
  bStream[0]:=0;
  lBufferedStream:=TBufferedFileStream.Create(TEST_FILENAME,fmOpenRead or fmShareDenyWrite);
  lStream:=TFileStream.Create(TEST_FILENAME,fmOpenRead or fmShareDenyWrite);
  try
    lStream.Position:=-1;
    lBufferedStream.Position:=-1;
    if lStream.Position<>lBufferedStream.Position then
    begin
      Result := 'Positions are not the same after setting to -1.';
      Exit;
    end;

    lStream.Read(bBuffered[0],10);
    lBufferedStream.Read(bStream[0],10);
    if (not CompareMem(@bBuffered[0],@bStream[0],10)) or (lStream.Position<>lBufferedStream.Position) then
    begin
      Result := 'Read data or positions are not the same after reading at -1.';
      Exit;
    end;

    lStream.Seek(-1,soBeginning);
    lBufferedStream.Seek(-1,soBeginning);

    lStream.Read(bBuffered[0],10);
    lBufferedStream.Read(bStream[0],10);
    if (not CompareMem(@bBuffered[0],@bStream[0],10)) or (lStream.Position<>lBufferedStream.Position) then
    begin
      Result := 'Read data or positions are not the same after seeking to -1.';
      Exit;
    end;

    lStream.Seek(lStream.Position*-2,soCurrent);
    lBufferedStream.Seek(lBufferedStream.Position*-2,soCurrent);
    lStream.Read(bBuffered[0],10);
    lBufferedStream.Read(bStream[0],10);
    if (not CompareMem(@bBuffered[0],@bStream[0],10)) or (lStream.Position<>lBufferedStream.Position) then
    begin
      Result := 'Read data or positions are not the same after seeking from current.';
      Exit;
    end;
  finally
    lBufferedStream.Free;
    lStream.Free;
  end;
end;


procedure TTestBufferedFileStream_TestSetSize;
var
  Filename: string;
  Stream: TStream;
begin
  Stream := nil;
  Filename := ExpandFileName('~/66E9541B9C0D482BBDB98D911E6E3415.tst');
  try
    Stream := TBufferedFileStream.Create(Filename, fmCreate);
    Stream.Size := 1024;
  finally
    Stream.Free;
    DeleteFile(Filename);
  end;
end;

procedure TTestBufferedFileStream_TestWriteBeyondEOF;
var
  testfile : string;
  fs: TBufferedFileStream;
  buf: array[0..15] of byte;
  i: integer;
  readback: array[0..15] of byte;
  ok: boolean;
begin
  for i := 0 to High(buf) do
    buf[i] := i + 1;
  // Create a small file (8 bytes)
  TestFile := ExpandFileName('66E9541B9C0D482BBDB98D911E6E3415.tst');
  fs := TBufferedFileStream.Create(TestFile, fmCreate);
  try
    fs.Write(buf[0], 8);
  finally
    fs.Free;
  end;
  // Re-open and write beyond EOF - this triggers bug 40391
  fs := TBufferedFileStream.Create(TestFile, fmOpenReadWrite);
  try
    // Seek past EOF and write there
    fs.Seek(16384, soBeginning);  // well beyond the 8-byte file
    fs.Write(buf[0], 16);

    // Verify: read back what we wrote
    fs.Seek(16384, soBeginning);
    FillChar(readback, SizeOf(readback), 0);
    fs.Read(readback[0], 16);

    ok := true;
    for i := 0 to 15 do
      if not AssertEquals(Format('FAIL: mismatch at offset %d ',[i]), buf[i], readback[i]) then
        exit;

  finally
    DeleteFile(TestFile);
    fs.Free;
  end;
end;

procedure TTestBufferedFileStream_TestWriteExtendFile;
var
  fs: TBufferedFileStream;
  val: longint;
  readval: longint;
  TestFile : string;
begin
  // Create an empty file, write at offset 0 (file has size 0,
  // so even offset 0 means ReadPageBeforeWrite reads 0 bytes)
  fs:=nil;
  TestFile := ExpandFileName('66E9541B9C0D482BBDB98D911E6E3415.tst');
  try
    fs := TBufferedFileStream.Create(TestFile, fmCreate);
    fs.Free;

    fs := TBufferedFileStream.Create(TestFile, fmOpenReadWrite);
    val := $DEADBEEF;
    fs.Write(val, SizeOf(val));

    fs.Seek(0, soBeginning);
    readval := 0;
    fs.Read(readval, SizeOf(readval));

    AssertEquals('Write to empty file succeeded',val,readval);
  finally
    DeleteFile(TestFile);
    fs.Free;
  end;

end;


procedure RegisterTests;
begin
  AddSuite('TBufferedFileStreamTests', @Setup, @TearDown);
  AddTest('TestCacheRead', @TBufferedFileStream_TestCacheRead, 'TBufferedFileStreamTests');
  AddTest('TestCacheWrite', @TBufferedFileStream_TestCacheWrite, 'TBufferedFileStreamTests');
  AddTest('TestCacheSeek', @TBufferedFileStream_TestCacheSeek, 'TBufferedFileStreamTests');
  AddTest('TestSetSize', @TTestBufferedFileStream_TestSetSize,'TBufferedFileStreamTests');
  AddTest('TestWriteBeyondEOF', @TTestBufferedFileStream_TestWriteBeyondEOF,'TBufferedFileStreamTests');
  AddTest('TestWriteExtendFile', @TTestBufferedFileStream_TestWriteExtendFile,'TBufferedFileStreamTests');
end;

end.
