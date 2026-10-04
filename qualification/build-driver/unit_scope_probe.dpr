program unit_scope_probe;

{ Delphi code names System.ZLib and System.Zip by their short names and lets
  the unit scope System find them (MoonBot's MoonTrades: `uses zLib`; the
  websocket client's FPC branch: `uses zlib`).  Built with the product
  configuration, this program has to reach the same units:
  TZDecompressionStream and TZipFile exist in no other unit of these names. }

uses
  SysUtils,
  Classes,
  zLib,
  Zip;

var
  Data, Back: TBytes;
  Source, Deflated, Inflated, Archive: TMemoryStream;
  Z: TZCompressionStream;
  D: TZDecompressionStream;
  ZipFile: TZipFile;
  I: Integer;
begin
  SetLength(Data, 10000);
  for I := 0 to High(Data) do
    Data[I] := Byte(I mod 7 + I div 100);
  Source := TMemoryStream.Create;
  Deflated := TMemoryStream.Create;
  Inflated := TMemoryStream.Create;
  Archive := TMemoryStream.Create;
  ZipFile := TZipFile.Create;
  try
    Source.WriteBuffer(Data[0], Length(Data));
    Z := TZCompressionStream.Create(Deflated, zcDefault, -15);
    try
      Z.CopyFrom(Source, 0);
    finally
      FreeAndNil(Z);
    end;
    Deflated.Position := 0;
    D := TZDecompressionStream.Create(Deflated, -15);
    try
      Inflated.CopyFrom(D, 0);
    finally
      FreeAndNil(D);
    end;
    If (Inflated.Size <> Length(Data)) or not CompareMem(Inflated.Memory, @Data[0], Length(Data)) then
      raise Exception.Create('the zlib round trip lost data');
    ZipFile.Open(Archive, zmWrite);
    Source.Position := 0;
    ZipFile.Add(Source, 'data.bin');
    ZipFile.Close;
    Archive.Position := 0;
    ZipFile.Open(Archive, zmRead);
    ZipFile.Read('data.bin', Back);
    ZipFile.Close;
    If (Length(Back) <> Length(Data)) or not CompareMem(@Back[0], @Data[0], Length(Data)) then
      raise Exception.Create('the zip round trip lost data');
    WriteLn('UNIT_SCOPE_PROBE_PASS zlib=', zlibVersion);
  finally
    FreeAndNil(ZipFile);
    FreeAndNil(Archive);
    FreeAndNil(Inflated);
    FreeAndNil(Deflated);
    FreeAndNil(Source);
  end;
end.
