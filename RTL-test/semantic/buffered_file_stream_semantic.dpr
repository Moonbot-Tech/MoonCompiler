program buffered_file_stream_semantic;

{$mode delphi}{$H+}{$Q-}{$R-}

{ Classes.TBufferedFileStream (Delphi surface) and bufstream.TBufferedFileStream
  (fcl-base page cache) against the TFileStream oracle: the same sequence of
  Read/Write/Seek/Size calls must leave the same file, and Position/Size must
  agree at every step.  The frame pattern of MarketsU.SaveToFile - write a
  placeholder header, write the frame, seek back and patch the header, seek to
  the frame end - is the pattern on which the page cache corrupted 996 of 2001
  frames (planning/bufstream_repro_20260920.dpr).
  RTL-test/oracles/buffered_stream_oracle.dpr runs one random sequence under
  Delphi 12.2 and here: the outputs agree line for line except that Delphi's
  TBufferedFileStream accepts a seek to a negative offset (Position -9, the
  next Read returns other bytes) where its own TFileStream, and this one,
  answer -1 and keep the position. }

uses
  SysUtils,
  Classes,
  bufstream;

var
  Failures: Integer;
  Dir: string;

procedure Fail(const Msg: string);
begin
  Inc(Failures);
  If Failures <= 20 then
    WriteLn('FAIL ', Msg);
end;

procedure Check(Cond: Boolean; const Msg: string);
begin
  If not Cond then
    Fail(Msg);
end;

function FileBytes(const FileName: string): TBytes;
var
  F: TFileStream;
begin
  F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, F.Size);
    If F.Size > 0 then
      F.ReadBuffer(Result[0], F.Size);
  finally
    F.Free;
  end;
end;

function SameBytes(const A, B: TBytes): Boolean;
begin
  Result := (Length(A) = Length(B)) and ((Length(A) = 0) or CompareMem(@A[0], @B[0], Length(A)));
end;

function FirstDifference(const A, B: TBytes): Integer;
var
  I, N: Integer;
begin
  N := Length(A);
  If Length(B) < N then
    N := Length(B);
  for I := 0 to N - 1 do
    If A[I] <> B[I] then
      Exit(I);
  If Length(A) <> Length(B) then
    Exit(N);
  Result := -1;
end;

{ The two streams receive identical calls; Position and Size are compared
  after each. }
type
  TPair = record
    Name: string;
    Oracle: TFileStream;
    Tested: TStream;
    OracleFile, TestedFile: string;
    procedure Agree(const What: string);
    procedure Write(const Buffer; Count: Integer);
    procedure Read(var OracleBuffer, TestedBuffer; Count: Integer; const What: string);
    procedure SeekTo(Pos: Int64);
    procedure SeekBy(Delta: Int64; Origin: TSeekOrigin);
    procedure Resize(NewSize: Int64);
    procedure Close;
    function FilesEqual(const What: string): Boolean;
  end;

procedure TPair.Agree(const What: string);
begin
  If Oracle.Position <> Tested.Position then
    Fail(Format('%s: %s Position %d <> oracle %d', [Name, What, Tested.Position, Oracle.Position]));
  If Oracle.Size <> Tested.Size then
    Fail(Format('%s: %s Size %d <> oracle %d', [Name, What, Tested.Size, Oracle.Size]));
end;

procedure TPair.Write(const Buffer; Count: Integer);
begin
  Oracle.WriteBuffer(Buffer, Count);
  Tested.WriteBuffer(Buffer, Count);
  Agree('write');
end;

procedure TPair.Read(var OracleBuffer, TestedBuffer; Count: Integer; const What: string);
var
  A, B: Integer;
begin
  A := Oracle.Read(OracleBuffer, Count);
  B := Tested.Read(TestedBuffer, Count);
  If A <> B then
    Fail(Format('%s: %s Read returned %d <> oracle %d', [Name, What, B, A]))
  else If (A > 0) and not CompareMem(@OracleBuffer, @TestedBuffer, A) then
    Fail(Format('%s: %s Read data differs', [Name, What]));
  Agree('read');
end;

procedure TPair.SeekTo(Pos: Int64);
begin
  Oracle.Position := Pos;
  Tested.Position := Pos;
  Agree('seek');
end;

procedure TPair.SeekBy(Delta: Int64; Origin: TSeekOrigin);
var
  A, B: Int64;
begin
  A := Oracle.Seek(Delta, Origin);
  B := Tested.Seek(Delta, Origin);
  If A <> B then
    Fail(Format('%s: Seek returned %d <> oracle %d', [Name, B, A]));
  Agree('seek');
