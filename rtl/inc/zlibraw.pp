{
    This file is part of the Free Pascal run time library.
    Copyright (c) 2026 Moonbot

    Shared native zlib ABI and bounded DWARF section inflater.

    See COPYING.FPC for the license and static-linking exception.
    This program is distributed without any warranty; without even the
    implied warranty of merchantability or fitness for a particular purpose.
}
unit zlibraw;
{$mode fpc}{$modeswitch result}{$modeswitch exceptions}{$packrecords c}{$I-}
interface
type
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
    msg: PAnsiChar;
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


{ The caller positions the file at a complete zlib stream. Output is supplied
  by the caller; all input, output and checksum must match exactly. }
function InflateFile(var Source: File; InputSize: LongInt; Output: Pointer; OutputSize: LongInt): Boolean;
implementation
{$L moonzlib_adler32.o}
{$L moonzlib_crc32.o}
{$L moonzlib_inffast.o}
{$L moonzlib_inflate.o}
{$L moonzlib_inftrees.o}
{$L moonzlib_zutil.o}
function Init(var S: z_stream; V: PAnsiChar; Size: LongInt): LongInt; cdecl; external name 'moon_zlib_inflateInit_';
function Inflate(var S: z_stream; Flush: LongInt): LongInt; cdecl; external name 'moon_zlib_inflate';
function Done(var S: z_stream): LongInt; cdecl; external name 'moon_zlib_inflateEnd';
function Allocate(Opaque: Pointer; Items, Size: Cardinal): Pointer; cdecl;
begin
  Result:=GetMem(SizeUInt(Items)*Size);
end;
procedure Release(Opaque, Block: Pointer); cdecl;
begin
  FreeMem(Block);
end;
function InflateFile(var Source: File; InputSize: LongInt; Output: Pointer; OutputSize: LongInt): Boolean;
var
  S: z_stream;
  Buffer: array[0..16383] of Byte;
  N, Code: LongInt;
  Overflow: Byte;
begin
  Result:=False;
  FillChar(S,SizeOf(S),0);
  S.zalloc:=@Allocate;
  S.zfree:=@Release;
  S.next_out:=Output;
  S.avail_out:=OutputSize;
  if Init(S,'1.3.1',SizeOf(S))<>0 then exit;
  try
    repeat
      N:=InputSize;
      if N>SizeOf(Buffer) then N:=SizeOf(Buffer);
      if N<=0 then exit;
      BlockRead(Source,Buffer,N,Code);
      if (Code<>N) or (IOResult<>0) then exit;
      Dec(InputSize,N);
      S.next_in:=@Buffer;
      S.avail_in:=N;
      { The output can finish before the checksum arrives in the next input
        block. One scratch byte lets zlib consume that trailer while detecting
        any actual output beyond the advertised section size. }
      if S.avail_out=0 then
        begin
          S.next_out:=@Overflow;
          S.avail_out:=1;
        end;
      Code:=Inflate(S,0);
      if S.total_out>TZLong(OutputSize) then exit;
      if Code=1 then
        exit((InputSize=0) and (S.avail_in=0) and (S.total_out=TZLong(OutputSize)));
      if (Code<>0) or (S.avail_in<>0) then exit;
    until False;
  finally
    Done(S);
  end;
end;
end.
