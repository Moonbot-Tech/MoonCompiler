unit BenchCompression;
interface
uses mormot.core.base, mormot.core.text, System.SysUtils, System.ZLib, System.Math;
function ZInflate(Data: PByte; Len: Integer; WindowBits: Integer): RawUtf8;
function GZipCompress(const Data: TBytes): TBytes;
implementation
function ZInflate(Data: PByte; Len: Integer; WindowBits: Integer): RawUtf8;
const
  // Shared zip-bomb guard for small WebSocket frames and the much larger
  // Binance exchangeInfo response. The measured response was about 16.2 MB;
  // 64 MB leaves growth headroom without allowing an unbounded expansion.
  MAX_OUT = 64 * 1024 * 1024;
var
  zstream:       TZStreamRec;
  outSize, zret: Integer;
  outBuffer:     TBytes;
begin
  Result := '';
  If (Data = nil) or (Len <= 0) then exit;
  FillChar(zstream, SizeOf(TZStreamRec), 0);
  outSize := (Len * 2 + 255) and not 255;
  SetLength(outBuffer, outSize);
  If InflateInit2(zstream, WindowBits) <> Z_OK then exit;
  try
    zstream.next_in := Data;
    zstream.avail_in := Len;
    repeat
      zstream.next_out := PByte(@outBuffer[0]) + zstream.total_out;
      zstream.avail_out := outSize - Integer(zstream.total_out);
      zret := inflate(zstream, Z_NO_FLUSH);
      If zret = Z_STREAM_END then Break;
      If (zret <> Z_OK) and (zret <> Z_BUF_ERROR) then Exit('');
      If zstream.avail_out = 0 then begin
        If outSize >= MAX_OUT then Exit('');
        outSize := outSize * 2;
        SetLength(outBuffer, outSize);
      end else If zstream.avail_in = 0 then
        Exit('');
    until False;
  finally
    inflateEnd(zstream);
  end;
  FastSetString(Result, @outBuffer[0], zstream.total_out);
end;

function GZipCompress(const Data: TBytes): TBytes;
const
  GZIP_WBITS = 15 + 16; // 31 -> gzip wrapper
  CHUNK = 16384;
var
  Z:      TZStreamRec;
  Res:    integer;
  DstPos: integer;
begin
  if Length(Data) = 0 then exit(nil);

  FillChar(Z, SizeOf(Z), 0);
  Z.next_in := @Data[0];
  Z.avail_in := Length(Data);

  Res := deflateInit2_(Z, Z_DEFAULT_COMPRESSION, Z_DEFLATED, GZIP_WBITS, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION,
    SizeOf(Z));
  if Res <> Z_OK then raise Exception.CreateFmt('deflateInit2_ failed (%d)', [Res]);

  try
    SetLength(Result, 0);
    DstPos := 0;
    repeat
      SetLength(Result, Length(Result) + CHUNK);
      Z.next_out := @Result[DstPos];
      Z.avail_out := CHUNK;
      Res := deflate(Z, IfThen(Z.avail_in = 0, Z_FINISH, Z_NO_FLUSH));
      Inc(DstPos, CHUNK - Z.avail_out);
    until Res = Z_STREAM_END;

    SetLength(Result, DstPos);
  finally
    deflateEnd(Z);
  end;
end;


end.