end;

procedure TPair.Resize(NewSize: Int64);
begin
  Oracle.Size := NewSize;
  Tested.Size := NewSize;
  Agree('resize');
end;

procedure TPair.Close;
begin
  FreeAndNil(Oracle);
  FreeAndNil(Tested);
end;

function TPair.FilesEqual(const What: string): Boolean;
var
  A, B: TBytes;
  D: Integer;
begin
  A := FileBytes(OracleFile);
  B := FileBytes(TestedFile);
  Result := SameBytes(A, B);
  If not Result then begin
    D := FirstDifference(A, B);
    Fail(Format('%s: %s file differs at %d (sizes %d / oracle %d)', [Name, What, D, Length(B), Length(A)]));
  end;
end;

type
  TKind = (kClasses, kBufStream);

const
  KindName: array[TKind] of string = ('Classes.TBufferedFileStream', 'bufstream.TBufferedFileStream');

function MakeTested(Kind: TKind; const FileName: string; Mode: Word; BufferSize: Integer): TStream;
begin
  case Kind of
    kClasses: Result := Classes.TBufferedFileStream.Create(FileName, Mode, BufferSize);
  else
    Result := bufstream.TBufferedFileStream.Create(FileName, Mode);
  end;
end;

function OpenPair(Kind: TKind; const Tag: string; Mode: Word; BufferSize: Integer): TPair;
begin
  Result.Name := KindName[Kind] + '/' + Tag;
  Result.OracleFile := Dir + Tag + '-oracle.bin';
  Result.TestedFile := Dir + Tag + '-' + IntToStr(Ord(Kind)) + '.bin';
  Result.Oracle := TFileStream.Create(Result.OracleFile, Mode);
  Result.Tested := MakeTested(Kind, Result.TestedFile, Mode, BufferSize);
end;

{ 1. the frame pattern: 2001 frames, header patched after each frame }
procedure FramePattern(Kind: TKind; BufferSize: Integer);
var
  P: TPair;
  I, K, N: Integer;
  HdrPos, FrameEnd: Int64;
  Buf: array[0..4095] of Byte;
  Zero: Integer;
begin
  P := OpenPair(Kind, 'frames' + IntToStr(BufferSize), fmCreate, BufferSize);
  try
    Zero := 0;
    for I := 0 to 2000 do begin
      HdrPos := P.Tested.Position;
      P.Write(Zero, 4);
      N := 100 + (I * 37) mod 3900;
      for K := 0 to N - 1 do
        Buf[K] := Byte(I + K);
      P.Write(Buf[0], N);
      FrameEnd := P.Tested.Position;
      P.SeekTo(HdrPos);
      P.Write(N, 4);
      P.SeekTo(FrameEnd);
    end;
  finally
    P.Close;
  end;
  P.FilesEqual('frames written');
end;

{ 2. read side: random seeks over a plain-written file, mixed read sizes }
procedure ReadSide(Kind: TKind; BufferSize: Integer);
var
  P: TPair;
  I, N: Integer;
  A, B: array[0..8191] of Byte;
  Seed: Cardinal;
  Src: TFileStream;
  Total: Int64;
  Data: TBytes;
begin
  { one file, written plainly, opened by both streams }
  Total := 300000;
  SetLength(Data, Total);
  for I := 0 to Total - 1 do
    Data[I] := Byte((I * 7) xor (I shr 9));
  Src := TFileStream.Create(Dir + 'readsrc.bin', fmCreate);
  try
    Src.WriteBuffer(Data[0], Total);
  finally
    Src.Free;
  end;
  P.Name := KindName[Kind] + '/read' + IntToStr(BufferSize);
  P.OracleFile := Dir + 'readsrc.bin';
  P.TestedFile := Dir + 'readsrc.bin';
  P.Oracle := TFileStream.Create(P.OracleFile, fmOpenRead or fmShareDenyNone);
  P.Tested := MakeTested(Kind, P.TestedFile, fmOpenRead or fmShareDenyNone, BufferSize);
  try
    Seed := 12345;
    for I := 0 to 3000 do begin
      Seed := Seed * 1103515245 + 12345;
      case (Seed shr 16) mod 5 of
        0: P.SeekTo((Seed shr 8) mod Cardinal(Total + 1000));      { anywhere, past the end too }
        1: P.SeekBy(-Integer((Seed shr 8) mod 100), soCurrent);   { a little back }
        2: P.SeekBy(-Integer((Seed shr 8) mod 5000), soEnd);
        else ;                                                    { sequential }
      end;
      If P.Tested.Position < 0 then
        P.SeekTo(0);
      N := 1 + (Seed shr 10) mod 8191;
      P.Read(A, B, N, 'random read');
    end;
    { byte by byte around a window boundary }
    P.SeekTo(BufferSize - 3);
    for I := 0 to 7 do
      P.Read(A, B, 1, 'boundary read');
    { larger than the window }
    P.SeekTo(17);
    P.Read(A, B, 8192, 'large read');
  finally
    P.Close;
  end;
