program zlib_semantic;

{$mode delphi}{$H+}

{ System.ZLib (planning contract 2.1) over the native zlib: the zlib.h
  functions, the two streams and the helpers.  Oracles are the standards -
  RFC 1950/1951/1952 framing, the CRC-32 and Adler-32 check values of the
  specifications - and round trips, never this compiler's own answer.
  RTL-test/oracles/zlib_oracle.dpr compares the unit with Delphi 12.2's:
  the compressed bytes are identical for every input and level (zlib 1.3.1
  in both; Delphi's unit declares ZLIB_VERSION '1.2.13'), the stream
  positions, sizes, rates, error classes and seeks agree, with two known
  differences: Delphi's ZCompressStr('') ignores the level (a default-level
  header for an empty string, this one honours it), and Delphi's
  decompression stream fires OnProgress once more, for the final refill
  that reads nothing; this one fires it per refill that brought input. }

uses
  {$ifdef MSWINDOWS}Windows,{$endif}
  {$ifdef UNIX}BaseUnix,{$endif}
  SysUtils,
  Classes,
  System.ZLib;

var
  Failures: Integer;

procedure Check(Cond: Boolean; const Msg: string);
begin
  If not Cond then begin
    Inc(Failures);
    WriteLn('FAIL ', Msg);
  end;
end;

function Pattern(Size: Integer; Seed: Integer): TBytes;
var
  I: Integer;
begin
  SetLength(Result, Size);
  for I := 0 to Size - 1 do
    Result[I] := Byte((I * 7 + Seed) xor (I shr 5) xor ((I div 97) * 3));
end;

function SameBytes(const A, B: TBytes): Boolean;
begin
  Result := (Length(A) = Length(B)) and ((Length(A) = 0) or CompareMem(@A[0], @B[0], Length(A)));
end;

{ deflate/inflate through the raw functions with the given window bits }
function RawDeflate(const Data: TBytes; WindowBits: Integer; out Bound: LongWord): TBytes;
var
  S: z_stream;
  Code: Integer;
begin
  S := Default(z_stream);
  Check(deflateInit2(S, Z_DEFAULT_COMPRESSION, Z_DEFLATED, WindowBits, 8, Z_DEFAULT_STRATEGY) = Z_OK, 'deflateInit2');
  Bound := deflateBound(S, Length(Data));
  SetLength(Result, Bound);
  S.next_in := Pointer(Data);
  S.avail_in := Length(Data);
  S.next_out := Pointer(Result);
  S.avail_out := Length(Result);
  Code := deflate(S, Z_FINISH);
  Check(Code = Z_STREAM_END, 'deflate Z_FINISH in one call: ' + IntToStr(Code));
  SetLength(Result, S.total_out);
  Check(deflateEnd(S) = Z_OK, 'deflateEnd');
end;

function RawInflate(const Data: TBytes; WindowBits: Integer; Expected: Integer): TBytes;
var
  S: z_stream;
  Code: Integer;
begin
  S := Default(z_stream);
  Check(inflateInit2(S, WindowBits) = Z_OK, 'inflateInit2');
  SetLength(Result, Expected);
  S.next_in := Pointer(Data);
  S.avail_in := Length(Data);
  S.next_out := Pointer(Result);
  S.avail_out := Length(Result);
  Code := inflate(S, Z_FINISH);
  Check(Code = Z_STREAM_END, 'inflate Z_FINISH: ' + IntToStr(Code));
  Check(S.avail_in = 0, 'inflate consumed everything');
  SetLength(Result, S.total_out);
  Check(inflateEnd(S) = Z_OK, 'inflateEnd');
end;

procedure Framing;
var
  Data, Z, R: TBytes;
  Bound: LongWord;
