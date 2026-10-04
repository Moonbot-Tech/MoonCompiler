{
    This file is part of the Free Pascal run time library.
    Copyright (c) 2026 by the MoonCompiler contributors

    zlib bindings, streams and helpers with the Delphi System.ZLib surface.

    Provenance: written for MoonCompiler from the behavioural contract in the
    planning document "DELPHI_SURFACE_ADDITIONS_20260920" (section 2.1), from
    zlib.h of zlib 1.3.1 and RFC 1950/1951/1952.  No Embarcadero source,
    interface text or documentation excerpt was consulted or copied.
    Author: MoonCompiler team, 2026-09-21.

    The compressor is the native zlib 1.3.1 of the objects shipped in
    ../native/zlib/<target> (symbols prefixed moon_zlib_ so that another
    zlib in the same program is not disturbed; on Win64 without a C runtime,
    on Linux copying through memcpy/memset of the C library every program
    links), the same code on Win64 and Linux; MoonORMot's mormot.lib.z
    compresses through this unit too (MOONCOMPILER_SYSTEM_ZLIB).  Every
    stream allocates through the program's memory manager.

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}
unit System.ZLib;

{$mode objfpc}
{$H+}
{$PACKRECORDS C}
{$if not (defined(WIN64) or defined(LINUX))}
  {$fatal System.ZLib supports Win64 and Linux x86-64}
{$endif}

interface

uses
  SysUtils, Classes, RtlConsts;

