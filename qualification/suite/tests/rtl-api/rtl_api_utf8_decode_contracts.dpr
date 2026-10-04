program rtl_api_utf8_decode_contracts;

{$ifdef FPC}
  {$mode delphiunicode}
  {$pointermath on}
{$endif}

uses
  {$ifdef MSWINDOWS}
  Windows,
  {$else}
  BaseUnix,
  {$endif}
  SysUtils;

procedure Check(OK: Boolean; const Name: UnicodeString);
begin
  If not OK then
    raise Exception.Create(Name);
end;

function Bytes(const Values: array of Byte): RawByteString;
var I: Integer;
begin
  SetLength(Result, Length(Values));
  for I := 0 to High(Values) do
    Result[I + 1] := AnsiChar(Values[I]);
end;

procedure CheckText(const Input: RawByteString; const Expected: UnicodeString);
begin
  Check(UTF8Decode(Input) = Expected, 'decoded UTF16 units');
end;

procedure CheckPairs;
var C1, C2: Integer;
    Input: RawByteString;
    Expected: UnicodeString;
begin
  for C1 := $80 to $7ff do
  begin
    C2 := $80 + ((C1 * 37) mod ($800 - $80));
    Input := Bytes([$c0 or (C1 shr 6), $80 or (C1 and $3f),
      $c0 or (C2 shr 6), $80 or (C2 and $3f)]);
    Expected := WideChar(C1) + WideChar(C2);
    CheckText(Input, Expected);
    CheckText('prefix ' + Input + ' suffix', 'prefix ' + Expected + ' suffix');
  end;
  CheckText(Bytes([0, 65, $d0, $b0, $e2, $82, $ac, $f0, $9f, $98, $80]),
    #0'A'#$430#$20ac#$d83d#$de00);
end;

{$ifdef FPC}
procedure CheckInvalid;
var Input: RawByteString;
    Output: array[0..7] of WideChar;
    Raised: Boolean;
begin
  CheckText(Bytes([$c0, $af]), #$fffd#$fffd);
  CheckText(Bytes([$e0, $80, $80]), #$fffd#$fffd);
  CheckText(Bytes([$ed, $a0, $80]), #$fffd#$fffd);
  CheckText(Bytes([$f4, $90, $80, $80]), #$fffd#$fffd#$fffd);
  CheckText(Bytes([$f0, $9f, $98]), #$fffd);
  CheckText(Bytes([$d0, $b0, $d1]), #$430#$fffd);
  Input := Bytes([$d0, $b0, $c0]);
  Raised := False;
  try
    Utf8ToUnicode(@Output[0], Length(Output), PAnsiChar(Input), Length(Input), False);
  except
    on E: EConvertError do
      Raised := True;
  end;
  Check(Raised, 'strict malformed conversion');
end;

function GuardMap: PByte;
{$ifdef MSWINDOWS}
var OldProtect: DWORD;
{$endif}
begin
  {$ifdef MSWINDOWS}
  Result := VirtualAlloc(nil, 8192, MEM_RESERVE or MEM_COMMIT, PAGE_READWRITE);
  Check(Result <> nil, 'guard allocation');
  Check(VirtualProtect(Result + 4096, 4096, PAGE_NOACCESS, OldProtect), 'guard protection');
  {$else}
  Result := fpMMap(nil, 8192, PROT_READ or PROT_WRITE, MAP_PRIVATE or MAP_ANONYMOUS, -1, 0);
  Check(Result <> Pointer(-1), 'guard allocation');
  Check(fpMProtect(Result + 4096, 4096, PROT_NONE) = 0, 'guard protection');
  {$endif}
end;

procedure ReleaseGuard(P: PByte);
begin
  {$ifdef MSWINDOWS}
  Check(VirtualFree(P, 0, MEM_RELEASE), 'guard release');
  {$else}
  Check(fpMUnmap(P, 8192) = 0, 'guard release');
  {$endif}
end;

procedure CheckBounds;
var SourceMap, DestMap, Source: PByte;
    Dest: PWideChar;
    N, Capacity, Written, ExpectedCount, I: Integer;
begin
  SourceMap := GuardMap;
  DestMap := GuardMap;
  try
    for N := 0 to 9 do
    begin
      Source := SourceMap + 4096 - N;
      for I := 0 to N - 1 do
        If I and 1 = 0 then
          Source[I] := $d0
        else
          Source[I] := $b0;
      ExpectedCount := (N + 1) div 2;
      Check(Utf8ToUnicode(nil, 0, PAnsiChar(Source), N, True) = SizeUInt(ExpectedCount + 1), 'count-only');
      for Capacity := 0 to 10 do
      begin
        Dest := PWideChar(DestMap + 4096 - Capacity * 2);
        FillChar(DestMap^, 4096, $55);
        Written := ExpectedCount;
        If Written > Capacity then
          Written := Capacity;
        Check(Utf8ToUnicode(Dest, Capacity, PAnsiChar(Source), N, True) = SizeUInt(Written + 1), 'bounded count');
        for I := 0 to Written - 1 do
          If (N and 1 <> 0) and (I = ExpectedCount - 1) then
            Check(Dest[I] = WideChar($fffd), 'truncated last lead')
          else
            Check(Dest[I] = WideChar($430), 'bounded content');
        If Written < Capacity then
          Check(Dest[Written] = #0, 'bounded terminator');
        Check(PWord(PByte(Dest) - 2)^ = $5555, 'no write before destination');
      end;
    end;
    Check(Utf8ToUnicode(PWideChar(DestMap + 4096), 0, nil, 9, True) = 0, 'nil source');
  finally
    ReleaseGuard(DestMap);
    ReleaseGuard(SourceMap);
  end;
end;
{$endif}

begin
  CheckPairs;
  {$ifdef FPC}
  CheckInvalid;
  CheckBounds;
  {$endif}
  Writeln('RTL_API_UTF8_DECODE_CONTRACTS_OK');
end.