begin
  Data := Pattern(20000, 1);
  { zlib: RFC 1950 header, CM=8, adler32 trailer }
  Z := RawDeflate(Data, 15, Bound);
  Check(LongWord(Length(Z)) <= Bound, 'deflateBound covers zlib output');
  Check((Length(Z) > 6) and (Z[0] and $0F = 8) and ((Z[0] * 256 + Z[1]) mod 31 = 0), 'RFC 1950 header');
  Check(SameBytes(RawInflate(Z, 15, Length(Data)), Data), 'zlib round trip');
  Check(SameBytes(RawInflate(Z, 47, Length(Data)), Data), 'zlib through auto-detect (32+15)');
  { gzip: RFC 1952 magic and CM }
  Z := RawDeflate(Data, 31, Bound);
  Check(LongWord(Length(Z)) <= Bound, 'deflateBound covers gzip output');
  Check((Length(Z) > 18) and (Z[0] = $1F) and (Z[1] = $8B) and (Z[2] = 8), 'RFC 1952 header');
  Check(PLongWord(@Z[Length(Z) - 4])^ = LongWord(Length(Data)), 'RFC 1952 ISIZE trailer');
  Check(PLongWord(@Z[Length(Z) - 8])^ = crc32(0, Pointer(Data), Length(Data)), 'RFC 1952 CRC32 trailer');
  Check(SameBytes(RawInflate(Z, 31, Length(Data)), Data), 'gzip round trip');
  Check(SameBytes(RawInflate(Z, 47, Length(Data)), Data), 'gzip through auto-detect');
  { raw deflate: no header at all; the zlib form minus its 2-byte header and 4-byte trailer }
  R := RawDeflate(Data, -15, Bound);
  Z := RawDeflate(Data, 15, Bound);
  Check(Length(R) = Length(Z) - 6, 'raw deflate is the zlib body');
  Check(CompareMem(@R[0], @Z[2], Length(R)), 'raw deflate bytes equal the zlib body');
  Check(SameBytes(RawInflate(R, -15, Length(Data)), Data), 'raw round trip');
  { empty input }
  Data := nil;
  Z := RawDeflate(Data, 15, Bound);
  Check(Length(Z) = 8, 'empty zlib stream is 8 bytes: ' + IntToStr(Length(Z)));
  Check(Length(RawInflate(Z, 15, 16)) = 0, 'empty zlib round trip');
end;

procedure CheckValues;
const
  S1: AnsiString = '123456789';
  S2: AnsiString = 'Wikipedia';
begin
  Check(crc32(0, PByte(PAnsiChar(S1)), Length(S1)) = $CBF43926, 'crc32("123456789") = CBF43926');
  Check(crc32(0, nil, 0) = 0, 'crc32 of nothing');
  Check(adler32(1, PByte(PAnsiChar(S2)), Length(S2)) = $11E60398, 'adler32("Wikipedia") = 11E60398');
  Check(adler32(0, nil, 0) = 1, 'adler32 initial value');
  Check(StrPas(zlibVersion) <> '', 'zlibVersion answers');
  Check(zlibVersion^ = '1', 'zlibVersion major 1');
end;

{ inflate fed 1..N bytes at a time: Z_BUF_ERROR means "no progress possible",
  never data loss; output arrives as soon as the library can produce it }
procedure Piecewise;
var
  Data, Z, Out: TBytes;
  S: z_stream;
  Bound: LongWord;
  Piece, Pos, Code, Produced: Integer;
begin
  Data := Pattern(5000, 3);
  Z := RawDeflate(Data, 15, Bound);
  for Piece := 1 to 7 do begin
    S := Default(z_stream);
    Check(inflateInit(S) = Z_OK, 'inflateInit');
    SetLength(Out, Length(Data) + 64);
    S.next_out := Pointer(Out);
    S.avail_out := Length(Out);
    Pos := 0;
    Code := Z_OK;
    while (Pos < Length(Z)) and (Code <> Z_STREAM_END) do begin
      S.next_in := @Z[Pos];
      If Length(Z) - Pos < Piece then
        S.avail_in := Length(Z) - Pos
      else
        S.avail_in := Piece;
      Inc(Pos, S.avail_in);
      Code := inflate(S, Z_NO_FLUSH);
      Check((Code = Z_OK) or (Code = Z_STREAM_END) or (Code = Z_BUF_ERROR), Format('piece %d: inflate code %d', [Piece, Code]));
      Check(S.avail_in = 0, Format('piece %d: input consumed', [Piece]));
    end;
    Check(Code = Z_STREAM_END, Format('piece %d: reached the end', [Piece]));
    Produced := S.total_out;
    Check((Produced = Length(Data)) and CompareMem(@Out[0], @Data[0], Length(Data)), Format('piece %d: output intact', [Piece]));
    { one more call behind the end: the library keeps answering Z_STREAM_END }
    S.avail_in := 0;
    Check(inflate(S, Z_NO_FLUSH) = Z_STREAM_END, Format('piece %d: Z_STREAM_END repeats', [Piece]));
    inflateEnd(S);
  end;
end;

