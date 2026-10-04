unit pulse_zlib_rtl;

{ The zlib forms of the product (MoonBot) through System.ZLib: the stream
  classes as MoonTrades, MarketsU and MoonProto call them, and the z_stream
  calls as the websocket client and the buffer helpers make them.  Each form is
  one whole operation of the product: the objects it creates, it frees. }

{$ifdef FPC}
  {$mode delphi}{$H+}
{$endif}

{$Q-}{$R-}

interface

uses
  Classes;

{ TZCompressionStream over a new TMemoryStream, the source copied in with
  CopyFrom (MoonTrades SendData: raw deflate of a trade packet; MarketsU
  BuildCandlesZlibLocked: zlib format of the candle blob); the compressed size. }
function RtlStreamDeflate(Source: TMemoryStream; Fastest: Boolean; WindowBits: Integer): Int64;

{ The same stream written part by part (SendMarketHistoryChunked: the version
  byte, then each array behind its count). }
function RtlStreamDeflateParts(Data: PByte; const Sizes: array of Integer; Fastest: Boolean;
  WindowBits: Integer): Int64;

{ The compression of the two forms above into a given stream: their output for
  the check before the measurement. }
procedure RtlStreamDeflateTo(Source: TMemoryStream; Fastest: Boolean; WindowBits: Integer; Target: TStream);
procedure RtlStreamDeflatePartsTo(Data: PByte; const Sizes: array of Integer; Fastest: Boolean;
  WindowBits: Integer; Target: TStream);

{ TZDecompressionStream over the compressed bytes, CopyFrom(Z, 0) into a new
  TMemoryStream (MoonTrades UDPRead, MarketsU ApplyRecvdStream); the size of
  the output, Digest over it. }
function RtlStreamInflate(Source: TMemoryStream; WindowBits: Integer; out Digest: UInt64): Int64;

{ deflateInit2 / deflate(Z_FINISH) / deflateEnd from buffer to buffer; the
  compressed size. }
function RtlDeflateBuffer(Source: Pointer; SourceSize: Integer; Target: Pointer; TargetSize: Integer;
  Level, WindowBits: Integer): Integer;

{ inflateInit2 / inflate(Z_FINISH) / inflateEnd from buffer to buffer; the size
  of the output. }
function RtlInflateBuffer(Source: Pointer; SourceSize: Integer; Target: Pointer; TargetSize: Integer;
  WindowBits: Integer): Integer;

{ permessage-deflate as TWSThread.HandleDataFrame takes it: one raw inflate
  stream over the messages of a connection, each payload moved into the
  receive buffer with the 4-byte trailer behind it and inflated until the input
  is gone.  Frames holds the payloads back to back, Bounds[I]..Bounds[I+1] the
  message I; the bytes out, Digest over every message. }
function RtlInflateMessages(Frames: PByte; const Bounds: array of Integer; Receive, Output: PByte;
  OutputSize: Integer; out Digest: UInt64): Int64;

{ The payloads for RtlInflateMessages: each message deflated with Z_SYNC_FLUSH
  on one raw stream, the trailer 00 00 FF FF cut off, as a server sends them. }
procedure RtlDeflateMessages(Messages: PByte; const Bounds: array of Integer; Frames: TMemoryStream;
  var FrameBounds: array of Integer);

function RtlZlibVersion: string;

implementation

uses
  SysUtils,
  System.ZLib;

const
  Trailer: array[0..3] of Byte = ($00, $00, $FF, $FF);

function Digest64(Data: PByte; Size: Integer): UInt64;
var
  Head, Tail: UInt64;
begin
  Head := 0;
  Tail := 0;
  If Size >= 8 then begin
    Move(Data^, Head, 8);
    Move((Data + Size - 8)^, Tail, 8);
  end;
  Result := UInt64(Size) xor Head xor (Tail shl 1);
end;

procedure RtlStreamDeflateTo(Source: TMemoryStream; Fastest: Boolean; WindowBits: Integer; Target: TStream);
var
  Z: TZCompressionStream;
begin
  If Fastest then
    Z := TZCompressionStream.Create(Target, zcFastest, WindowBits)
  else
    Z := TZCompressionStream.Create(Target, zcDefault, WindowBits);
  try
    Source.Position := 0;
    Z.CopyFrom(Source, Source.Size);
  finally
    FreeAndNil(Z);
  end;
end;

function RtlStreamDeflate(Source: TMemoryStream; Fastest: Boolean; WindowBits: Integer): Int64;
var
  Target: TMemoryStream;
begin
  Target := TMemoryStream.Create;
  try
    RtlStreamDeflateTo(Source, Fastest, WindowBits, Target);
    Result := Target.Size;
  finally
    FreeAndNil(Target);
  end;
end;

procedure RtlStreamDeflatePartsTo(Data: PByte; const Sizes: array of Integer; Fastest: Boolean;
  WindowBits: Integer; Target: TStream);
var
  Z: TZCompressionStream;
  I: Integer;
begin
  If Fastest then
    Z := TZCompressionStream.Create(Target, zcFastest, WindowBits)
  else
    Z := TZCompressionStream.Create(Target, zcDefault, WindowBits);
  try
    for I := 0 to High(Sizes) do begin
      Z.Write(Data^, Sizes[I]);
      Inc(Data, Sizes[I]);
    end;
  finally
    FreeAndNil(Z);
  end;
end;

function RtlStreamDeflateParts(Data: PByte; const Sizes: array of Integer; Fastest: Boolean;
  WindowBits: Integer): Int64;
var
  Target: TMemoryStream;
