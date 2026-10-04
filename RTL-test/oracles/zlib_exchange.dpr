program zlib_exchange;

{ The exchange oracle of System.ZLib and System.Zip: what one build writes, the
  other reads.  The same source is built by Delphi 12.2 (dcc64, its RTL's
  System.ZLib and System.Zip) and by MoonCompiler with the product
  configuration (System.ZLib over the toolchain's zlib 1.3.1 objects,
  System.Zip over MoonORMot's mormot.core.zip, whose deflate is that same
  zlib).

    zlib_exchange write DIR   the payloads as zlib (three levels), raw deflate
                              and gzip files, and one ZIP archive holding them
                              (deflated, one stored, an empty entry, a name
                              outside ASCII)
    zlib_exchange read DIR    everything write puts there, inflated and
                              compared byte for byte with the payloads made
                              again here; the archive's entries are read with
                              their CRC checked

  Run write with one build and read with the other, in both directions; each
  side also reads its own files, and any third implementation (Python's zlib
  and zipfile, the system libz of a Linux server) can read the directory too.
  The payloads are made of integer arithmetic only, alike for every compiler.
  EXCHANGE_READ_PASS / EXCHANGE_WRITE_PASS with the counts, exit 1 on the first
  difference. }

{$ifndef FPC}
  {$APPTYPE CONSOLE}
{$endif}
{$ifdef FPC}
  {$mode delphi}{$H+}
{$endif}

uses
  SysUtils,
  Classes,
  System.ZLib,
  System.Zip;

type
  TPayload = record
    Name: string;
    Data: TBytes;
  end;

var
  Seed: UInt64;

function NextRandom: UInt64;
begin
  Seed := Seed xor (Seed shr 12);
  Seed := Seed xor (Seed shl 25);
  Seed := Seed xor (Seed shr 27);
  Result := Seed * UInt64($2545F4914F6CDD1D);
end;

procedure AddText(var Data: TBytes; var Size: Integer; const Text: AnsiString);
begin
  If Size + Length(Text) > Length(Data) then
    SetLength(Data, (Size + Length(Text)) * 2);
  If Text <> '' then
    Move(Text[1], Data[Size], Length(Text));
  Inc(Size, Length(Text));
end;

{ the kinds of data the product compresses: exchange messages (text with long
  repeats), trade records (binary, short repeats), noise (stored blocks),
  zeros (the longest matches, the whole window), the empty and one byte }
function Payloads: TArray<TPayload>;
var
  I, Size: Integer;
  Price, Qty: UInt64;
begin
  SetLength(Result, 6);
  Seed := $1D3779B97F4A7C15;
  Result[0].Name := 'messages';
  Size := 0;
  Price := 6543210;
  for I := 0 to 1499 do begin
    Price := Price + (NextRandom shr 61) - 3;
    Qty := 1 + NextRandom shr 50;
    AddText(Result[0].Data, Size, AnsiString('{"stream":"btcusdt@aggTrade","data":{"e":"aggTrade","E":' +
      IntToStr(1727524800000 + I * 37) + ',"s":"BTCUSDT","a":' + IntToStr(3120000000 + I) + ',"p":"' +
      IntToStr(Price div 100) + '.' + IntToStr(Price mod 100) + '","q":"0.' + IntToStr(Qty) + '","m":' +
      BoolToStr(Odd(NextRandom shr 40), True) + '}}'));
  end;
  SetLength(Result[0].Data, Size);
  Result[1].Name := 'trades';
  SetLength(Result[1].Data, 4608);
  for I := 0 to Length(Result[1].Data) div 16 - 1 do begin
    PUInt64(@Result[1].Data[I * 16])^ := UInt64($40E63F0000000000) + UInt64(I) * 1234567;
    PCardinal(@Result[1].Data[I * 16 + 8])^ := $47C35000 + Cardinal(NextRandom shr 56);
    PCardinal(@Result[1].Data[I * 16 + 12])^ := Cardinal(NextRandom shr 32);
  end;
  Result[2].Name := 'noise';
  SetLength(Result[2].Data, 100000);
  for I := 0 to High(Result[2].Data) do
    Result[2].Data[I] := Byte(NextRandom shr 56);
  Result[3].Name := 'zeros';
  SetLength(Result[3].Data, 300000);
  FillChar(Result[3].Data[0], Length(Result[3].Data), 0);
  Result[4].Name := 'empty';
  Result[5].Name := 'one';
  SetLength(Result[5].Data, 1);
  Result[5].Data[0] := $5A;