{ two independent gzip frames through one z_stream with inflateReset in
  between (the exchange feed pattern: every message is its own gzip member) }
procedure ResetBetweenFrames;
var
  A, B, ZA, ZB, Out: TBytes;
  S: z_stream;
  Bound: LongWord;
  Code: Integer;
begin
  A := Pattern(3000, 11);
  B := Pattern(700, 13);
  ZA := RawDeflate(A, 31, Bound);
  ZB := RawDeflate(B, 31, Bound);
  S := Default(z_stream);
  Check(inflateInit2(S, 31) = Z_OK, 'inflateInit2 gzip');
  SetLength(Out, 4000);
  S.next_in := Pointer(ZA); S.avail_in := Length(ZA);
  S.next_out := Pointer(Out); S.avail_out := Length(Out);
  Code := inflate(S, Z_FINISH);
  Check((Code = Z_STREAM_END) and (S.total_out = LongWord(Length(A))) and CompareMem(@Out[0], @A[0], Length(A)), 'first frame');
  Check(inflateReset(S) = Z_OK, 'inflateReset');
  Check((S.total_in = 0) and (S.total_out = 0), 'inflateReset clears the counters');
  S.next_in := Pointer(ZB); S.avail_in := Length(ZB);
  S.next_out := Pointer(Out); S.avail_out := Length(Out);
  Code := inflate(S, Z_FINISH);
  Check((Code = Z_STREAM_END) and (S.total_out = LongWord(Length(B))) and CompareMem(@Out[0], @B[0], Length(B)), 'second frame after reset');
  { inflateReset2 switches the framing }
  Check(inflateReset2(S, -15) = Z_OK, 'inflateReset2');
  ZA := RawDeflate(A, -15, Bound);
  S.next_in := Pointer(ZA); S.avail_in := Length(ZA);
  S.next_out := Pointer(Out); S.avail_out := Length(Out);
  Code := inflate(S, Z_FINISH);
  Check((Code = Z_STREAM_END) and (S.total_out = LongWord(Length(A))), 'raw frame after inflateReset2');
  inflateEnd(S);
end;

type
  TProgressCounter = class
    Count: Integer;
    procedure OnProgress(Sender: TObject);
  end;

procedure TProgressCounter.OnProgress(Sender: TObject);
begin
  Inc(Count);
  Check(Sender is TCustomZStream, 'progress sender is the stream');
end;

procedure Streams;
var
  Data, Back: TBytes;
  Dest, Shared: TMemoryStream;
  C: TZCompressionStream;
  D: TZDecompressionStream;
  Tag: Cardinal;
  Head: array[0..9] of Byte;
  Counter: TProgressCounter;
  Rate: Single;
  procedure Compress(Level: TZCompressionLevel; WindowBits: Integer);
  begin
    Dest.Clear;
    C := TZCompressionStream.Create(Dest, Level, WindowBits);
    try
      C.OnProgress := Counter.OnProgress;
      Check(C.Position = 0, 'compression stream starts at 0');
      C.WriteBuffer(Data[0], 1000);
      Check(C.Position = 1000, 'Position counts accepted bytes');
      Check(C.Size = 1000, 'Size counts accepted bytes');
      Check(C.Seek(0, soCurrent) = 1000, 'Seek(0, soCurrent)');
      Check(C.Seek(1000, soBeginning) = 1000, 'Seek(accepted, soBeginning)');
      try
        C.Seek(5, soBeginning);
        Check(False, 'Seek to another offset accepted');
      except
        on EZCompressionError do ;
      end;
      try
        C.Read(Tag, 1);
        Check(False, 'Read from the compression stream accepted');
      except
        on EZCompressionError do ;
      end;
      C.WriteBuffer(Data[1000], Length(Data) - 1000);
      Rate := C.CompressionRate;
      Check((Rate > 0) and (Rate < 100), 'compression rate in range: ' + FloatToStr(Rate));
    finally
      C.Free;    { finishes the stream }
    end;
  end;