type
  { uLong of the C library: 32 bits on Win64 (LLP64), 64 bits on Linux (LP64);
    z_stream goes to the library as it is, so these fields must match }
  TZLong = {$ifdef WIN64}LongWord{$else}PtrUInt{$endif};

  TZAlloc = function(opaque: Pointer; items, size: Cardinal): Pointer; cdecl;
  TZFree = procedure(opaque, block: Pointer); cdecl;

  { z_stream of zlib.h, C layout, zlib's field names }
  z_stream = record
    next_in: PByte;
    avail_in: Cardinal;
    total_in: TZLong;
    next_out: PByte;
    avail_out: Cardinal;
    total_out: TZLong;
    msg: MarshaledAString;
    state: Pointer;
    zalloc: TZAlloc;
    zfree: TZFree;
    opaque: Pointer;
    data_type: Integer;
    adler: TZLong;
    reserved: TZLong;
  end;
  TZStreamRec = z_stream;
  PZStreamRec = ^z_stream;

  TZCompressionLevel = (zcNone, zcFastest, zcDefault, zcMax);
  TCompressionLevel = (clNone, clFastest, clDefault, clMax);

  EZLibError = class(Exception);
  EZCompressionError = class(EZLibError);
  EZDecompressionError = class(EZLibError);

const
  ZLIB_VERSION = '1.3.1';

  Z_NO_FLUSH      = 0;
  Z_PARTIAL_FLUSH = 1;
  Z_SYNC_FLUSH    = 2;
  Z_FULL_FLUSH    = 3;
  Z_FINISH        = 4;
  Z_BLOCK         = 5;
  Z_TREES         = 6;

  Z_OK            = 0;
  Z_STREAM_END    = 1;
  Z_NEED_DICT     = 2;
  Z_ERRNO         = -1;
  Z_STREAM_ERROR  = -2;
  Z_DATA_ERROR    = -3;
  Z_MEM_ERROR     = -4;
  Z_BUF_ERROR     = -5;
  Z_VERSION_ERROR = -6;

  Z_NO_COMPRESSION      = 0;
  Z_BEST_SPEED          = 1;
  Z_BEST_COMPRESSION    = 9;
  Z_DEFAULT_COMPRESSION = -1;

  Z_FILTERED         = 1;
  Z_HUFFMAN_ONLY     = 2;
  Z_RLE              = 3;
  Z_FIXED            = 4;
  Z_DEFAULT_STRATEGY = 0;

  Z_BINARY  = 0;
  Z_TEXT    = 1;
  Z_ASCII   = Z_TEXT;
  Z_UNKNOWN = 2;

  Z_DEFLATED = 8;

  Z_NULL = 0;

{ The zlib.h functions with Delphi types.  The *Init* forms fill a nil
  zalloc/zfree with the program's memory manager before the library sees the
  record, so the library's own default (malloc; not linked on Win64) is never
  called. }
function deflateInit(var strm: z_stream; level: Integer): Integer;
function deflateInit2(var strm: z_stream; level, method, windowBits, memLevel, strategy: Integer): Integer;
function deflateInit_(var strm: z_stream; level: Integer; version: MarshaledAString; stream_size: Integer): Integer;
function deflateInit2_(var strm: z_stream; level, method, windowBits, memLevel, strategy: Integer; version: MarshaledAString; stream_size: Integer): Integer;
function deflate(var strm: z_stream; flush: Integer): Integer;
function deflateEnd(var strm: z_stream): Integer;
function deflateReset(var strm: z_stream): Integer;
function deflateParams(var strm: z_stream; level, strategy: Integer): Integer;
function deflateBound(var strm: z_stream; sourceLen: Cardinal): LongWord;
function deflateSetDictionary(var strm: z_stream; dictionary: PByte; dictLength: Cardinal): Integer;

function inflateInit(var strm: z_stream): Integer;
function inflateInit2(var strm: z_stream; windowBits: Integer): Integer;
function inflateInit_(var strm: z_stream; version: MarshaledAString; stream_size: Integer): Integer;
function inflateInit2_(var strm: z_stream; windowBits: Integer; version: MarshaledAString; stream_size: Integer): Integer;
function inflate(var strm: z_stream; flush: Integer): Integer;
function inflateEnd(var strm: z_stream): Integer;
function inflateReset(var strm: z_stream): Integer;
function inflateReset2(var strm: z_stream; windowBits: Integer): Integer;
function inflateSync(var strm: z_stream): Integer;
function inflateSetDictionary(var strm: z_stream; dictionary: PByte; dictLength: Cardinal): Integer;

function crc32(crc: UInt32; buf: PByte; len: Cardinal): UInt32;
function adler32(adler: LongWord; buf: PByte; len: Cardinal): LongWord;

function compress(dest: PByte; var destLen: LongWord; source: PByte; sourceLen: LongWord): Integer;
function compress2(dest: PByte; var destLen: LongWord; source: PByte; sourceLen: LongWord; level: Integer): Integer;
function compressBound(sourceLen: LongWord): LongWord;
function uncompress(dest: PByte; var destLen: LongWord; source: PByte; sourceLen: LongWord): Integer;

function zlibVersion: MarshaledAString;

type
  { base of the two streams: the progress event, Sender is the stream }
  TCustomZStream = class(TStream)
  private
    FStream: TStream;
    FStreamPos: Int64;
    FOnProgress: TNotifyEvent;
    FZStream: z_stream;
    FBuffer: array[0..65535] of Byte;
  protected
    procedure DoProgress; virtual;
    property OnProgress: TNotifyEvent read FOnProgress write FOnProgress;
  public
    constructor Create(stream: TStream);
  end;

  { Write compresses (Z_NO_FLUSH); finished output collects in the 64 KB
    buffer and goes to dest when the buffer is full, at the position the
    stream keeps for dest (dest.Position at creation; dest may be moved by
    others between calls).  Read is an error.  Seek accepts only the current
    position: (Offset, soBeginning) with Offset = bytes accepted, or
    (0, soCurrent)/(0, soEnd).  Size and Position are the bytes accepted.
    Destroy finishes the deflate stream and writes the rest. }
  TZCompressionStream = class(TCustomZStream)
  private
    function GetCompressionRate: Single;
    procedure FlushOutput;
  protected
    function GetSize: Int64; override;
  public
    constructor Create(dest: TStream); overload;
    constructor Create(dest: TStream; compressionLevel: TZCompressionLevel; windowBits: Integer); overload;
    constructor Create(compressionLevel: TCompressionLevel; dest: TStream); overload;
    destructor Destroy; override;
    function Read(var buffer; count: Longint): Longint; override;
    function Write(const buffer; count: Longint): Longint; override;
    function Seek(const offset: Int64; origin: TSeekOrigin): Int64; override;
    property CompressionRate: Single read GetCompressionRate;
    property OnProgress;
  end;

  { Read inflates on demand, pulling source in 64 KB pieces from the position
    the stream keeps for it (set before every read: source may be moved by
    others between calls).  Z_BUF_ERROR is not an error, the bytes obtained are
    returned; at Z_STREAM_END input the library did not consume counts as not
    read (the kept position moves back by avail_in).  Write is an error.
    Seek: back to a smaller offset restarts (inflateReset, source back to the
    start) and skips forward by reading; forward offsets skip by reading;
    (0, soEnd) reads to the end.  Size is the whole inflated size, found
    once by reading to the end and restarting, then cached. }
  TZDecompressionStream = class(TCustomZStream)
  private
    FOwnsStream: Boolean;
    FStreamStart: Int64;
    FWindowBits: Integer;
    FPosition: Int64;
    FSize: Int64;
    FSizeKnown: Boolean;
    FEnded: Boolean;
    procedure Restart;
    procedure Skip(count: Int64);
  protected
    function GetSize: Int64; override;
  public
    constructor Create(source: TStream); overload;
    constructor Create(source: TStream; windowBits: Integer); overload;
    constructor Create(source: TStream; windowBits: Integer; ownsStream: Boolean); overload;
    destructor Destroy; override;
    function Read(var buffer; count: Longint): Longint; override;
    function Write(const buffer; count: Longint): Longint; override;
    function Seek(const offset: Int64; origin: TSeekOrigin): Int64; override;
    property OnProgress;
  end;

  TCompressionStream = TZCompressionStream;
  TDecompressionStream = TZDecompressionStream;
  TCustomZLibStream = TCustomZStream;

{ Whole-buffer helpers, zlib format (windowBits 15).  outBuffer is GetMem'd
  here and FreeMem'd by the caller; on an exception it is freed and nil. }
procedure ZCompress(const inBuffer: Pointer; inSize: Integer; out outBuffer: Pointer; out outSize: Integer; level: TZCompressionLevel = zcDefault); overload;
procedure ZCompress(const inBuffer: Pointer; inSize: Integer; out outBuffer: Pointer; out outSize: Integer; level: TCompressionLevel); overload;
procedure ZCompress(const inBuffer: TBytes; out outBuffer: TBytes; level: TZCompressionLevel = zcDefault); overload;
procedure ZDecompress(const inBuffer: Pointer; inSize: Integer; out outBuffer: Pointer; out outSize: Integer; outEstimate: Integer = 0); overload;
procedure ZDecompress(const inBuffer: TBytes; out outBuffer: TBytes; outEstimate: Integer = 0); overload;
{ From inStream's current position to its end, 32 KB pieces }
procedure ZCompressStream(inStream, outStream: TStream; level: TZCompressionLevel = zcDefault);
procedure ZDecompressStream(inStream, outStream: TStream);
{ The UTF-16LE bytes of the string, no BOM; back the same way }
function ZCompressStr(const s: string; level: TZCompressionLevel = zcDefault): TBytes;
function ZDecompressStr(const s: TBytes): string;

implementation

{ ---------------------------------------------------------------------
  the library
  ---------------------------------------------------------------------}

{$macro on}
{$L moonzlib_adler32.o}
{$L moonzlib_crc32.o}
{$L moonzlib_deflate.o}
{$L moonzlib_inffast.o}
{$L moonzlib_inflate.o}
{$L moonzlib_inftrees.o}
{$L moonzlib_trees.o}
{$L moonzlib_zutil.o}
const
  ZP = 'moon_zlib_';
  {$define ZEXT := cdecl; external name}

function z_deflateInit_(var strm: z_stream; level: Integer; version: MarshaledAString; stream_size: Integer): Integer; ZEXT ZP + 'deflateInit_';
function z_deflateInit2_(var strm: z_stream; level, method, windowBits, memLevel, strategy: Integer; version: MarshaledAString; stream_size: Integer): Integer; ZEXT ZP + 'deflateInit2_';
function z_deflate(var strm: z_stream; flush: Integer): Integer; ZEXT ZP + 'deflate';
function z_deflateEnd(var strm: z_stream): Integer; ZEXT ZP + 'deflateEnd';
function z_deflateReset(var strm: z_stream): Integer; ZEXT ZP + 'deflateReset';
function z_deflateParams(var strm: z_stream; level, strategy: Integer): Integer; ZEXT ZP + 'deflateParams';
function z_deflateBound(var strm: z_stream; sourceLen: TZLong): TZLong; ZEXT ZP + 'deflateBound';
function z_deflateSetDictionary(var strm: z_stream; dictionary: PByte; dictLength: Cardinal): Integer; ZEXT ZP + 'deflateSetDictionary';
function z_inflateInit_(var strm: z_stream; version: MarshaledAString; stream_size: Integer): Integer; ZEXT ZP + 'inflateInit_';
function z_inflateInit2_(var strm: z_stream; windowBits: Integer; version: MarshaledAString; stream_size: Integer): Integer; ZEXT ZP + 'inflateInit2_';
function z_inflate(var strm: z_stream; flush: Integer): Integer; ZEXT ZP + 'inflate';
function z_inflateEnd(var strm: z_stream): Integer; ZEXT ZP + 'inflateEnd';
function z_inflateReset(var strm: z_stream): Integer; ZEXT ZP + 'inflateReset';
function z_inflateReset2(var strm: z_stream; windowBits: Integer): Integer; ZEXT ZP + 'inflateReset2';
function z_inflateSync(var strm: z_stream): Integer; ZEXT ZP + 'inflateSync';
function z_inflateSetDictionary(var strm: z_stream; dictionary: PByte; dictLength: Cardinal): Integer; ZEXT ZP + 'inflateSetDictionary';
function z_crc32(crc: TZLong; buf: PByte; len: Cardinal): TZLong; ZEXT ZP + 'crc32';
function z_adler32(adler: TZLong; buf: PByte; len: Cardinal): TZLong; ZEXT ZP + 'adler32';
function z_zlibVersion: MarshaledAString; ZEXT ZP + 'zlibVersion';

{ ---------------------------------------------------------------------
  allocator and errors
  ---------------------------------------------------------------------}

function ZAlloc(opaque: Pointer; items, size: Cardinal): Pointer; cdecl;
begin
  Result := GetMem(NativeUInt(items) * size);
end;

procedure ZFree(opaque, block: Pointer); cdecl;
begin
  FreeMem(block);
end;

procedure UseProgramAllocator(var strm: z_stream); inline;
begin
  if not Assigned(strm.zalloc) then
    strm.zalloc := @ZAlloc;
  if not Assigned(strm.zfree) then
    strm.zfree := @ZFree;
end;

function ZErrorText(code: Integer): string;
begin
  case code of
    Z_STREAM_END:    Result := 'stream end';
    Z_NEED_DICT:     Result := 'need dictionary';
    Z_ERRNO:         Result := 'file error';
    Z_STREAM_ERROR:  Result := 'stream error';
    Z_DATA_ERROR:    Result := 'data error';
    Z_MEM_ERROR:     Result := 'insufficient memory';
    Z_BUF_ERROR:     Result := 'buffer error';
    Z_VERSION_ERROR: Result := 'incompatible version';
  else
    Result := IntToStr(code);
  end;
end;

function ZCheckCompression(code: Integer): Integer;
begin
  Result := code;
  if code < 0 then
    raise EZCompressionError.Create(ZErrorText(code));
end;

function ZCheckDecompression(code: Integer): Integer;
begin
  Result := code;
  if (code < 0) or (code = Z_NEED_DICT) then
    raise EZDecompressionError.Create(ZErrorText(code));
end;

const
  ZLevels: array[TZCompressionLevel] of Integer =
    (Z_NO_COMPRESSION, Z_BEST_SPEED, Z_DEFAULT_COMPRESSION, Z_BEST_COMPRESSION);
  DefaultMemLevel = 8;
  StreamBufferSize = 32768;
  SkipBufferSize = 8192;
  SInvalidOperation = 'Invalid ZStream operation!';

{ ---------------------------------------------------------------------
  the zlib.h functions
  ---------------------------------------------------------------------}

function deflateInit(var strm: z_stream; level: Integer): Integer;
begin
  Result := deflateInit_(strm, level, ZLIB_VERSION, SizeOf(z_stream));
end;

function deflateInit2(var strm: z_stream; level, method, windowBits, memLevel, strategy: Integer): Integer;
begin
  Result := deflateInit2_(strm, level, method, windowBits, memLevel, strategy, ZLIB_VERSION, SizeOf(z_stream));
end;

function deflateInit_(var strm: z_stream; level: Integer; version: MarshaledAString; stream_size: Integer): Integer;
begin
  UseProgramAllocator(strm);
  Result := z_deflateInit_(strm, level, version, stream_size);
end;

function deflateInit2_(var strm: z_stream; level, method, windowBits, memLevel, strategy: Integer; version: MarshaledAString; stream_size: Integer): Integer;
begin
  UseProgramAllocator(strm);
  Result := z_deflateInit2_(strm, level, method, windowBits, memLevel, strategy, version, stream_size);
end;

function deflate(var strm: z_stream; flush: Integer): Integer;
begin
  Result := z_deflate(strm, flush);
end;

function deflateEnd(var strm: z_stream): Integer;
begin
  Result := z_deflateEnd(strm);
end;

function deflateReset(var strm: z_stream): Integer;
begin
  Result := z_deflateReset(strm);
end;

function deflateParams(var strm: z_stream; level, strategy: Integer): Integer;
begin
  Result := z_deflateParams(strm, level, strategy);
end;

function deflateBound(var strm: z_stream; sourceLen: Cardinal): LongWord;
begin
  Result := LongWord(z_deflateBound(strm, sourceLen));
end;

function deflateSetDictionary(var strm: z_stream; dictionary: PByte; dictLength: Cardinal): Integer;
begin
  Result := z_deflateSetDictionary(strm, dictionary, dictLength);
end;

function inflateInit(var strm: z_stream): Integer;
begin
  Result := inflateInit_(strm, ZLIB_VERSION, SizeOf(z_stream));
end;

function inflateInit2(var strm: z_stream; windowBits: Integer): Integer;
begin
  Result := inflateInit2_(strm, windowBits, ZLIB_VERSION, SizeOf(z_stream));
end;

function inflateInit_(var strm: z_stream; version: MarshaledAString; stream_size: Integer): Integer;
begin
  UseProgramAllocator(strm);
  Result := z_inflateInit_(strm, version, stream_size);
end;

function inflateInit2_(var strm: z_stream; windowBits: Integer; version: MarshaledAString; stream_size: Integer): Integer;
begin
  UseProgramAllocator(strm);
  Result := z_inflateInit2_(strm, windowBits, version, stream_size);
end;

function inflate(var strm: z_stream; flush: Integer): Integer;
begin
  Result := z_inflate(strm, flush);
end;

function inflateEnd(var strm: z_stream): Integer;
begin
  Result := z_inflateEnd(strm);
end;

function inflateReset(var strm: z_stream): Integer;
begin
  Result := z_inflateReset(strm);
end;

function inflateReset2(var strm: z_stream; windowBits: Integer): Integer;
begin
  Result := z_inflateReset2(strm, windowBits);
end;

function inflateSync(var strm: z_stream): Integer;
begin
  Result := z_inflateSync(strm);
end;

function inflateSetDictionary(var strm: z_stream; dictionary: PByte; dictLength: Cardinal): Integer;
begin
  Result := z_inflateSetDictionary(strm, dictionary, dictLength);
end;

function crc32(crc: UInt32; buf: PByte; len: Cardinal): UInt32;
begin
  Result := UInt32(z_crc32(crc, buf, len));
end;

function adler32(adler: LongWord; buf: PByte; len: Cardinal): LongWord;
begin
  Result := LongWord(z_adler32(adler, buf, len));
end;

function zlibVersion: MarshaledAString;
begin
  Result := z_zlibVersion;
end;

{ compress/uncompress as zlib.h defines them, over the streaming calls in
  one shot each (the buffers are 32-bit sized, so one call covers them):
  zlib's compress.c and uncompr.c are not in the objects, and every stream
  allocates through the program's memory manager }
function compress2(dest: PByte; var destLen: LongWord; source: PByte; sourceLen: LongWord; level: Integer): Integer;
var
  strm: z_stream;
begin
  strm := Default(z_stream);
  Result := deflateInit(strm, level);
  if Result <> Z_OK then
    Exit;
  strm.next_in := source;
  strm.avail_in := sourceLen;
  strm.next_out := dest;
  strm.avail_out := destLen;
  Result := z_deflate(strm, Z_FINISH);
  destLen := LongWord(strm.total_out);
  z_deflateEnd(strm);
  case Result of
    Z_STREAM_END:
      Result := Z_OK;
    Z_OK:
      Result := Z_BUF_ERROR;      { the output buffer was too small }
  end;
end;

function compress(dest: PByte; var destLen: LongWord; source: PByte; sourceLen: LongWord): Integer;
begin
  Result := compress2(dest, destLen, source, sourceLen, Z_DEFAULT_COMPRESSION);
end;

function compressBound(sourceLen: LongWord): LongWord;
begin
  { zlib.h: the worst case of the zlib format, stored blocks included }
  Result := sourceLen + (sourceLen shr 12) + (sourceLen shr 14) + (sourceLen shr 25) + 13;
end;

function uncompress(dest: PByte; var destLen: LongWord; source: PByte; sourceLen: LongWord): Integer;
var
  strm: z_stream;
  empty: Byte;
begin
  strm := Default(z_stream);
  Result := inflateInit(strm);
  if Result <> Z_OK then
    Exit;
  strm.next_in := source;
  strm.avail_in := sourceLen;
  strm.next_out := dest;
  if destLen = 0 then
    strm.next_out := @empty;       { an empty output still needs a valid next_out }
  strm.avail_out := destLen;
  Result := z_inflate(strm, Z_FINISH);
  destLen := LongWord(strm.total_out);
  z_inflateEnd(strm);
  case Result of
    Z_STREAM_END:
      Result := Z_OK;
    Z_NEED_DICT:
      Result := Z_DATA_ERROR;
    Z_OK, Z_BUF_ERROR:
      { the output buffer filled up before the stream ended, or the input
        ended before the stream did }
      if strm.avail_in = 0 then
        Result := Z_DATA_ERROR
      else
        Result := Z_BUF_ERROR;
  end;
end;

{ ---------------------------------------------------------------------
  TCustomZStream
  ---------------------------------------------------------------------}

constructor TCustomZStream.Create(stream: TStream);
begin
  inherited Create;
  FStream := stream;
  FStreamPos := stream.Position;
end;

procedure TCustomZStream.DoProgress;
begin
  if Assigned(FOnProgress) then
    FOnProgress(Self);
end;

{ ---------------------------------------------------------------------
  TZCompressionStream
  ---------------------------------------------------------------------}

constructor TZCompressionStream.Create(dest: TStream);
begin
  Create(dest, zcDefault, 15);
end;

constructor TZCompressionStream.Create(dest: TStream; compressionLevel: TZCompressionLevel; windowBits: Integer);
begin
  inherited Create(dest);
  FZStream.next_out := @FBuffer[0];
  FZStream.avail_out := SizeOf(FBuffer);
  ZCheckCompression(deflateInit2(FZStream, ZLevels[compressionLevel], Z_DEFLATED, windowBits, DefaultMemLevel, Z_DEFAULT_STRATEGY));
end;

constructor TZCompressionStream.Create(compressionLevel: TCompressionLevel; dest: TStream);
begin
  Create(dest, TZCompressionLevel(compressionLevel), 15);
end;

destructor TZCompressionStream.Destroy;
var
  code: Integer;
begin
  if Assigned(FZStream.state) then
  begin
    try
      FZStream.next_in := nil;
      FZStream.avail_in := 0;
      repeat
        code := ZCheckCompression(deflate(FZStream, Z_FINISH));
        FlushOutput;
      until code = Z_STREAM_END;
    finally
      deflateEnd(FZStream);
    end;
  end;
  inherited Destroy;
end;

{ what the buffer holds goes to dest at the kept position }
procedure TZCompressionStream.FlushOutput;
var
  count: Integer;
begin
  count := SizeOf(FBuffer) - FZStream.avail_out;
  if count > 0 then
  begin
    if FStream.Position <> FStreamPos then
      FStream.Position := FStreamPos;
    FStream.WriteBuffer(FBuffer[0], count);
    Inc(FStreamPos, count);
    DoProgress;
  end;
  FZStream.next_out := @FBuffer[0];
  FZStream.avail_out := SizeOf(FBuffer);
end;

function TZCompressionStream.GetCompressionRate: Single;
begin
  if FZStream.total_in = 0 then
    Result := 0
  else
    Result := (1 - FZStream.total_out / FZStream.total_in) * 100;
end;

function TZCompressionStream.GetSize: Int64;
begin
  Result := FZStream.total_in;
end;

function TZCompressionStream.Read(var buffer; count: Longint): Longint;
begin
  Result := 0;
  raise EZCompressionError.Create(SInvalidOperation);
end;

function TZCompressionStream.Write(const buffer; count: Longint): Longint;
begin
  if count <= 0 then
    Exit(0);
  FZStream.next_in := @buffer;
  FZStream.avail_in := count;
  while FZStream.avail_in > 0 do
  begin
    ZCheckCompression(deflate(FZStream, Z_NO_FLUSH));
    if FZStream.avail_out = 0 then
      FlushOutput;
  end;
  Result := count;
end;

function TZCompressionStream.Seek(const offset: Int64; origin: TSeekOrigin): Int64;
begin
  case origin of
    soBeginning:
      if offset <> Int64(FZStream.total_in) then
        raise EZCompressionError.Create(SInvalidOperation);
    soCurrent, soEnd:
      if offset <> 0 then
        raise EZCompressionError.Create(SInvalidOperation);
  end;
  Result := FZStream.total_in;
end;

{ ---------------------------------------------------------------------
  TZDecompressionStream
  ---------------------------------------------------------------------}

constructor TZDecompressionStream.Create(source: TStream);
begin
  Create(source, 15, False);
end;

constructor TZDecompressionStream.Create(source: TStream; windowBits: Integer);
begin
  Create(source, windowBits, False);
end;

constructor TZDecompressionStream.Create(source: TStream; windowBits: Integer; ownsStream: Boolean);
begin
  inherited Create(source);
  FOwnsStream := ownsStream;
  FStreamStart := FStreamPos;
  FWindowBits := windowBits;
  FZStream.next_in := @FBuffer[0];
  FZStream.avail_in := 0;
  ZCheckDecompression(inflateInit2(FZStream, windowBits));
end;

destructor TZDecompressionStream.Destroy;
begin
  if Assigned(FZStream.state) then
    inflateEnd(FZStream);
  if FOwnsStream then
    FreeAndNil(FStream)
  else if Assigned(FStream) then
    try
      { the bytes the library holds but did not consume are not read }
      FStream.Position := FStreamPos - FZStream.avail_in;
    except
    end;
  inherited Destroy;
end;

function TZDecompressionStream.Read(var buffer; count: Longint): Longint;
var
  code: Integer;
  got: Longint;
begin
  if (count <= 0) or FEnded then
    Exit(0);
  FZStream.next_out := @buffer;
  FZStream.avail_out := count;
  while FZStream.avail_out > 0 do
  begin
    if FZStream.avail_in = 0 then
    begin
      if FStream.Position <> FStreamPos then
        FStream.Position := FStreamPos;
      got := FStream.Read(FBuffer[0], SizeOf(FBuffer));
      if got > 0 then
      begin
        Inc(FStreamPos, got);
        FZStream.next_in := @FBuffer[0];
        FZStream.avail_in := got;
        DoProgress;
      end;
      { inflate can still emit a match kept in its state after consuming
        every source byte (especially raw deflate, without a trailer). }
    end;
    code := inflate(FZStream, Z_NO_FLUSH);
    if code = Z_STREAM_END then
    begin
      FEnded := True;
      { input behind the end of the deflate stream stays unread }
      Dec(FStreamPos, FZStream.avail_in);
      FZStream.avail_in := 0;
      Break;
    end;
    if code = Z_BUF_ERROR then
      Break;                         { no input or output progress possible }
    ZCheckDecompression(code);
  end;
  Result := count - Longint(FZStream.avail_out);
  Inc(FPosition, Result);
  if FEnded then
  begin
    FSize := FPosition;
    FSizeKnown := True;
  end;
end;

function TZDecompressionStream.Write(const buffer; count: Longint): Longint;
begin
  Result := 0;
  raise EZDecompressionError.Create(SInvalidOperation);
end;

procedure TZDecompressionStream.Restart;
begin
  ZCheckDecompression(inflateReset(FZStream));
  FZStream.next_in := @FBuffer[0];
  FZStream.avail_in := 0;
  FStreamPos := FStreamStart;
  FStream.Position := FStreamStart;
  FPosition := 0;
  FEnded := False;
end;

{ a forward seek is a read that is thrown away; the data ending before the
  target is a read error, as it is in Delphi (its Seek uses ReadBuffer) }
procedure TZDecompressionStream.Skip(count: Int64);
var
  scratch: array[0..SkipBufferSize - 1] of Byte;
  piece: Longint;
begin
  while count > 0 do
  begin
    if count > SizeOf(scratch) then
      piece := SizeOf(scratch)
    else
      piece := count;
    piece := Read(scratch, piece);
    if piece = 0 then
      raise EReadError.Create(SReadError);
    Dec(count, piece);
  end;
end;

function TZDecompressionStream.Seek(const offset: Int64; origin: TSeekOrigin): Int64;
var
  scratch: array[0..SkipBufferSize - 1] of Byte;
begin
  case origin of
    soBeginning:
      begin
        if offset < 0 then
          raise EZDecompressionError.Create(SInvalidOperation);
        if offset < FPosition then
          Restart;
        Skip(offset - FPosition);
      end;
    soCurrent:
      begin
        if offset < 0 then
          raise EZDecompressionError.Create(SInvalidOperation);
        Skip(offset);
      end;
    soEnd:
      begin
        if offset <> 0 then
          raise EZDecompressionError.Create(SInvalidOperation);
        while Read(scratch, SizeOf(scratch)) > 0 do ;
      end;
  end;
  Result := FPosition;
end;

function TZDecompressionStream.GetSize: Int64;
var
  saved: Int64;
begin
  if not FSizeKnown then
  begin
    saved := FPosition;
    Seek(0, soEnd);
    FSize := FPosition;
    FSizeKnown := True;
    if saved <> FPosition then
      Seek(saved, soBeginning);
  end;
  Result := FSize;
end;

{ ---------------------------------------------------------------------
  helpers
  ---------------------------------------------------------------------}

function ZCompressGrowth(inSize: Integer): Integer; inline;
begin
  Result := ((inSize + inSize div 10 + 12) + 255) and not 255;
end;

procedure ZCompress(const inBuffer: Pointer; inSize: Integer; out outBuffer: Pointer; out outSize: Integer; level: TZCompressionLevel);
var
  strm: z_stream;
  step: Integer;
  code: Integer;
begin
  step := ZCompressGrowth(inSize);
  outSize := step;
  outBuffer := GetMem(outSize);
  try
    strm := Default(z_stream);
    strm.next_in := inBuffer;
    strm.avail_in := inSize;
    strm.next_out := outBuffer;
    strm.avail_out := outSize;
    ZCheckCompression(deflateInit(strm, ZLevels[level]));
    try
      repeat
        code := ZCheckCompression(deflate(strm, Z_FINISH));
        if code = Z_STREAM_END then
          Break;
        { more room, keeping the produced bytes }
        Inc(outSize, step);
        ReallocMem(outBuffer, outSize);
        strm.next_out := PByte(outBuffer) + strm.total_out;
        strm.avail_out := outSize - strm.total_out;
      until False;
    finally
      deflateEnd(strm);
    end;
    outSize := strm.total_out;
    ReallocMem(outBuffer, outSize);
  except
    FreeMem(outBuffer);
    outBuffer := nil;
    outSize := 0;
    raise;
  end;
end;

procedure ZCompress(const inBuffer: Pointer; inSize: Integer; out outBuffer: Pointer; out outSize: Integer; level: TCompressionLevel);
begin
  ZCompress(inBuffer, inSize, outBuffer, outSize, TZCompressionLevel(level));
end;

procedure ZCompress(const inBuffer: TBytes; out outBuffer: TBytes; level: TZCompressionLevel);
var
  buffer: Pointer;
  size: Integer;
begin
  ZCompress(Pointer(inBuffer), Length(inBuffer), buffer, size, level);
  try
    SetLength(outBuffer, size);
    if size > 0 then
      Move(buffer^, outBuffer[0], size);
  finally
    FreeMem(buffer);
  end;
end;

procedure ZDecompress(const inBuffer: Pointer; inSize: Integer; out outBuffer: Pointer; out outSize: Integer; outEstimate: Integer);
var
  strm: z_stream;
  step: Integer;
  code: Integer;
begin
  if outEstimate > 0 then
    step := outEstimate
  else
    step := (inSize + 255) and not 255;
  if step < 16 then
    step := 16;
  outSize := step;
  outBuffer := GetMem(outSize);
  try
    strm := Default(z_stream);
    strm.next_in := inBuffer;
    strm.avail_in := inSize;
    strm.next_out := outBuffer;
    strm.avail_out := outSize;
    ZCheckDecompression(inflateInit(strm));
    try
      repeat
        code := inflate(strm, Z_NO_FLUSH);
        if code = Z_STREAM_END then
          Break;
        if (code = Z_BUF_ERROR) and (strm.avail_in = 0) then
          raise EZDecompressionError.Create(ZErrorText(Z_BUF_ERROR));   { input ran out first }
        if code <> Z_BUF_ERROR then
          ZCheckDecompression(code);
        if strm.avail_out = 0 then
        begin
          Inc(outSize, step);
          ReallocMem(outBuffer, outSize);
          strm.next_out := PByte(outBuffer) + strm.total_out;
          strm.avail_out := outSize - strm.total_out;
        end;
      until False;
      if strm.avail_in <> 0 then
        raise EZDecompressionError.Create(ZErrorText(Z_BUF_ERROR));     { bytes behind the stream }
    finally
      inflateEnd(strm);
    end;
    outSize := strm.total_out;
    ReallocMem(outBuffer, outSize);
  except
    FreeMem(outBuffer);
    outBuffer := nil;
    outSize := 0;
    raise;
  end;
end;

procedure ZDecompress(const inBuffer: TBytes; out outBuffer: TBytes; outEstimate: Integer);
var
  buffer: Pointer;
  size: Integer;
begin
  ZDecompress(Pointer(inBuffer), Length(inBuffer), buffer, size, outEstimate);
  try
    SetLength(outBuffer, size);
    if size > 0 then
      Move(buffer^, outBuffer[0], size);
  finally
    FreeMem(buffer);
  end;
end;

procedure ZCompressStream(inStream, outStream: TStream; level: TZCompressionLevel);
var
  strm: z_stream;
  inBuf, outBuf: array[0..StreamBufferSize - 1] of Byte;
  got: Longint;
  code, flush: Integer;
begin
  strm := Default(z_stream);
  ZCheckCompression(deflateInit(strm, ZLevels[level]));
  try
    repeat
      got := inStream.Read(inBuf, SizeOf(inBuf));
      if got > 0 then
        flush := Z_NO_FLUSH
      else
        flush := Z_FINISH;
      strm.next_in := @inBuf[0];
      strm.avail_in := got;
      repeat
        strm.next_out := @outBuf[0];
        strm.avail_out := SizeOf(outBuf);
        code := ZCheckCompression(deflate(strm, flush));
        if SizeOf(outBuf) - strm.avail_out > 0 then
          outStream.WriteBuffer(outBuf[0], SizeOf(outBuf) - strm.avail_out);
      until ((flush = Z_NO_FLUSH) and (strm.avail_out <> 0)) or (code = Z_STREAM_END);
    until flush = Z_FINISH;
  finally
    deflateEnd(strm);
  end;
end;

procedure ZDecompressStream(inStream, outStream: TStream);
var
  strm: z_stream;
  inBuf, outBuf: array[0..StreamBufferSize - 1] of Byte;
  got: Longint;
  code: Integer;
begin
  strm := Default(z_stream);
  ZCheckDecompression(inflateInit(strm));
  try
    code := Z_OK;
    repeat
      got := inStream.Read(inBuf, SizeOf(inBuf));
      if got <= 0 then
        raise EZDecompressionError.Create(ZErrorText(Z_BUF_ERROR));   { empty or truncated input }
      strm.next_in := @inBuf[0];
      strm.avail_in := got;
      repeat
        strm.next_out := @outBuf[0];
        strm.avail_out := SizeOf(outBuf);
        code := inflate(strm, Z_NO_FLUSH);
        if code <> Z_BUF_ERROR then
          ZCheckDecompression(code);
        if SizeOf(outBuf) - strm.avail_out > 0 then
          outStream.WriteBuffer(outBuf[0], SizeOf(outBuf) - strm.avail_out);
      until (strm.avail_in = 0) or (code = Z_STREAM_END);
    until code = Z_STREAM_END;
  finally
    inflateEnd(strm);
  end;
end;

function ZCompressStr(const s: string; level: TZCompressionLevel): TBytes;
var
  buffer: Pointer;
  size: Integer;
begin
  Result := nil;
  ZCompress(Pointer(s), Length(s) * SizeOf(Char), buffer, size, level);
  try
    SetLength(Result, size);
    if size > 0 then
      Move(buffer^, Result[0], size);
  finally
    FreeMem(buffer);
  end;
end;

function ZDecompressStr(const s: TBytes): string;
var
  buffer: Pointer;
  size: Integer;
begin
  Result := '';
  ZDecompress(Pointer(s), Length(s), buffer, size, 0);
  try
    SetLength(Result, size div SizeOf(Char));
    if size > 0 then
      Move(buffer^, Pointer(Result)^, Length(Result) * SizeOf(Char));
  finally
    FreeMem(buffer);
  end;
end;

end.