end;

procedure Fail(const What: string);
begin
  WriteLn('EXCHANGE_FAIL ', What);
  Halt(1);
end;

function SameBytes(const A, B: TBytes): Boolean;
begin
  Result := (Length(A) = Length(B)) and ((Length(A) = 0) or CompareMem(@A[0], @B[0], Length(A)));
end;

function FileBytes(const Name: string): TBytes;
var
  F: TFileStream;
begin
  F := TFileStream.Create(Name, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result, F.Size);
    If Length(Result) > 0 then
      F.ReadBuffer(Result[0], Length(Result));
  finally
    FreeAndNil(F);
  end;
end;

procedure SaveBytes(const Name: string; const Data: TBytes);
var
  F: TFileStream;
begin
  F := TFileStream.Create(Name, fmCreate);
  try
    If Length(Data) > 0 then
      F.WriteBuffer(Data[0], Length(Data));
  finally
    FreeAndNil(F);
  end;
end;

const
  LevelNames: array[TZCompressionLevel] of string = ('none', 'fastest', 'default', 'max');
  { an entry name outside ASCII, written by code so that no source code page is involved }
  UnicodeName = #$0434#$0430#$043D#$043D#$044B#$0435'/'#$0441#$043E#$043E#$0431#$0449#$0435#$043D#$0438#$044F'.json';

{ through TZCompressionStream with the window bits of the format: -15 raw, 15 zlib, 31 gzip }
function StreamDeflate(const Data: TBytes; WindowBits: Integer): TBytes;
var
  Target: TBytesStream;
  Z: TZCompressionStream;
begin
  Target := TBytesStream.Create;
  try
    Z := TZCompressionStream.Create(Target, zcDefault, WindowBits);
    try
      If Length(Data) > 0 then
        Z.WriteBuffer(Data[0], Length(Data));
    finally
      FreeAndNil(Z);
    end;
    Result := Copy(Target.Bytes, 0, Target.Size);
  finally
    FreeAndNil(Target);
  end;
end;

function StreamInflate(const Data: TBytes; WindowBits: Integer): TBytes;
var
  Source: TBytesStream;
  Target: TBytesStream;
  Z: TZDecompressionStream;
  Buffer: array[0..16383] of Byte;
  Got: Integer;
begin
  Source := TBytesStream.Create(Data);
  Target := TBytesStream.Create;
  try
    Z := TZDecompressionStream.Create(Source, WindowBits);
    try
      repeat
        Got := Z.Read(Buffer, SizeOf(Buffer));
        If Got > 0 then
          Target.WriteBuffer(Buffer, Got);
      until Got <= 0;
    finally
      FreeAndNil(Z);
    end;
    Result := Copy(Target.Bytes, 0, Target.Size);
  finally
    FreeAndNil(Target);
    FreeAndNil(Source);
  end;
end;

procedure WriteAll(const Dir: string);
var
  P: TPayload;
  Level: TZCompressionLevel;
  Squeezed: TBytes;
  Zip: TZipFile;
  Stream: TBytesStream;
  Files: Integer;