begin
  Data := Pattern(300000, 5);
  Dest := TMemoryStream.Create;
  Counter := TProgressCounter.Create;
  try
    Compress(zcDefault, 15);
    Check(Counter.Count > 0, 'OnProgress fired for the compression stream');
    Check(Dest.Size > 0, 'compressed output written');
    Check((PByte(Dest.Memory)^ and $0F) = 8, 'stream output is zlib framed');
    Dest.Position := 0;
    D := TZDecompressionStream.Create(Dest);
    D.Position := 0;                                       { a no-op right after creation }
    Check(D.Position = 0, 'Position := 0 after creation is a no-op');
    Check(D.Size = Length(Data), 'Size is the whole inflated size');
    Check(D.Position = 0, 'Size does not move the position');
    SetLength(Back, Length(Data));
    D.ReadBuffer(Back[0], 1234);
    Check(D.Position = 1234, 'position after a partial read');
    Check(D.Seek(0, soBeginning) = 0, 'Seek(0, soBeginning) after a partial read');
    D.ReadBuffer(Back[0], Length(Back));
    Check(SameBytes(Back, Data), 'stream round trip');
    Check(D.Read(Tag, 4) = 0, 'reading past the end gives 0');
    Check(D.Size = Length(Data), 'Size after reading');
    try
      D.Seek(-Length(Data) + 10, soCurrent);
      Check(False, 'negative relative seek accepted');
    except
      on EZDecompressionError do ;
    end;
    { seek forward by skipping, then back by restarting }
    D.Seek(500, soBeginning);
    D.ReadBuffer(Head, 10);
    Check(CompareMem(@Head, @Data[500], 10), 'read after forward seek');
    D.Seek(100, soCurrent);
    D.ReadBuffer(Head, 10);
    Check(CompareMem(@Head, @Data[610], 10), 'read after relative seek');
    D.Seek(3, soBeginning);
    D.ReadBuffer(Head, 10);
    Check(CompareMem(@Head, @Data[3], 10), 'read after seeking back');
    Check(D.Seek(0, soEnd) = Length(Data), 'Seek(0, soEnd)');
    { a forward seek is a read thrown away: past the end it is a read error,
      as in Delphi (its Seek uses ReadBuffer); the position stays where the
      data ended }
    try
      D.Seek(10, soCurrent);
      Check(False, 'seek past the end accepted');
    except
      on EReadError do ;
    end;
    Check(D.Position = Length(Data), 'position after the failed seek');
    D.Seek(0, soBeginning);
    try
      D.Seek(Length(Data) + 1, soBeginning);
      Check(False, 'absolute seek past the end accepted');
    except
      on EReadError do ;
    end;
    Check(D.Position = Length(Data), 'position after the failed absolute seek');
    try
      D.Write(Tag, 1);
      Check(False, 'Write to the decompression stream accepted');
    except
      on EZDecompressionError do ;
    end;
    D.Free;
    Check(Dest.Position = Dest.Size, 'source left behind the compressed data');
    { gzip and raw through the streams }
    Compress(zcMax, 31);
    Check((PByte(Dest.Memory)^ = $1F) and (PByte(Dest.Memory)[1] = $8B), 'gzip framed stream');
    Dest.Position := 0;
    D := TZDecompressionStream.Create(Dest, 31);
    try
      D.ReadBuffer(Back[0], Length(Back));
      Check(SameBytes(Back, Data), 'gzip stream round trip');
    finally
      D.Free;
    end;
    Compress(zcFastest, -15);
    Dest.Position := 0;
    D := TZDecompressionStream.Create(Dest, -15);
    try
      D.ReadBuffer(Back[0], Length(Back));
      Check(SameBytes(Back, Data), 'raw stream round trip');
    finally
      D.Free;
    end;
    { a shared source: compressed data behind other bytes, and the source
      moved by someone else between reads }
    Shared := TMemoryStream.Create;
    try
      Tag := $DEADBEEF;
      Shared.WriteBuffer(Tag, 4);
      Compress(zcDefault, 15);
      Shared.CopyFrom(Dest, 0);
      Shared.WriteBuffer(Tag, 4);                          { trailing bytes: not part of the stream }
      Shared.Position := 4;
      D := TZDecompressionStream.Create(Shared, 15, False);
      try
        Counter.Count := 0;
        D.OnProgress := Counter.OnProgress;
        D.ReadBuffer(Back[0], 100);
        Shared.Position := 0;                              { someone moves the source }
        D.ReadBuffer(Back[100], Length(Back) - 100);
        Check(SameBytes(Back, Data), 'shared source round trip');
        Check(Counter.Count > 0, 'OnProgress fired for the decompression stream');
      finally
        D.Free;
      end;
      Check(Shared.Position = Shared.Size - 4, 'source positioned right behind the deflate stream: ' + IntToStr(Shared.Position));
      Shared.ReadBuffer(Tag, 4);
      Check(Tag = $DEADBEEF, 'the trailing bytes are still to be read');
    finally
      Shared.Free;
    end;
    { OwnsStream frees the source }
    Shared := TMemoryStream.Create;
    Compress(zcDefault, 15);
    Shared.CopyFrom(Dest, 0);
    Shared.Position := 0;
    D := TZDecompressionStream.Create(Shared, 15, True);
    D.ReadBuffer(Back[0], Length(Back));
    Check(SameBytes(Back, Data), 'owned source round trip');
    D.Free;                                                { frees Shared too; a leak report would show otherwise }
    { the old names }
    Dest.Clear;
    with TCompressionStream.Create(clDefault, Dest) do
      try
        WriteBuffer(Data[0], 1000);
      finally
        Free;
      end;
    Dest.Position := 0;
    with TDecompressionStream.Create(Dest) do
      try
        ReadBuffer(Back[0], 1000);
        Check(CompareMem(@Back[0], @Data[0], 1000), 'TCompressionStream/TDecompressionStream');
      finally
        Free;
      end;
  finally
    Counter.Free;
    Dest.Free;
  end;