begin
  Target := TMemoryStream.Create;
  try
    RtlStreamDeflatePartsTo(Data, Sizes, Fastest, WindowBits, Target);
    Result := Target.Size;
  finally
    FreeAndNil(Target);
  end;
end;

function RtlStreamInflate(Source: TMemoryStream; WindowBits: Integer; out Digest: UInt64): Int64;
var
  Target: TMemoryStream;
  Z: TZDecompressionStream;
begin
  Target := TMemoryStream.Create;
  try
    Source.Position := 0;
    Z := TZDecompressionStream.Create(Source, WindowBits);
    try
      Target.CopyFrom(Z, 0);
    finally
      FreeAndNil(Z);
    end;
    Result := Target.Size;
    Digest := Digest64(Target.Memory, Target.Size);
  finally
    FreeAndNil(Target);
  end;
end;

function RtlDeflateBuffer(Source: Pointer; SourceSize: Integer; Target: Pointer; TargetSize: Integer;
  Level, WindowBits: Integer): Integer;
var
  Z: z_stream;
begin
  FillChar(Z, SizeOf(Z), 0);
  If deflateInit2(Z, Level, Z_DEFLATED, WindowBits, 8, Z_DEFAULT_STRATEGY) <> Z_OK then
    raise EZCompressionError.Create('deflateInit2');
  try
    Z.next_in := Source;
    Z.avail_in := SourceSize;
    Z.next_out := Target;
    Z.avail_out := TargetSize;
    If deflate(Z, Z_FINISH) <> Z_STREAM_END then
      raise EZCompressionError.Create('deflate');
    Result := TargetSize - Integer(Z.avail_out);
  finally
    deflateEnd(Z);
  end;
end;

function RtlInflateBuffer(Source: Pointer; SourceSize: Integer; Target: Pointer; TargetSize: Integer;
  WindowBits: Integer): Integer;
var
  Z: z_stream;
begin
  FillChar(Z, SizeOf(Z), 0);
  If inflateInit2(Z, WindowBits) <> Z_OK then
    raise EZDecompressionError.Create('inflateInit2');
  try
    Z.next_in := Source;
    Z.avail_in := SourceSize;
    Z.next_out := Target;
    Z.avail_out := TargetSize;
    If inflate(Z, Z_FINISH) <> Z_STREAM_END then
      raise EZDecompressionError.Create('inflate');
    Result := TargetSize - Integer(Z.avail_out);
  finally
    inflateEnd(Z);
  end;
end;

function RtlInflateMessages(Frames: PByte; const Bounds: array of Integer; Receive, Output: PByte;
  OutputSize: Integer; out Digest: UInt64): Int64;
var
  Z: z_stream;
  I, Size, Produced, Code: Integer;
begin
  Result := 0;
  Digest := 0;
  FillChar(Z, SizeOf(Z), 0);
  If inflateInit2(Z, -15) <> Z_OK then
    raise EZDecompressionError.Create('inflateInit2');
  try
    for I := 0 to High(Bounds) - 1 do begin
      Size := Bounds[I + 1] - Bounds[I];
      Move((Frames + Bounds[I])^, Receive^, Size);
      Move(Trailer, (Receive + Size)^, 4);
      Z.next_in := Receive;
      Z.avail_in := Size + 4;
      Produced := 0;
      repeat
        Z.next_out := Output + Produced;
        Z.avail_out := OutputSize - Produced;
        Code := inflate(Z, Z_NO_FLUSH);
        If Code = Z_BUF_ERROR then
          Break;
        If (Code <> Z_OK) and (Code <> Z_STREAM_END) then
          raise EZDecompressionError.Create('inflate');
        Produced := OutputSize - Integer(Z.avail_out);
      until (Z.avail_in = 0) or (Code = Z_STREAM_END);
      Inc(Result, Produced);
      Digest := Digest * 31 + Digest64(Output, Produced);
    end;
  finally
    inflateEnd(Z);
  end;
end;

procedure RtlDeflateMessages(Messages: PByte; const Bounds: array of Integer; Frames: TMemoryStream;
  var FrameBounds: array of Integer);
var
  Z: z_stream;
  Buffer: array[0..65535] of Byte;
  I, Size: Integer;
begin
  FillChar(Z, SizeOf(Z), 0);
  If deflateInit2(Z, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -15, 8, Z_DEFAULT_STRATEGY) <> Z_OK then
    raise EZCompressionError.Create('deflateInit2');
  try
    Frames.Size := 0;
    for I := 0 to High(Bounds) - 1 do begin
      FrameBounds[I] := Frames.Size;
      Z.next_in := Messages + Bounds[I];
      Z.avail_in := Bounds[I + 1] - Bounds[I];
      Z.next_out := @Buffer[0];
      Z.avail_out := SizeOf(Buffer);
      If deflate(Z, Z_SYNC_FLUSH) <> Z_OK then
        raise EZCompressionError.Create('deflate');
      Size := SizeOf(Buffer) - Integer(Z.avail_out);
      If (Z.avail_in <> 0) or (Size < 4) or (Buffer[Size - 4] <> 0) or (Buffer[Size - 3] <> 0) or
         (Buffer[Size - 2] <> $FF) or (Buffer[Size - 1] <> $FF) then
        raise EZCompressionError.Create('sync flush');
      Frames.Write(Buffer, Size - 4);
    end;
    FrameBounds[High(Bounds)] := Frames.Size;
  finally
    deflateEnd(Z);
  end;
end;

function RtlZlibVersion: string;
begin
  Result := string(zlibVersion);
end;

end.
