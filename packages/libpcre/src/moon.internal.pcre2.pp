{ Private PCRE2-16 binding to the pinned open-source engine in ../native.
  Declarations follow pcre2.h; no Delphi implementation is used. }
unit Moon.Internal.Pcre2;
{$mode objfpc}{$H+}
interface
uses ctypes;
{$i pcreconsts.inc}
const
  PCRE2_EXTRA_ASCII_BSD = $00000100;
  PCRE2_EXTRA_ASCII_BSS = $00000200;
  PCRE2_EXTRA_ASCII_BSW = $00000400;
type
  Psize_t = ^SizeUInt;
  PCRE2_SPTR = PWideChar;
  Ppcre2_code_16 = Pointer;
  ppcre2_match_data = Pointer;

function pcre2_compile_context_create(Context: Pointer): Pointer; cdecl;
  external name 'moon_pcre_pcre2_compile_context_create_16';
procedure pcre2_compile_context_free(Context: Pointer); cdecl;
  external name 'moon_pcre_pcre2_compile_context_free_16';
function pcre2_set_compile_extra_options(Context: Pointer; Options: UInt32): Integer; cdecl;
  external name 'moon_pcre_pcre2_set_compile_extra_options_16';
function pcre2_set_newline(Context: Pointer; Newline: UInt32): Integer; cdecl;
  external name 'moon_pcre_pcre2_set_newline_16';
function pcre2_compile_w(Pattern: PWideChar; Length: SizeUInt; Options: UInt32; ErrorCode: PInteger;
  ErrorOffset: PSizeUInt; Context: Pointer): Ppcre2_code_16; cdecl; external name 'moon_pcre_pcre2_compile_16';
procedure pcre2_code_free(Code: Ppcre2_code_16); cdecl; external name 'moon_pcre_pcre2_code_free_16';
function pcre2_pattern_info(Code: Ppcre2_code_16; What: UInt32; Where: Pointer): Integer; cdecl;
  external name 'moon_pcre_pcre2_pattern_info_16';
function pcre2_match_data_create_from_pattern(Code: Ppcre2_code_16; Context: Pointer): ppcre2_match_data; cdecl;
  external name 'moon_pcre_pcre2_match_data_create_from_pattern_16';
procedure pcre2_match_data_free(Data: ppcre2_match_data); cdecl; external name 'moon_pcre_pcre2_match_data_free_16';
function pcre2_match_w(Code: Ppcre2_code_16; Subject: PWideChar; Length, Start: SizeUInt; Options: UInt32;
  Data: ppcre2_match_data; Context: Pointer): Integer; cdecl; external name 'moon_pcre_pcre2_match_16';
function pcre2_get_ovector_pointer(Data: ppcre2_match_data): PSize_t; cdecl;
  external name 'moon_pcre_pcre2_get_ovector_pointer_16';
function pcre2_get_startchar(Data: ppcre2_match_data): SizeUInt; cdecl; external name 'moon_pcre_pcre2_get_startchar_16';
function pcre2_get_error_message(Code: Integer; Buffer: PWideChar; Capacity: SizeUInt): Integer; cdecl;
  external name 'moon_pcre_pcre2_get_error_message_16';
function pcre2_jit_compile(Code: Ppcre2_code_16; Options: UInt32): Integer; cdecl;
  external name 'moon_pcre_pcre2_jit_compile_16';

implementation
uses SysUtils;
{$linklib moonpcre2}
{$ifdef windows}
{$linklib moonpcre_os}
{$else}
{$linklib c}
{$linklib pthread}
{$endif}

function NativeMalloc(Size: SizeUInt): Pointer; cdecl; public name 'moon_pcre_malloc';
begin
  try
    Result := GetMem(Size);
  except
    on EOutOfMemory do
      Result := nil;
  end;
end;

procedure NativeFree(Block: Pointer); cdecl; public name 'moon_pcre_free';
begin
  FreeMem(Block);
end;

function NativeCopy(Destination, Source: Pointer; Count: SizeUInt): Pointer; cdecl; public name 'moon_pcre_memcpy';
begin
  if Count <> 0 then
    Move(Source^, Destination^, Count);
  Result := Destination;
end;

function NativeMove(Destination, Source: Pointer; Count: SizeUInt): Pointer; cdecl; public name 'moon_pcre_memmove';
begin
  Result := NativeCopy(Destination, Source, Count);
end;

function NativeFill(Destination: Pointer; Value: Integer; Count: SizeUInt): Pointer; cdecl; public name 'moon_pcre_memset';
begin
  if Count <> 0 then
    FillChar(Destination^, Count, Byte(Value));
  Result := Destination;
end;

function NativeCompare(Left, Right: PByte; Count: SizeUInt): Integer; cdecl; public name 'moon_pcre_memcmp';
begin
  while Count <> 0 do begin
    if Left^ <> Right^ then
      Exit(Integer(Left^) - Integer(Right^));
    Inc(Left);
    Inc(Right);
    Dec(Count);
  end;
  Result := 0;
end;

function NativeLength(Text: PAnsiChar): SizeUInt; cdecl; public name 'moon_pcre_strlen';
var
  Cursor: PAnsiChar;
begin
  Cursor := Text;
  while Cursor^ <> #0 do
    Inc(Cursor);
  Result := Cursor - Text;
end;

function NativeFind(Text: PAnsiChar; Value: Integer): PAnsiChar; cdecl; public name 'moon_pcre_strchr';
begin
  repeat
    if Byte(Text^) = Byte(Value) then
      Exit(Text);
    if Text^ = #0 then
      Exit(nil);
    Inc(Text);
  until False;
end;
end.
