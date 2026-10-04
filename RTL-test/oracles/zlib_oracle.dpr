program zlib_oracle;

{ System.ZLib differential oracle, compiled by Delphi 12.2 and by
  MoonCompiler (zlib 1.3.1 in both: Delphi's unit declares ZLIB_VERSION
  '1.2.13', its objects are 1.3.1): the buffer and string helpers, the compression
  and decompression streams with chunked writes and reads, seeks in every
  direction, sizes, rates, progress events and the errors on damaged input.
  Compressed bytes are printed as size + digest; where the two zlib versions
  emit different bytes for the same input the line is marked so and only the
  round trip is compared. }

{$ifndef FPC}
  {$APPTYPE CONSOLE}
{$endif}
{$ifdef FPC}
  {$mode delphi}{$H+}
{$endif}

uses
  SysUtils, Classes, System.ZLib;

var
  Progress: Integer;

function Digest(const P: PByte; N: Integer): string;
var
  H: Cardinal;
  I: Integer;
begin
  H := 2166136261;
  for I := 0 to N - 1 do
    H := (H xor P[I]) * 16777619;
  Result := IntToHex(H, 8);
end;

function DigestBytes(const B: TBytes): string;
begin
  if Length(B) = 0 then
    Result := IntToStr(0) + ':' + Digest(nil, 0)
  else
    Result := IntToStr(Length(B)) + ':' + Digest(@B[0], Length(B));
end;

function Same(const A, B: TBytes): Boolean;
begin
  Result := (Length(A) = Length(B)) and ((Length(A) = 0) or CompareMem(@A[0], @B[0], Length(A)));
end;

procedure OnProgressHandler(Sender: TObject);
begin
  Inc(Progress);
end;

type
  TProgressSink = class
    procedure Hit(Sender: TObject);
  end;

procedure TProgressSink.Hit(Sender: TObject);
begin
  Inc(Progress);
end;

var
  Inputs: array[0..5] of TBytes;
  Names: array[0..5] of string = ('empty', 'one', 'runs', 'text', 'random', 'big');

procedure BuildInputs;
var
  I: Integer;
  S: AnsiString;
  Seed: Cardinal;