end;

procedure Helpers;
var
  Data, Z, Back: TBytes;
  P, Q: Pointer;
  N, M: Integer;
  S: string;
  Src, Dst: TMemoryStream;
  DestLen: LongWord;
begin
  Data := Pattern(70000, 9);
  { pointer forms }
  ZCompress(Pointer(Data), Length(Data), P, N);
  try
    Check((N > 0) and (N < Length(Data)), 'ZCompress produced a smaller buffer');
    Check((PByte(P)^ and $0F) = 8, 'ZCompress output is zlib framed');
    ZDecompress(P, N, Q, M);
    try
      Check((M = Length(Data)) and CompareMem(Q, @Data[0], M), 'ZDecompress round trip');
    finally
      FreeMem(Q);
    end;
    ZDecompress(P, N, Q, M, 100);                        { small estimate: growth path }
    try
      Check((M = Length(Data)) and CompareMem(Q, @Data[0], M), 'ZDecompress with a small estimate');
    finally
      FreeMem(Q);
    end;
    { truncated input: buffer error, nothing leaked }
    Q := Pointer(1);
    try
      ZDecompress(P, N - 10, Q, M);
      Check(False, 'truncated input accepted');
    except
      on E: EZDecompressionError do
        Check(E.Message = 'buffer error', 'truncated input: ' + E.Message);
    end;
    Check(Q = nil, 'outBuffer nil after the exception');
  finally
    FreeMem(P);
  end;
  { bytes behind the stream: buffer error }
  ZCompress(Data, Z);
  SetLength(Z, Length(Z) + 3);
  try
    ZDecompress(Z, Back);
    Check(False, 'trailing bytes accepted');
  except
    on E: EZDecompressionError do
      Check(E.Message = 'buffer error', 'trailing bytes: ' + E.Message);
  end;
  { TBytes forms and levels }
  ZCompress(Data, Z, zcMax);
  ZDecompress(Z, Back);
  Check(SameBytes(Back, Data), 'TBytes round trip, zcMax');
  ZCompress(Data, Z, zcNone);
  Check(Length(Z) > Length(Data), 'zcNone stores');
  ZDecompress(Z, Back);
  Check(SameBytes(Back, Data), 'TBytes round trip, zcNone');
  ZCompress(Pointer(Data), Length(Data), P, N, clFastest);
  FreeMem(P);
  Check(N > 0, 'TCompressionLevel overload');
  { empty }
  ZCompress(nil, 0, P, N);
  Check(N = 8, 'empty ZCompress: ' + IntToStr(N));
  ZDecompress(P, N, Q, M);
  Check(M = 0, 'empty ZDecompress');
  FreeMem(Q);
  FreeMem(P);
  { streams }
  Src := TMemoryStream.Create;
  Dst := TMemoryStream.Create;
  try
    Src.WriteBuffer(Data[0], Length(Data));
    Src.Position := 100;                                  { from the current position }
    ZCompressStream(Src, Dst);
    Check(Src.Position = Src.Size, 'ZCompressStream read to the end');
    Dst.Position := 0;
    Src.Clear;
    ZDecompressStream(Dst, Src);
    Check((Src.Size = Length(Data) - 100) and CompareMem(Src.Memory, @Data[100], Src.Size), 'ZCompressStream/ZDecompressStream round trip');
    Dst.Clear;
    try
      ZDecompressStream(Dst, Src);
      Check(False, 'ZDecompressStream accepted empty input');
    except
      on E: EZDecompressionError do
        Check(E.Message = 'buffer error', 'empty ZDecompressStream: ' + E.Message);
    end;
  finally
    Dst.Free;
    Src.Free;
  end;
  { strings: UTF-16LE bytes, no BOM }
  S := #$041F#$0440#$0438#$0432#$0435#$0442;              { six Cyrillic letters }
  Z := ZCompressStr(S);
  ZDecompress(Z, Back);
  Check(Length(Back) = 12, 'ZCompressStr compresses the UTF-16LE bytes: ' + IntToStr(Length(Back)));
  Check((Back[0] = $1F) and (Back[1] = $04) and (Back[10] = $42) and (Back[11] = $04), 'UTF-16LE byte order, no BOM');
  Check(ZDecompressStr(Z) = S, 'ZDecompressStr');
  Check(ZDecompressStr(ZCompressStr('')) = '', 'empty string round trip');
  { compress/uncompress of zlib.h }
  DestLen := compressBound(Length(Data));
  SetLength(Z, DestLen);
  Check(compress(Pointer(Z), DestLen, Pointer(Data), Length(Data)) = Z_OK, 'compress');
  Check(DestLen < LongWord(Length(Data)), 'compress shrank the data');
  SetLength(Back, Length(Data));
  N := Length(Back);
  Check(uncompress(Pointer(Back), LongWord(N), Pointer(Z), DestLen) = Z_OK, 'uncompress');
  Check((N = Length(Data)) and SameBytes(Back, Data), 'compress/uncompress round trip');
  N := 100;
  Check(uncompress(Pointer(Back), LongWord(N), Pointer(Z), DestLen) = Z_BUF_ERROR, 'uncompress into a short buffer');
  Check(uncompress(Pointer(Back), LongWord(N), Pointer(Z), 20) = Z_DATA_ERROR, 'uncompress of truncated input');
  DestLen := compressBound(Length(Data));
  Check(compress2(Pointer(Z), DestLen, Pointer(Data), Length(Data), Z_BEST_SPEED) = Z_OK, 'compress2');