begin
  Files := 0;
  for P in Payloads do begin
    for Level := zcFastest to zcMax do begin
      ZCompress(P.Data, Squeezed, Level);
      SaveBytes(Dir + P.Name + '.' + LevelNames[Level] + '.zlib', Squeezed);
      Inc(Files);
    end;
    SaveBytes(Dir + P.Name + '.raw', StreamDeflate(P.Data, -15));
    SaveBytes(Dir + P.Name + '.gz', StreamDeflate(P.Data, 31));
    Inc(Files, 2);
  end;
  Zip := TZipFile.Create;
  try
    Zip.Open(Dir + 'archive.zip', zmWrite);
    for P in Payloads do begin
      Stream := TBytesStream.Create(P.Data);
      try
        Zip.Add(Stream, P.Name + '.bin', zcDeflate);
      finally
        FreeAndNil(Stream);
      end;
    end;
    Stream := TBytesStream.Create(Payloads[1].Data);
    try
      Zip.Add(Stream, 'stored/trades.bin', zcStored);
    finally
      FreeAndNil(Stream);
    end;
    Stream := TBytesStream.Create(Payloads[0].Data);
    try
      Zip.Add(Stream, UnicodeName, zcDeflate);
    finally
      FreeAndNil(Stream);
    end;
    Zip.Close;
  finally
    FreeAndNil(Zip);
  end;
  WriteLn('EXCHANGE_WRITE_PASS files=', Files + 1, ' entries=', Length(Payloads) + 2);
end;

procedure ReadAll(const Dir: string);
var
  P: TPayload;
  Level: TZCompressionLevel;
  Back: TBytes;
  Zip: TZipFile;
  Checked: Integer;

  procedure Expect(const Got: TBytes; const Want: TBytes; const What: string);
  begin
    If not SameBytes(Got, Want) then
      Fail(What + ': ' + IntToStr(Length(Got)) + ' bytes, want ' + IntToStr(Length(Want)));
    Inc(Checked);
  end;

  procedure Entry(const Name: string; const Want: TBytes);
  var
    Got: TBytes;
  begin
    If Zip.IndexOf(Name) < 0 then
      Fail('archive.zip has no ' + Name);
    Zip.Read(Name, Got);
    Expect(Got, Want, 'archive.zip ' + Name);
  end;

begin
  Checked := 0;
  for P in Payloads do begin
    for Level := zcFastest to zcMax do begin
      ZDecompress(FileBytes(Dir + P.Name + '.' + LevelNames[Level] + '.zlib'), Back);
      Expect(Back, P.Data, P.Name + '.' + LevelNames[Level] + '.zlib');
    end;
    Expect(StreamInflate(FileBytes(Dir + P.Name + '.raw'), -15), P.Data, P.Name + '.raw');
    Expect(StreamInflate(FileBytes(Dir + P.Name + '.gz'), 31), P.Data, P.Name + '.gz');
  end;
  Zip := TZipFile.Create;
  try
    Zip.Open(Dir + 'archive.zip', zmRead);
    If Zip.FileCount <> Length(Payloads) + 2 then
      Fail('archive.zip holds ' + IntToStr(Zip.FileCount) + ' entries');
    for P in Payloads do
      Entry(P.Name + '.bin', P.Data);
    Entry('stored/trades.bin', Payloads[1].Data);
    Entry(UnicodeName, Payloads[0].Data);
    Zip.Close;
  finally
    FreeAndNil(Zip);
  end;
  WriteLn('EXCHANGE_READ_PASS checked=', Checked, ' zlib=', string(zlibVersion));
end;

var
  Dir: string;
begin
  try
    If (ParamCount <> 2) or not (SameText(ParamStr(1), 'write') or SameText(ParamStr(1), 'read')) then begin
      WriteLn('usage: zlib_exchange write|read DIR');
      Halt(2);
    end;
    Dir := IncludeTrailingPathDelimiter(ParamStr(2));
    If SameText(ParamStr(1), 'write') then begin
      ForceDirectories(Dir);
      WriteAll(Dir);
    end else
      ReadAll(Dir);
  except
    on E: Exception do
      Fail(E.ClassName + ': ' + E.Message);
  end;
end.
