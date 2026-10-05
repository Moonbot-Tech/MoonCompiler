{ MoonCompiler's private Brotli decoder binding. The MIT-licensed upstream
  decoder is linked statically; no Delphi implementation was used. See
  ../native/brotli for the pinned source, license and reproducible build. }
unit Moon.Brotli;
{$mode objfpc}{$H+}
interface
uses SysUtils, Classes;
type
  EBrotliError = class(EStreamError);
procedure BrotliDecompress(Source, Destination: TStream; EncodedSize: Int64);

implementation
{$L moonbrotli_common_constants.o}
{$L moonbrotli_common_context.o}
{$L moonbrotli_common_dictionary.o}
{$L moonbrotli_common_platform.o}
{$L moonbrotli_common_shared_dictionary.o}
{$L moonbrotli_common_transform.o}
{$L moonbrotli_dec_bit_reader.o}
{$L moonbrotli_dec_decode.o}
{$L moonbrotli_dec_huffman.o}
{$L moonbrotli_dec_prefix.o}
{$L moonbrotli_dec_state.o}
{$L moonbrotli_dec_static_init.o}
type
  TAlloc = function(Context: Pointer; Size: SizeUInt): Pointer; cdecl;
  TFree = procedure(Context, Block: Pointer); cdecl;

function DecoderCreate(Alloc: TAlloc; Free: TFree; Context: Pointer): Pointer; cdecl;
  external name 'moon_brotli_BrotliDecoderCreateInstance';
procedure DecoderDestroy(State: Pointer); cdecl; external name 'moon_brotli_BrotliDecoderDestroyInstance';
function DecoderRun(State: Pointer; var AvailableIn: SizeUInt; var NextIn: PByte;
  var AvailableOut: SizeUInt; var NextOut: PByte; TotalOut: PSizeUInt): Integer; cdecl;
  external name 'moon_brotli_BrotliDecoderDecompressStream';
function DecoderError(State: Pointer): Integer; cdecl; external name 'moon_brotli_BrotliDecoderGetErrorCode';

function BrotliMalloc(Size: SizeUInt): Pointer; cdecl; public name 'moon_brotli_malloc';
begin
  try
    Result := GetMem(Size);
  except
    on EOutOfMemory do
      Result := nil;
  end;
end;

procedure BrotliFree(Block: Pointer); cdecl; public name 'moon_brotli_free';
begin
  FreeMem(Block);
end;

function BrotliCopy(Destination, Source: Pointer; Count: SizeUInt): Pointer; cdecl; public name 'moon_brotli_memcpy';
begin
  If Count <> 0 then
    Move(Source^, Destination^, Count);
  Result := Destination;
end;

function BrotliMove(Destination, Source: Pointer; Count: SizeUInt): Pointer; cdecl; public name 'moon_brotli_memmove';
begin
  Result := BrotliCopy(Destination, Source, Count);
end;

function BrotliFill(Destination: Pointer; Value: Integer; Count: SizeUInt): Pointer; cdecl; public name 'moon_brotli_memset';
begin
  If Count <> 0 then
    FillChar(Destination^, Count, Byte(Value));
  Result := Destination;
end;

function Allocate(Context: Pointer; Size: SizeUInt): Pointer; cdecl;
begin
  Result := BrotliMalloc(Size);
end;

procedure Release(Context, Block: Pointer); cdecl;
begin
  BrotliFree(Block);
end;

procedure BrotliDecompress(Source, Destination: TStream; EncodedSize: Int64);
var
  State: Pointer;
  Input, Output: array[0..65535] of Byte;
  AvailableIn, AvailableOut, BeforeIn: SizeUInt;
  NextIn, NextOut: PByte;
  Remaining: Int64;
  Count, Code, Error: Integer;
begin
  If (Source = nil) or (Destination = nil) or (EncodedSize < 0) then
    raise EArgumentException.Create('Invalid Brotli streams or encoded size');
  State := DecoderCreate(@Allocate, @Release, nil);
  If State = nil then
    raise EOutOfMemory.Create('Cannot allocate Brotli decoder');
  try
    Remaining := EncodedSize;
    AvailableIn := 0;
    NextIn := nil;
    repeat
      If (AvailableIn = 0) and (Remaining > 0) then begin
        Count := SizeOf(Input);
        If Remaining < Count then
          Count := Remaining;
        Count := Source.Read(Input, Count);
        If Count <= 0 then
          raise EBrotliError.Create('Truncated Brotli input');
        Dec(Remaining, Count);
        AvailableIn := Count;
        NextIn := @Input[0];
      end;
      BeforeIn := AvailableIn;
      NextOut := @Output[0];
      AvailableOut := SizeOf(Output);
      Code := DecoderRun(State, AvailableIn, NextIn, AvailableOut, NextOut, nil);
      Count := SizeOf(Output) - AvailableOut;
      If Count <> 0 then
        Destination.WriteBuffer(Output, Count);
      If Code = 1 then begin
        If (AvailableIn <> 0) or (Remaining <> 0) then
          raise EBrotliError.Create('Trailing data after Brotli stream');
        Exit;
      end;
      If Code = 0 then begin
        Error := DecoderError(State);
        If (Error >= -30) and (Error <= -21) then
          raise EOutOfMemory.Create('Cannot allocate Brotli decode buffers');
        raise EBrotliError.CreateFmt('Invalid Brotli stream (%d)', [Error]);
      end;
      If ((Code = 2) and (AvailableIn = 0) and (Remaining = 0)) or
        ((Count = 0) and (BeforeIn = AvailableIn)) then
        raise EBrotliError.Create('Truncated Brotli stream');
    until False;
  finally
    DecoderDestroy(State);
  end;
end;
end.