end;

{ A preset dictionary is a valid RFC 1950 stream.  The raw API lets the
  caller supply it; high-level APIs have no dictionary argument and must
  report it instead of retrying inflate forever without progress. }
procedure DictionaryInput;
const
  Dictionary: AnsiString = 'hello shared dictionary';
  Data: AnsiString = 'hello shared dictionary hello shared dictionary';
var
  S: z_stream;
  Encoded, Decoded: array[0..255] of Byte;
  N, OutSize: Integer;
  P: Pointer;
  Src, Dst: TMemoryStream;
  Reader: TZDecompressionStream;
begin
  S := Default(z_stream);
  Check(deflateInit(S, Z_DEFAULT_COMPRESSION) = Z_OK, 'dictionary deflateInit');
  try
    Check(deflateSetDictionary(S, PByte(PAnsiChar(Dictionary)), Length(Dictionary)) = Z_OK, 'set compression dictionary');
    S.next_in := PByte(PAnsiChar(Data));
    S.avail_in := Length(Data);
    S.next_out := @Encoded[0];
    S.avail_out := SizeOf(Encoded);
    Check(deflate(S, Z_FINISH) = Z_STREAM_END, 'dictionary frame completed');
    N := S.total_out;
  finally
    deflateEnd(S);
  end;
  S := Default(z_stream);
  Check(inflateInit(S) = Z_OK, 'dictionary inflateInit');
  try
    S.next_in := @Encoded[0];
    S.avail_in := N;
    S.next_out := @Decoded[0];
    S.avail_out := SizeOf(Decoded);
    Check(inflate(S, Z_NO_FLUSH) = Z_NEED_DICT, 'raw inflate requests the dictionary');
    Check(inflateSetDictionary(S, PByte(PAnsiChar(Dictionary)), Length(Dictionary)) = Z_OK, 'supply requested dictionary');
    Check(inflate(S, Z_FINISH) = Z_STREAM_END, 'raw dictionary stream completes');
    Check((S.total_out = Length(Data)) and CompareMem(@Decoded[0], PAnsiChar(Data), Length(Data)), 'dictionary data intact');
  finally
    inflateEnd(S);
  end;
  P := nil;
  try
    ZDecompress(@Encoded[0], N, P, OutSize);
    FreeMem(P);
    Check(False, 'ZDecompress accepted a missing dictionary');
  except
    on E: EZDecompressionError do
      Check((E.Message = 'need dictionary') and (P = nil), 'ZDecompress missing dictionary cleanup and error');
  end;
  Src := TMemoryStream.Create;
  Dst := TMemoryStream.Create;
  try
    Src.WriteBuffer(Encoded[0], N);
    Src.Position := 0;
    try
      ZDecompressStream(Src, Dst);
      Check(False, 'ZDecompressStream accepted a missing dictionary');
    except
      on E: EZDecompressionError do
        Check(E.Message = 'need dictionary', 'ZDecompressStream missing dictionary error');
    end;
    Src.Position := 0;
    Reader := TZDecompressionStream.Create(Src);
    try
      try
        Reader.Read(Decoded[0], SizeOf(Decoded));
        Check(False, 'TZDecompressionStream accepted a missing dictionary');
      except
        on E: EZDecompressionError do
          Check(E.Message = 'need dictionary', 'TZDecompressionStream missing dictionary error');
      end;
    finally
      Reader.Free;
    end;
  finally
    Dst.Free;
    Src.Free;
  end;