end;

{ 3. mixed writes and reads at one point, blocks larger than the window,
     Size/Position during buffered writes, SetSize down and up, reopen }
procedure MixedPattern(Kind: TKind; BufferSize: Integer);
var
  P: TPair;
  I: Integer;
  A, B, Big: array[0..65535] of Byte;
  Small: Integer;
begin
  for I := 0 to High(Big) do
    Big[I] := Byte(I * 13 + 1);
  P := OpenPair(Kind, 'mixed' + IntToStr(BufferSize), fmCreate, BufferSize);
  try
    Small := $11223344;
    for I := 0 to 99 do
      P.Write(Small, 4);
    Check(P.Tested.Size = 400, P.Name + ': size counts unflushed writes');
    Check(P.Tested.Position = 400, P.Name + ': position after unflushed writes');
    { write, read back at the same point, write again }
    P.SeekTo(200);
    P.Read(A, B, 8, 'read after write');
    P.SeekTo(200);
    Small := $55667788;
    P.Write(Small, 4);
    P.SeekTo(198);
    P.Read(A, B, 8, 'read over the rewritten bytes');
    { block larger than the window, then small writes behind it }
    P.SeekBy(0, soEnd);
    P.Write(Big[0], SizeOf(Big));
    P.Write(Small, 4);
    P.Write(Small, 4);
    P.SeekTo(400 + 1000);
    P.Read(A, B, 16, 'read inside the large block');
    { write far past the end (hole), read the hole and the data }
    P.SeekTo(P.Tested.Size + 3000);
    P.Write(Small, 4);
    P.SeekTo(P.Tested.Size - 3100);
    P.Read(A, B, 3200, 'read across the hole');
    { shrink below pending writes, then grow }
    P.SeekBy(0, soEnd);
    P.Write(Big[0], 100);
    P.Resize(500);
    P.SeekTo(490);
    P.Read(A, B, 64, 'read at the truncated end');
    P.Resize(9000);
    P.SeekTo(8990);
    P.Read(A, B, 64, 'read the grown end');
    P.SeekTo(400);
    P.Write(Big[0], 300);
    { seeks that stay inside the window and beyond it }
    P.SeekBy(-100, soCurrent);
    P.Read(A, B, 50, 'read after relative seek');
    P.SeekBy(-1, soBeginning);   { invalid: answered -1, position kept }
    P.Read(A, B, 10, 'read after invalid seek');
  finally
    P.Close;
  end;
  P.FilesEqual('mixed');
  { reopen for reading with the tested class }
  P.Oracle := TFileStream.Create(P.OracleFile, fmOpenRead);
  P.Tested := MakeTested(Kind, P.TestedFile, fmOpenRead, BufferSize);
  try
    P.Agree('reopen');
    P.Read(A, B, 4096, 'reopened read');
    P.SeekBy(-10, soEnd);
    P.Read(A, B, 100, 'reopened tail read');
  finally
    P.Close;
  end;
end;

{ 4. FlushBuffer: pending bytes reach the OS, the handle stands at Position }
procedure FlushSemantics(BufferSize: Integer);
var
  S: Classes.TBufferedFileStream;
  Plain: TFileStream;
  V: Integer;
  B: array[0..15] of Byte;
