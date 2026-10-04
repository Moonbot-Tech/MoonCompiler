unit pulse_zlib_mormot;

{ The zlib work of pulse_zlib_rtl's buffer forms through mormot.lib.z: the same
  calls in the same order on the zlib mORMot links - under MoonCompiler on Win64
  its own static objects (zlib 1.2.11), under Delphi Win64 the zlib of the
  Delphi RTL, on Linux the system libz. }

{$ifdef FPC}
  {$mode delphi}{$H+}
{$endif}

{$Q-}{$R-}

interface

function MormotDeflateBuffer(Source: Pointer; SourceSize: Integer; Target: Pointer; TargetSize: Integer;
  Level, WindowBits: Integer): Integer;

function MormotInflateBuffer(Source: Pointer; SourceSize: Integer; Target: Pointer; TargetSize: Integer;
  WindowBits: Integer): Integer;

function MormotInflateMessages(Frames: PByte; const Bounds: array of Integer; Receive, Output: PByte;
  OutputSize: Integer; out Digest: UInt64): Int64;

implementation

uses
  SysUtils,
  mormot.lib.z;

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

function MormotDeflateBuffer(Source: Pointer; SourceSize: Integer; Target: Pointer; TargetSize: Integer;
  Level, WindowBits: Integer): Integer;
var
  Z: TZLib;
begin
  Z.Init(Source, Target, SourceSize, TargetSize);
  If not Z.CompressInit(Level, WindowBits > 0) then
    raise EZLib.Create('CompressInit');
  try
    If Z.Compress(Z_FINISH) <> Z_STREAM_END then
      raise EZLib.Create('Compress');
    Result := TargetSize - Integer(Z.Stream.avail_out);
  finally
    Z.CompressEnd;
  end;
end;

function MormotInflateBuffer(Source: Pointer; SourceSize: Integer; Target: Pointer; TargetSize: Integer;
  WindowBits: Integer): Integer;
var
  Z: TZLib;
begin
  Z.Init(Source, Target, SourceSize, TargetSize);
  If not Z.UncompressInit(WindowBits > 0) then
    raise EZLib.Create('UncompressInit');
  try
    If Z.Uncompress(Z_FINISH) <> Z_STREAM_END then
      raise EZLib.Create('Uncompress');
    Result := TargetSize - Integer(Z.Stream.avail_out);
  finally
    Z.UncompressEnd;
  end;
end;

function MormotInflateMessages(Frames: PByte; const Bounds: array of Integer; Receive, Output: PByte;
  OutputSize: Integer; out Digest: UInt64): Int64;
var
  Z: TZLib;
  I, Size, Produced, Code: Integer;
begin
  Result := 0;
  Digest := 0;
  Z.Init(nil, nil, 0, 0);
  If not Z.UncompressInit(False) then
    raise EZLib.Create('UncompressInit');
  try
    for I := 0 to High(Bounds) - 1 do begin
      Size := Bounds[I + 1] - Bounds[I];
      Move((Frames + Bounds[I])^, Receive^, Size);
      Move(Trailer, (Receive + Size)^, 4);
      Z.Stream.next_in := Pointer(Receive);
      Z.Stream.avail_in := Size + 4;
      Produced := 0;
      repeat
        Z.Stream.next_out := Pointer(Output + Produced);
        Z.Stream.avail_out := OutputSize - Produced;
        Code := Z.Uncompress(Z_NO_FLUSH);
        If Code = Z_BUF_ERROR then
          Break;
        If (Code <> Z_OK) and (Code <> Z_STREAM_END) then
          raise EZLib.Create('Uncompress');
        Produced := OutputSize - Integer(Z.Stream.avail_out);
      until (Z.Stream.avail_in = 0) or (Code = Z_STREAM_END);
      Inc(Result, Produced);
      Digest := Digest * 31 + Digest64(Output, Produced);
    end;
  finally
    Z.UncompressEnd;
  end;
end;

end.