end;

{ Raw deflate can consume its final byte while a long match still has output
  pending.  A short Read must drain that state before treating source EOF as
  end of the decompressed stream.  Framed streams are negative controls. }
procedure SmallReadsAtInputEnd;
const
  Bits: array[0..2] of Integer = (-15, 15, 31);
  Pieces: array[0..2] of Integer = (1, 7, 8192);
var
  Data, Back, Encoded: TBytes;
  Bound: LongWord;
  Src: TMemoryStream;
  Reader: TZDecompressionStream;
  WindowBits, Piece, Total, Got: Integer;
begin
  SetLength(Data, 65535);
  FillChar(Data[0], Length(Data), Ord('a'));
  SetLength(Back, Length(Data) + 8192);
  for WindowBits in Bits do begin
    Encoded := RawDeflate(Data, WindowBits, Bound);
    Src := TMemoryStream.Create;
    try
      Src.WriteBuffer(Encoded[0], Length(Encoded));
      for Piece in Pieces do begin
        Src.Position := 0;
        Reader := TZDecompressionStream.Create(Src, WindowBits);
        try
          Total := 0;
          repeat
            Got := Reader.Read(Back[Total], Piece);
            Inc(Total, Got);
          until (Got = 0) or (Total > Length(Data));
          Check((Total = Length(Data)) and CompareMem(@Data[0], @Back[0], Length(Data)),
            Format('input EOF tail: window %d piece %d got %d', [WindowBits, Piece, Total]));
          Check(Reader.Position = Length(Data), 'position includes pending inflate output');
        finally
          Reader.Free;
        end;
      end;
    finally
      Src.Free;
    end;
  end;
end;

procedure EmptyUncompress;
const
  EmptyZ: array[0..7] of Byte = ($78, $9C, $03, $00, $00, $00, $00, $01);
var
  Size: LongWord;
begin
  Size := 0;
  Check(uncompress(nil, Size, @EmptyZ[0], Length(EmptyZ)) = Z_OK, 'uncompress empty payload into nil buffer');
  Check(Size = 0, 'empty uncompress output size');
end;

{ An exception raised inside a zlib call reaches the caller's except through zlib's frames:
  one the stream's allocator raises (the unit's own ZAlloc raises EOutOfMemory when memory
  runs out, from inside deflateInit/inflateInit), and a fault on input that is not there.
  The caller keeps four values in registers the callee has to save; after the except they
  are what they were.  On Win64 the unwinder finds its way through the zlib objects only by
  their unwind tables (packages/vcl-compat/native/zlib/README.md). }
type
  EAllocRefused = class(Exception);

function RefusingAlloc(opaque: Pointer; items, size: Cardinal): Pointer; cdecl;
begin
  raise EAllocRefused.Create('the allocator refuses');
end;

procedure KeepingFree(opaque, block: Pointer); cdecl;
begin
end;

var
  GuardedInput: PByte;  { a readable page with an inaccessible one behind it }

function ThroughZlib(Which: Integer; const Deflated: TBytes): string; noinline;
var
  A, B, C, D: Int64;
  S: z_stream;
  Output: array[0..4095] of Byte;
  I: Integer;
