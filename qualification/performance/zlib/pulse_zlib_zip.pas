unit pulse_zlib_zip;

{ The ZIP forms of the product (MoonBot) through System.Zip: a market's data
  zipped into an archive in memory as TMarket.StoreToZipInternal does it, and
  the archive read back as TMarkets.ReStoreFromStream does it.  Under
  MoonCompiler System.Zip is the unit of runtime/mormot over mormot.core.zip
  (its deflate is mormot.lib.z, that is System.ZLib's zlib), under Delphi the
  System.Zip of its RTL. }

{$ifdef FPC}
  {$mode delphi}{$H+}
{$endif}

{$Q-}{$R-}

interface

uses
  Classes;

{ TZipFile.Open(Target, zmWrite), Add(Source, the market's name, zcDeflate),
  Free: the archive in Target; its size. }
function ZipAddTo(Source, Target: TMemoryStream): Int64;

{ The same into a new TMemoryStream, freed after. }
function ZipAdd(Source: TMemoryStream): Int64;

{ TZipFile.Open(Archive, zmRead), Read(the market's name, Stream, Header),
  CopyFrom(Stream, 0) into a new TMemoryStream; the size read, Digest over it. }
function ZipRead(Archive: TMemoryStream; out Digest: UInt64): Int64;

{ What ZipRead reads, into Target (for the check before the measurement). }
procedure ZipReadTo(Archive, Target: TMemoryStream);

implementation

uses
  SysUtils,
  System.Zip;

const
  EntryName = 'BTCUSDT';

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

function ZipAddTo(Source, Target: TMemoryStream): Int64;
var
  Zip: TZipFile;
begin
  Zip := TZipFile.Create;
  try
    Zip.Open(Target, zmWrite);
    Source.Position := 0;
    Zip.Add(Source, EntryName, zcDeflate);
  finally
    FreeAndNil(Zip);
  end;
  Result := Target.Size;
end;

function ZipAdd(Source: TMemoryStream): Int64;
var
  Target: TMemoryStream;
begin
  Target := TMemoryStream.Create;
  try
    Result := ZipAddTo(Source, Target);
  finally
    FreeAndNil(Target);
  end;
end;

procedure ZipReadTo(Archive, Target: TMemoryStream);
var
  Zip: TZipFile;
  Entry: TStream;
  Header: TZipHeader;
begin
  Zip := TZipFile.Create;
  try
    Archive.Position := 0;
    Zip.Open(Archive, zmRead);
    Zip.Read(EntryName, Entry, Header);
    try
      Target.CopyFrom(Entry, 0);
    finally
      FreeAndNil(Entry);
    end;
  finally
    FreeAndNil(Zip);
  end;
end;

function ZipRead(Archive: TMemoryStream; out Digest: UInt64): Int64;
var
  Target: TMemoryStream;
begin
  Target := TMemoryStream.Create;
  try
    ZipReadTo(Archive, Target);
    Result := Target.Size;
    Digest := Digest64(Target.Memory, Target.Size);
  finally
    FreeAndNil(Target);
  end;
end;

end.