begin
  Inputs[0] := nil;
  SetLength(Inputs[1], 1); Inputs[1][0] := 65;
  SetLength(Inputs[2], 5000);
  for I := 0 to 4999 do
    Inputs[2][I] := Byte(97 + (I div 700));
  S := '';
  for I := 1 to 300 do
    S := S + AnsiString('line ' + IntToStr(I) + ': the quick brown fox jumps over the lazy dog'#13#10);
  SetLength(Inputs[3], Length(S));
  Move(S[1], Inputs[3][0], Length(S));
  Seed := 42;
  SetLength(Inputs[4], 20000);
  for I := 0 to 19999 do
  begin
    Seed := Seed * 1103515245 + 12345;
    Inputs[4][I] := Byte(Seed shr 16);
  end;
  SetLength(Inputs[5], 300000);
  Seed := 7;
  for I := 0 to 299999 do
  begin
    if (I mod 1000) < 900 then
      Inputs[5][I] := Byte(I div 3000)
    else
    begin
      Seed := Seed * 1103515245 + 12345;
      Inputs[5][I] := Byte(Seed shr 16);
    end;
  end;
end;

procedure Buffers;
var
  I: Integer;
  L: TZCompressionLevel;
  C, D: TBytes;
begin
  for I := 0 to High(Inputs) do
    for L := zcNone to zcMax do
    begin
      ZCompress(Inputs[I], C, L);
      ZDecompress(C, D);
      WriteLn('zcompress ', Names[I], ' ', Ord(L), ' -> ', DigestBytes(C), ' roundtrip ', Same(D, Inputs[I]));
      ZDecompress(C, D, Length(Inputs[I]) + 7);
      WriteLn('zdecompress-estimate ', Names[I], ' ', Ord(L), ' ', Same(D, Inputs[I]));
    end;
end;

procedure Strings;
var
  C: TBytes;
  S: string;
begin
  C := ZCompressStr('hello, ' + #$0417#$0434#$0440#$0430#$0432#$0441#$0442#$0432#$0443#$0439 + ' world');
  WriteLn('zcompressstr -> ', DigestBytes(C));
  S := ZDecompressStr(C);
  WriteLn('zdecompressstr -> ', Length(S), ' ', S = 'hello, ' + #$0417#$0434#$0440#$0430#$0432#$0441#$0442#$0432#$0443#$0439 + ' world');
  C := ZCompressStr('', zcMax);
  WriteLn('zcompressstr-empty -> ', DigestBytes(C), ' ', ZDecompressStr(C) = '');
end;

procedure Streams(WindowBits: Integer);
var
  I, N, Got, Chunk: Integer;
  Src, Dst: TMemoryStream;
  Z: TZCompressionStream;
  U: TZDecompressionStream;
  Buf: TBytes;
  Out: TBytes;
  P: Int64;
  Sink: TProgressSink;
begin
  Sink := TProgressSink.Create;
  for I := 0 to High(Inputs) do
  begin
    Dst := TMemoryStream.Create;
    Z := TZCompressionStream.Create(Dst, zcDefault, WindowBits);
    try
      Progress := 0;
      Z.OnProgress := Sink.Hit;
      N := 0;
      Chunk := 1;
      while N < Length(Inputs[I]) do
      begin
        if N + Chunk > Length(Inputs[I]) then
          Chunk := Length(Inputs[I]) - N;
        Got := Z.Write(Inputs[I][N], Chunk);
        Inc(N, Got);
        Chunk := Chunk * 3 + 1;
      end;
      WriteLn('zstream ', WindowBits, ' ', Names[I], ' position ', Z.Position, ' rate ', FormatFloat('0.###', Z.CompressionRate),
        ' progress ', Progress);
      try
        Z.Seek(0, soBeginning);
        WriteLn('zstream seek-begin accepted');
      except
        on E: Exception do
          WriteLn('zstream seek-begin ', E.ClassName);
      end;
      WriteLn('zstream seek-cur-0 ', Z.Seek(0, soCurrent));
    finally
      Z.Free;
    end;
    WriteLn('zstream ', WindowBits, ' ', Names[I], ' output ', IntToStr(Dst.Size), ':', Digest(Dst.Memory, Dst.Size));

    { read back in growing chunks }
    Dst.Position := 0;
    U := TZDecompressionStream.Create(Dst, WindowBits);
    try
      Progress := 0;
      U.OnProgress := Sink.Hit;
      SetLength(Out, Length(Inputs[I]) + 64);
      N := 0;
      Chunk := 1;
      repeat
        if N + Chunk > Length(Out) then
          Chunk := Length(Out) - N;
        Got := U.Read(Out[N], Chunk);
        Inc(N, Got);
        Chunk := Chunk * 2 + 3;
      until (Got = 0) or (N >= Length(Out));
      SetLength(Out, N);
      WriteLn('unzstream ', WindowBits, ' ', Names[I], ' read ', N, ' same ', Same(Out, Inputs[I]), ' position ', U.Position,
        ' progress ', Progress);
      WriteLn('unzstream read-at-end ', U.Read(Buf, 0));
      { seeks: back to the start, forward inside, backward inside, to the end }
      SetLength(Buf, 10);
      try
        P := U.Seek(0, soBeginning);
        Got := U.Read(Buf[0], 10);
        WriteLn('unzstream seek-begin ', P, ' read10 ', Got, ' ', Digest(@Buf[0], Got));
      except
        on E: Exception do
          WriteLn('unzstream seek-begin ', E.ClassName);
      end;
      try
        P := U.Seek(100, soCurrent);
        Got := U.Read(Buf[0], 10);
        WriteLn('unzstream seek-cur+100 ', P, ' read10 ', Got, ' ', Digest(@Buf[0], Got), ' position ', U.Position);
      except
        on E: Exception do
          WriteLn('unzstream seek-cur+100 ', E.ClassName, ' position ', U.Position);
      end;
      try
        P := U.Seek(-50, soCurrent);
        Got := U.Read(Buf[0], 10);
        WriteLn('unzstream seek-cur-50 ', P, ' read10 ', Got, ' ', Digest(@Buf[0], Got));
      except
        on E: Exception do
          WriteLn('unzstream seek-cur-50 ', E.ClassName);
      end;
      try
        P := U.Seek(0, soEnd);
        WriteLn('unzstream seek-end ', P, ' size ', U.Size);
      except
        on E: Exception do
          WriteLn('unzstream seek-end ', E.ClassName);
      end;
      try
        P := U.Seek(5, soBeginning);
        Got := U.Read(Buf[0], 10);
        WriteLn('unzstream seek-begin5 ', P, ' read10 ', Got, ' ', Digest(@Buf[0], Got));
      except
        on E: Exception do
          WriteLn('unzstream seek-begin5 ', E.ClassName);
      end;
    finally
      U.Free;
    end;
    Dst.Free;
  end;
  Sink.Free;
end;

procedure Errors;
var
  C, D: TBytes;
  M: TMemoryStream;
  U: TZDecompressionStream;
  Buf: array[0..99] of Byte;
  Got: Integer;
begin
  ZCompress(Inputs[3], C);
  C[Length(C) div 2] := C[Length(C) div 2] xor $FF;
  try
    ZDecompress(C, D);
    WriteLn('zdecompress damaged: no error, ', Length(D));
  except
    on E: Exception do
      WriteLn('zdecompress damaged: ', E.ClassName);
  end;
  M := TMemoryStream.Create;
  try
    M.WriteBuffer(C[0], Length(C));
    M.Position := 0;
    U := TZDecompressionStream.Create(M);
    try
      try
        Got := 0;
        repeat
          Got := U.Read(Buf, SizeOf(Buf));
        until Got = 0;
        WriteLn('unzstream damaged: no error');
      except
        on E: Exception do
          WriteLn('unzstream damaged: ', E.ClassName);
      end;
    finally
      U.Free;
    end;
    { not a zlib stream at all }
    M.Clear;
    M.WriteBuffer(PAnsiChar('this is not compressed data at all')^, 34);
    M.Position := 0;
    U := TZDecompressionStream.Create(M);
    try
      try
        Got := U.Read(Buf, SizeOf(Buf));
        WriteLn('unzstream garbage: no error, ', Got);
      except
        on E: Exception do
          WriteLn('unzstream garbage: ', E.ClassName);
      end;
    finally
      U.Free;
    end;
    { truncated }
    M.Clear;
    ZCompress(Inputs[3], C);
    M.WriteBuffer(C[0], Length(C) div 2);
    M.Position := 0;
    U := TZDecompressionStream.Create(M);
    try
      try
        Got := 0;
        repeat
          Got := U.Read(Buf, SizeOf(Buf));
        until Got = 0;
        WriteLn('unzstream truncated: no error');
      except
        on E: Exception do
          WriteLn('unzstream truncated: ', E.ClassName);
      end;
    finally
      U.Free;
    end;
  finally
    M.Free;
  end;
  try
    ZDecompress(nil, D);
    WriteLn('zdecompress nil: ', Length(D));
  except
    on E: Exception do
      WriteLn('zdecompress nil: ', E.ClassName);
  end;
end;

procedure StreamHelpers;
var
  A, B, C: TMemoryStream;
begin
  A := TMemoryStream.Create; B := TMemoryStream.Create; C := TMemoryStream.Create;
  try
    A.WriteBuffer(Inputs[3][0], Length(Inputs[3]));
    A.Position := 100;
    ZCompressStream(A, B, zcFastest);
    WriteLn('zcompressstream from position 100 -> ', IntToStr(B.Size), ':', Digest(B.Memory, B.Size), ' a.pos ', A.Position, ' b.pos ', B.Position);
    B.Position := 0;
    ZDecompressStream(B, C);
    WriteLn('zdecompressstream -> ', C.Size, ' ', CompareMem(C.Memory, @Inputs[3][100], Length(Inputs[3]) - 100), ' b.pos ', B.Position, ' c.pos ', C.Position);
  finally
    A.Free; B.Free; C.Free;
  end;
end;

begin
  BuildInputs;
  Buffers;
  Strings;
  Streams(15);
  Streams(-15);
  Streams(31);
  Errors;
  StreamHelpers;
  WriteLn('ZLIB_ORACLE_END');
end.