begin
  A := $1111111111111111;
  B := $2222222222222222;
  C := $3333333333333333;
  D := $4444444444444444;
  Result := 'nothing raised';
  for I := 1 to 2 do begin
    S := Default(z_stream);
    try
      case Which of
        0: begin
             S.zalloc := @RefusingAlloc;
             S.zfree := @KeepingFree;
             deflateInit2(S, Z_DEFAULT_COMPRESSION, Z_DEFLATED, 15, 8, Z_DEFAULT_STRATEGY);
           end;
        1: begin
             S.zalloc := @RefusingAlloc;
             S.zfree := @KeepingFree;
             inflateInit2(S, 15);
           end;
      else
        { the first half of a stream at the end of the readable page, and a length that
          claims the page behind it: inflate reads on into the page that is not there }
        Move(Deflated[0], (GuardedInput + 4096 - Length(Deflated) div 2)^, Length(Deflated) div 2);
        Check(inflateInit2(S, 15) = Z_OK, 'inflateInit2 for the input that runs out');
        try
          S.next_in := GuardedInput + 4096 - Length(Deflated) div 2;
          S.avail_in := Length(Deflated);
          repeat
            S.next_out := @Output[0];
            S.avail_out := SizeOf(Output);
          until inflate(S, Z_NO_FLUSH) <> Z_OK;
        finally
          inflateEnd(S);
        end;
      end;
    except
      on E: EAllocRefused do
        Result := 'raised';
      on E: EAccessViolation do
        Result := 'raised';
    end;
    A := A + D - $4444444444444444;
    B := B xor (C - $3333333333333333);
  end;
  If (A <> $1111111111111111) or (B <> $2222222222222222) or (C <> $3333333333333333) or
     (D <> $4444444444444444) then
    Result := Result + ', the caller''s registers were not restored';
end;

procedure ExceptionsThroughZlib;
var
  Plain, Deflated: TBytes;
  Size: LongWord;
  I: Integer;
{$ifdef MSWINDOWS}
  Old: DWORD;
{$endif}
begin
{$ifdef MSWINDOWS}
  GuardedInput := VirtualAlloc(nil, 2 * 4096, MEM_RESERVE or MEM_COMMIT, PAGE_READWRITE);
  Check((GuardedInput <> nil) and VirtualProtect(GuardedInput + 4096, 4096, PAGE_NOACCESS, @Old),
    'guard page for the input');
{$else}
  GuardedInput := Fpmmap(nil, 2 * 4096, PROT_READ or PROT_WRITE, MAP_PRIVATE or MAP_ANONYMOUS, -1, 0);
  Check((GuardedInput <> PByte(-1)) and (Fpmprotect(GuardedInput + 4096, 4096, PROT_NONE) = 0),
    'guard page for the input');
{$endif}
  { a stream that inflates to more than one output buffer, a few hundred bytes packed }
  SetLength(Plain, 60000);
  for I := 0 to High(Plain) do
    Plain[I] := Byte((I div 3) mod 200);
  SetLength(Deflated, 8192);
  Size := Length(Deflated);
  Check(compress(@Deflated[0], Size, @Plain[0], Length(Plain)) = Z_OK, 'compress for the input that runs out');
  SetLength(Deflated, Size);
  Check((Size > 64) and (Size < 8000), 'the packed stream fits the page twice: ' + IntToStr(Size));
  Check(ThroughZlib(0, Deflated) = 'raised', 'an exception of the allocator inside deflateInit2: ' +
    ThroughZlib(0, Deflated));
  Check(ThroughZlib(1, Deflated) = 'raised', 'an exception of the allocator inside inflateInit2: ' +
    ThroughZlib(1, Deflated));
  Check(ThroughZlib(2, Deflated) = 'raised', 'a fault on input that is not there, inside inflate: ' +
    ThroughZlib(2, Deflated));
end;

begin
  Failures := 0;
  Check(SizeOf(z_stream) = {$ifdef WIN64}88{$else}112{$endif}, 'z_stream has the C layout: ' + IntToStr(SizeOf(z_stream)));
  Framing;
  CheckValues;
  Piecewise;
  ResetBetweenFrames;
  Streams;
  Helpers;
  DictionaryInput;
  SmallReadsAtInputEnd;
  EmptyUncompress;
  ExceptionsThroughZlib;
  If Failures <> 0 then
    Halt(1);
  WriteLn('ZLIB_PASS');
end.