begin
  S := Classes.TBufferedFileStream.Create(Dir + 'flush.bin', fmCreate or fmShareDenyNone, BufferSize);
  try
    V := $0A0B0C0D;
    S.WriteBuffer(V, 4);
    S.WriteBuffer(V, 4);
    Plain := TFileStream.Create(Dir + 'flush.bin', fmOpenRead or fmShareDenyNone);
    try
      Check(Plain.Size = 0, 'small writes are buffered, not yet on disk');
    finally
      Plain.Free;
    end;
    S.Position := 4;
    S.FlushBuffer;
    Plain := TFileStream.Create(Dir + 'flush.bin', fmOpenRead or fmShareDenyNone);
    try
      Check(Plain.Size = 8, 'FlushBuffer wrote the pending bytes: ' + IntToStr(Plain.Size));
    finally
      Plain.Free;
    end;
    { the handle stands at Position: a raw read on it sees byte 4 }
    Check(FileRead(S.Handle, B[0], 4) = 4, 'raw read on the handle after FlushBuffer');
    Check(PInteger(@B[0])^ = V, 'raw read reads from Position');
    Check(S.Position = 4, 'FlushBuffer keeps Position');
    Check(FileFlush(S.Handle), 'fsync on the handle after FlushBuffer');
    S.Position := 0;
    S.ReadBuffer(B[0], 8);
    Check((PInteger(@B[0])^ = V) and (PInteger(@B[4])^ = V), 'read after FlushBuffer');
  finally
    S.Free;
  end;
end;

{ 5. constructor overloads: buffer size versus rights }
procedure Overloads;
var
  S: Classes.TBufferedFileStream;
  V: Integer;
begin
  S := Classes.TBufferedFileStream.Create(Dir + 'ovl.bin', fmCreate, 4096);
  try
    V := 7;
    S.WriteBuffer(V, 4);
  finally
    S.Free;
  end;
  S := Classes.TBufferedFileStream.Create(Dir + 'ovl.bin', fmOpenRead, 438, 4096);
  try
    Check(S.Size = 4, 'rights overload opens the file');
    S.ReadBuffer(V, 4);
    Check(V = 7, 'rights overload reads');
  finally
    S.Free;
  end;
  S := Classes.TBufferedFileStream.Create(Dir + 'ovl.bin', fmOpenRead);
  try
    Check(S.Size = 4, 'default buffer size overload');
  finally
    S.Free;
  end;
  try
    S := Classes.TBufferedFileStream.Create(Dir + 'ovl.bin', fmOpenRead, 0);
    S.Free;
    Fail('buffer size 0 accepted');
  except
    on E: EStreamError do ;
  end;
end;

{ Seek inside the window keeps pending bytes; seek from end and outside
  the window commit them, even before another read or write. }
procedure SeekFlushSemantics;
var
  S: Classes.TBufferedFileStream;
  Plain: TFileStream;
  V: Integer;
begin
  S := Classes.TBufferedFileStream.Create(Dir + 'seek-flush.bin', fmCreate or fmShareDenyNone, 16);
  try
    Plain := TFileStream.Create(Dir + 'seek-flush.bin', fmOpenRead or fmShareDenyNone);
    try
      V := 42;
      S.WriteBuffer(V, SizeOf(V));
      S.Seek(2, soBeginning);
      Check(Plain.Size = 0, 'seek inside the window keeps pending bytes');
      S.Seek(0, soEnd);
      Check(Plain.Size = 4, 'seek from end flushes pending bytes');
      S.WriteBuffer(V, SizeOf(V));
      S.Seek(32, soBeginning);
      Check(Plain.Size = 8, 'seek outside the window flushes pending bytes');
      Check(S.Position = 32, 'seek outside the window sets requested position');
    finally
      Plain.Free;
    end;
  finally
    S.Free;
  end;
end;

procedure RemoveTemporaries;
var
  SR: TSearchRec;
begin
  If FindFirst(Dir + '*', faAnyFile, SR) = 0 then begin
    repeat
      If (SR.Attr and faDirectory) = 0 then
        DeleteFile(Dir + SR.Name);
    until FindNext(SR) <> 0;
    FindClose(SR);
  end;
  RemoveDir(Dir);
end;

const
  BufferSizes: array[0..1] of Integer = (4096, 32768);

var
  Kind: TKind;
  BufferSize: Integer;
begin
  Failures := 0;
  Dir := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'rtl-bufstream-' + IntToStr(GetProcessID) + PathDelim;
  ForceDirectories(Dir);
  try
    for Kind := Low(TKind) to High(TKind) do
      for BufferSize in BufferSizes do begin
        FramePattern(Kind, BufferSize);
        ReadSide(Kind, BufferSize);
        MixedPattern(Kind, BufferSize);
      end;
    FlushSemantics(4096);
    FlushSemantics(32768);
    Overloads;
    SeekFlushSemantics;
  finally
    RemoveTemporaries;
  end;
  If Failures <> 0 then begin
    WriteLn('FAILURES ', Failures);
    Halt(1);
  end;
  WriteLn('BUFFERED_FILE_STREAM_PASS');
end.
