{
    This file is part of the MoonCompiler runtime.
    Copyright (c) 2026 by the MoonCompiler contributors

    The Delphi System.Zip surface over mORMot's TZipRead/TZipWrite.

    Provenance: written for MoonCompiler from the behavioural contract in the
    planning document "DELPHI_SURFACE_ADDITIONS_20260920" (section 3.2),
    PKWARE APPNOTE 6.3.10 and the MoonBot compatibility unit
    MoonBot.Compat.Zip it replaces (stream classes ported from there).  No
    Embarcadero source, interface text or documentation excerpt was consulted
    or copied.  Author: MoonCompiler team, 2026-09-21.

    The unit lives in runtime/mormot and is compiled into each project against
    the project's own mORMot (rule 0.2 of the planning document): the
    container - central directory, ZIP64, names, local headers, writing - is
    mormot.core.zip's; deflate is mormot.lib.z, which under MoonCompiler goes
    through System.ZLib (MOONCOMPILER_SYSTEM_ZLIB), the one zlib of the
    program; CRC-32 is libdeflate's on Linux.  This unit adds the Delphi
    shape: TZipFile with owned entry streams read on demand straight from the
    archive, TZipHeader per APPNOTE, the EZip* exceptions, ExtractAll that
    refuses names leaving the directory.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}
unit System.Zip;

{$mode delphi}
{$H+}

interface

uses
  SysUtils,
  Classes,
  mormot.core.os,
  mormot.core.zip;

type
  { the compression method field of APPNOTE 4.4.5; Stored and Deflate are
    implemented, every other value raises EZipException when used }
  TZipCompression = (
    zcStored = 0, zcShrunk, zcReduce1, zcReduce2, zcReduce3, zcReduce4,
    zcImplode, zcTokenize, zcDeflate, zcDeflate64, zcPKImplode,
    zcBZIP2 = 12, zcLZMA = 14, zcTERSE = 18, zcLZ77, zcWavePack = 97, zcPPMdI1);

  TZipMode = (zmClosed, zmRead, zmReadWrite, zmWrite);

  { the central directory header of APPNOTE 4.3.12 without its signature,
    field for field; the variable parts follow as byte arrays }
  TZipHeader = packed record
  private
    function GetModifiedTime: TDateTime;
    function GetUTF8Support: Boolean;
    function GetUseDataDescriptor: Boolean;
    function GetIsEncrypted: Boolean;
  public
    MadeByVersion: UInt16;
    RequiredVersion: UInt16;
    Flag: UInt16;
    CompressionMethod: UInt16;
    ModifiedDateTime: UInt32;
    CRC32: UInt32;
    CompressedSize: UInt32;
    UncompressedSize: UInt32;
    FileNameLength: UInt16;
    ExtraFieldLength: UInt16;
    FileCommentLength: UInt16;
    DiskNumberStart: UInt16;
    InternalAttributes: UInt16;
    ExternalAttributes: UInt32;
    LocalHeaderOffset: UInt32;
    FileName: TBytes;
    ExtraField: TBytes;
    FileComment: TBytes;
    { the real sizes and offset, also for entries beyond 4 GB (ZIP64) }
    UncompressedSize64: UInt64;
    CompressedSize64: UInt64;
    LocalHeaderOffset64: UInt64;
    property ModifiedTime: TDateTime read GetModifiedTime;
    property UTF8Support: Boolean read GetUTF8Support;              { bit 11 }
    property UseDataDescriptor: Boolean read GetUseDataDescriptor;  { bit 3 }
    property IsEncrypted: Boolean read GetIsEncrypted;              { bit 0 }
  end;

  EZipException = class(Exception);
  EZipCRCException = class(EZipException);
  EZipFileNotFoundException = class(EZipException)
  private
    FFileName: string;
  public
    constructor Create(const AFileName: string);
    property FileName: string read FFileName;
  end;

  TZipProgressEvent = procedure(Sender: TObject; FileName: string; Header: TZipHeader; Position: Int64) of object;

  { Open(zmRead) on a file maps the archive; on a memory stream it works on
    the stream's memory from its position; on any other stream the archive is
    copied once.  Read gives a stream owned by the caller that inflates the
    entry on demand from the archive (no copy of the entry); with CheckCrc
    the CRC is checked on the last byte.  Add writes through
    mormot.core.zip, the central directory is written at Close. }
  TZipFile = class
  private
    FMode: TZipMode;
    FReader: TZipRead;
    FWriter: TZipWrite;
    FMap: TMemoryMap;
    FMapped: Boolean;
    FArchiveData: PByte;
    FArchiveSize: Int64;
    FSourceBuffer: RawByteString;
    FNames: TArray<string>;
    FHeaders: array of TZipHeader;
    FOnProgress: TZipProgressEvent;
    procedure OpenReader(Data: Pointer; Size: PtrInt);
    procedure LoadEntries;
    procedure RequireRead;
    procedure RequireWrite;
    function CreateEntrySource(Index: Integer): TStream;
    function GetFileCount: Integer;
    function GetFileNames: TArray<string>;
    function IndexOrRaise(const FileName: string): Integer;
    procedure DoProgress(const AFileName: string; const Header: TZipHeader; Position: Int64);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Open(const ZipFileName: string; OpenMode: TZipMode); overload;
    procedure Open(ZipFileStream: TStream; OpenMode: TZipMode); overload;
    procedure Close;
    procedure ExtractAll(const Path: string = '');
    procedure Read(const FileName: string; out Stream: TStream; out LocalHeader: TZipHeader; CheckCrc: Boolean = False); overload;
    procedure Read(Index: Integer; out Stream: TStream; out LocalHeader: TZipHeader; CheckCrc: Boolean = False); overload;
    procedure Read(const FileName: string; out Bytes: TBytes); overload;
    procedure Read(Index: Integer; out Bytes: TBytes); overload;
    procedure Add(Data: TStream; const ArchiveFileName: string; Compression: TZipCompression = zcDeflate);
    function IndexOf(const FileName: string): Integer;
    property Mode: TZipMode read FMode;
    property FileCount: Integer read GetFileCount;
    property FileNames: TArray<string> read GetFileNames;
    property OnProgress: TZipProgressEvent read FOnProgress write FOnProgress;
  end;

implementation

uses
  {$ifdef UNIX}BaseUnix,{$endif}
  mormot.lib.z,
  MoonORMot.Need;

const
  ZipBufferSize = 64 * 1024;

resourcestring
  SZipNotOpen = 'The archive is not open';
  SZipNotReadable = 'The archive is not open for reading';
  SZipNotWritable = 'The archive is not open for writing';
  SZipEmptyStream = 'The stream holds no archive';
  SZipCannotMap = 'Cannot open the archive %s';
  SZipIndexRange = 'Entry index %d is out of range';
  SZipUnsupportedMethod = 'Compression method %d is not supported';
  SZipEncrypted = 'Entry %s is encrypted';
  SZipEmptyName = 'An entry needs a name';
  SZipFileNotFound = 'Entry not found in the archive: %s';
  SZipCRC = 'CRC mismatch in entry %s: expected %.8x, read %.8x';
  SZipTruncated = 'Entry %s ends before its data does';
  SZipInvalidMode = 'Invalid open mode';
  SZipEscapes = 'Entry %s would leave the extraction directory';
  SZipSymlink = 'Cannot create symbolic link %s';
  SZipEntryInfo = 'Cannot read the information of entry %d';

{ ---------------------------------------------------------------------
  TZipHeader
  ---------------------------------------------------------------------}

function TZipHeader.GetModifiedTime: TDateTime;
var
  Date, Time: UInt32;
  D: TDateTime;
begin
  Date := ModifiedDateTime shr 16;
  Time := ModifiedDateTime and $FFFF;
  Result := 0;
  If TryEncodeDate(1980 + (Date shr 9), (Date shr 5) and 15, Date and 31, D) then
    Result := D;
  If TryEncodeTime(Time shr 11, (Time shr 5) and 63, (Time and 31) * 2, 0, D) then
    Result := Result + D;
end;

function TZipHeader.GetUTF8Support: Boolean;
begin
  Result := (Flag and (1 shl 11)) <> 0;
end;

function TZipHeader.GetUseDataDescriptor: Boolean;
begin
  Result := (Flag and (1 shl 3)) <> 0;
end;

function TZipHeader.GetIsEncrypted: Boolean;
begin
  Result := (Flag and 1) <> 0;
end;

{ ---------------------------------------------------------------------
  entry streams (ported from MoonBot.Compat.Zip)
  ---------------------------------------------------------------------}

type
  { the compressed bytes of one entry: a window on the archive in memory }
  TZipEntrySourceStream = class(TStream)
  private
    FData: PByte;
    FSize, FPosition: Int64;
  protected
    function GetSize: Int64; override;
  public
    constructor Create(Data: Pointer; Size: Int64);
    function Read(var Buffer; Count: Longint): Longint; override;
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; override;
    function Write(const Buffer; Count: Longint): Longint; override;
  end;

  { the entry's data, inflated on demand; a seek backwards restarts }
  TZipEntryReadStream = class(TStream)
  private
    FSource: TStream;
    FInflater: TZLib;
    FInflaterInitialized: Boolean;
    FStored: Boolean;
    FFinished: Boolean;
    FSize, FPosition: Int64;
    FInput: array[0..ZipBufferSize - 1] of Byte;
    FInputEnded: Boolean;
    FName: string;
    procedure Reset;
  protected
    function GetSize: Int64; override;
  public
    constructor Create(var Source: TStream; CompressionMethod: Word; UncompressedSize: Int64; const Name: string);
    destructor Destroy; override;
    function Read(var Buffer; Count: Longint): Longint; override;
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; override;
    function Write(const Buffer; Count: Longint): Longint; override;
  end;

  { checks the CRC of what passed through when the last byte is read }
  TZipCRCReadStream = class(TStream)
  private
    FSource: TStream;
    FExpectedCRC, FCRC: UInt32;
    FSize, FPosition: Int64;
    FName: string;
  protected
    function GetSize: Int64; override;
  public
    constructor Create(var Source: TStream; ExpectedCRC: UInt32; Size: Int64; const Name: string);
    destructor Destroy; override;
    function Read(var Buffer; Count: Longint): Longint; override;
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; override;
    function Write(const Buffer; Count: Longint): Longint; override;
  end;

constructor TZipEntrySourceStream.Create(Data: Pointer; Size: Int64);
begin
  inherited Create;
  FData := Data;
  FSize := Size;
end;

function TZipEntrySourceStream.GetSize: Int64;
begin
  Result := FSize;
end;

function TZipEntrySourceStream.Read(var Buffer; Count: Longint): Longint;
var
  Remaining: Int64;
begin
  Remaining := FSize - FPosition;
  If Remaining <= 0 then
    Exit(0);
  If Count > Remaining then
    Count := Remaining;
  Move(FData[FPosition], Buffer, Count);
  Inc(FPosition, Count);
  Result := Count;
end;

function TZipEntrySourceStream.Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;
var
  Target: Int64;
begin
  Target := -1;
  case Origin of
    soBeginning: Target := Offset;
    soCurrent: Target := FPosition + Offset;
    soEnd: Target := FSize + Offset;
  end;
  If (Target < 0) or (Target > FSize) then
    raise EStreamError.Create('ZIP entry seek is outside the entry');
  FPosition := Target;
  Result := FPosition;
end;

function TZipEntrySourceStream.Write(const Buffer; Count: Longint): Longint;
begin
  Result := 0;
  raise EStreamError.Create('ZIP entry stream is read-only');
end;

constructor TZipEntryReadStream.Create(var Source: TStream; CompressionMethod: Word; UncompressedSize: Int64;
  const Name: string);
begin
  inherited Create;
  FSource := Source;
  Source := nil;
  FStored := CompressionMethod = Z_STORED;
  If not FStored and (CompressionMethod <> Z_DEFLATED) then
    raise EZipException.CreateFmt(SZipUnsupportedMethod, [CompressionMethod]);
  FSize := UncompressedSize;
  FName := Name;
  Reset;
end;

destructor TZipEntryReadStream.Destroy;
begin
  If FInflaterInitialized then
    FInflater.UncompressEnd;
  FreeAndNil(FSource);
  inherited Destroy;
end;

procedure TZipEntryReadStream.Reset;
begin
  If FInflaterInitialized then begin
    FInflater.UncompressEnd;
    FInflaterInitialized := False;
  end;
  FSource.Position := 0;
  FPosition := 0;
  FFinished := FStored and (FSize = 0);
  FInputEnded := False;
  If not FStored then begin
    FInflater.Init(nil, nil, 0, 0);
    If not FInflater.UncompressInit(False) then
      raise EZipException.Create('Could not initialize the ZIP inflater');
    FInflaterInitialized := True;
  end;
end;

function TZipEntryReadStream.GetSize: Int64;
begin
  Result := FSize;
end;

function TZipEntryReadStream.Read(var Buffer; Count: Longint): Longint;
var
  Code: Integer;
  InputCount: Longint;
  OutputBefore, Produced: Cardinal;
  Extra: Byte;
begin
  If (Count <= 0) or FFinished then
    Exit(0);
  If Count > FSize - FPosition then
    Count := FSize - FPosition;
  If FStored then begin
    Result := FSource.Read(Buffer, Count);
    Inc(FPosition, Result);
    FFinished := FPosition = FSize;
    Exit;
  end;
  Result := 0;
  while ((Result < Count) or (FPosition = FSize)) and not FFinished do begin
    If (FInflater.Stream.avail_in = 0) and not FInputEnded then begin
      InputCount := FSource.Read(FInput[0], Length(FInput));
      FInputEnded := InputCount = 0;
      FInflater.Stream.next_in := Pointer(@FInput[0]);
      FInflater.Stream.avail_in := InputCount;
    end;
    If FPosition = FSize then begin
      { Reaching the announced size does not finish the deflate stream.
        Let zlib consume its end marker; one extra output byte is an error. }
      FInflater.Stream.next_out := Pointer(@Extra);
      FInflater.Stream.avail_out := 1;
    end else begin
      FInflater.Stream.next_out := Pointer(PByte(@Buffer) + Result);
      FInflater.Stream.avail_out := Count - Result;
    end;
    OutputBefore := FInflater.Stream.avail_out;
    Code := FInflater.Uncompress(Z_NO_FLUSH);
    Produced := OutputBefore - FInflater.Stream.avail_out;
    If Produced > FSize - FPosition then
      raise EZipException.CreateFmt('ZIP entry %s exceeds its declared size', [FName]);
    Inc(Result, Produced);
    Inc(FPosition, Produced);
    If Code = Z_STREAM_END then
      FFinished := True
    else If (Code <> Z_OK) and not ((Code = Z_BUF_ERROR) and (Produced > 0)) then
      raise EZipException.CreateFmt('ZIP inflate failed for %s: %d', [FName, Code]);
    If (Produced = 0) and (FInflater.Stream.avail_in = 0) and FInputEnded and not FFinished then
      raise EZipException.CreateFmt(SZipTruncated, [FName]);
  end;
  If FFinished and (FPosition <> FSize) then
    raise EZipException.CreateFmt('ZIP entry %s: expected %d bytes, inflated %d', [FName, FSize, FPosition]);
end;

function TZipEntryReadStream.Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;
var
  Target: Int64;
  Skip: array[0..8191] of Byte;
  ToRead: Longint;
begin
  Target := -1;
  case Origin of
    soBeginning: Target := Offset;
    soCurrent: Target := FPosition + Offset;
    soEnd: Target := FSize + Offset;
  end;
  If (Target < 0) or (Target > FSize) then
    raise EStreamError.Create('ZIP seek is outside the uncompressed entry');
  If Target < FPosition then
    Reset;
  while FPosition < Target do begin
    ToRead := SizeOf(Skip);
    If ToRead > Target - FPosition then
      ToRead := Target - FPosition;
    If Read(Skip[0], ToRead) <> ToRead then
      raise EStreamError.Create('Could not seek within the ZIP entry');
  end;
  Result := FPosition;
end;

function TZipEntryReadStream.Write(const Buffer; Count: Longint): Longint;
begin
  Result := 0;
  raise EStreamError.Create('ZIP entry stream is read-only');
end;

constructor TZipCRCReadStream.Create(var Source: TStream; ExpectedCRC: UInt32; Size: Int64; const Name: string);
begin
  inherited Create;
  FSource := Source;
  Source := nil;
  FExpectedCRC := ExpectedCRC;
  FSize := Size;
  FName := Name;
end;

destructor TZipCRCReadStream.Destroy;
begin
  FreeAndNil(FSource);
  inherited Destroy;
end;

function TZipCRCReadStream.GetSize: Int64;
begin
  Result := FSize;
end;

function TZipCRCReadStream.Read(var Buffer; Count: Longint): Longint;
begin
  Result := FSource.Read(Buffer, Count);
  If Result > 0 then begin
    FCRC := mormot.lib.z.crc32(FCRC, @Buffer, Result);
    Inc(FPosition, Result);
  end;
  If (FPosition = FSize) and (FCRC <> FExpectedCRC) then
    raise EZipCRCException.CreateFmt(SZipCRC, [FName, FExpectedCRC, FCRC]);
end;

function TZipCRCReadStream.Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;
var
  Target: Int64;
  Skip: array[0..8191] of Byte;
  ToRead: Longint;
begin
  Target := -1;
  case Origin of
    soBeginning: Target := Offset;
    soCurrent: Target := FPosition + Offset;
    soEnd: Target := FSize + Offset;
  end;
  If (Target < 0) or (Target > FSize) then
    raise EStreamError.Create('ZIP seek is outside the entry');
  If Target < FPosition then begin
    FSource.Position := 0;
    FCRC := 0;
    FPosition := 0;
  end;
  while FPosition < Target do begin
    ToRead := SizeOf(Skip);
    If ToRead > Target - FPosition then
      ToRead := Target - FPosition;
    If Read(Skip[0], ToRead) <> ToRead then
      raise EStreamError.Create('Could not seek within the ZIP entry');
  end;
  Result := FPosition;
end;

function TZipCRCReadStream.Write(const Buffer; Count: Longint): Longint;
begin
  Result := 0;
  raise EStreamError.Create('ZIP entry stream is read-only');
end;

{ ---------------------------------------------------------------------
  TZipFile
  ---------------------------------------------------------------------}

constructor EZipFileNotFoundException.Create(const AFileName: string);
begin
  FFileName := AFileName;
  inherited CreateFmt(SZipFileNotFound, [AFileName]);
end;

constructor TZipFile.Create;
begin
  inherited Create;
  FMode := zmClosed;
end;

destructor TZipFile.Destroy;
begin
  Close;
  inherited Destroy;
end;

procedure TZipFile.Close;
begin
  FreeAndNil(FReader);
  { mORMot truncates handle streams itself. Other streams can retain an old
    tail; trim it before mORMot appends the central directory. }
  If (FWriter <> nil) and not (FWriter.Dest is THandleStream) then
    FWriter.Dest.Size := FWriter.Dest.Position;
  FreeAndNil(FWriter);           { writes the central directory }
  If FMapped then begin
    FMap.UnMap;
    FMapped := False;
  end;
  FArchiveData := nil;
  FArchiveSize := 0;
  FSourceBuffer := '';
  FNames := nil;
  FHeaders := nil;
  FMode := zmClosed;
end;

procedure TZipFile.RequireRead;
begin
  If FMode = zmClosed then
    raise EZipException.Create(SZipNotOpen);
  If (FMode = zmWrite) or (FReader = nil) then
    raise EZipException.Create(SZipNotReadable);
end;

procedure TZipFile.RequireWrite;
begin
  If FMode = zmClosed then
    raise EZipException.Create(SZipNotOpen);
  If (FMode = zmRead) or (FWriter = nil) then
    raise EZipException.Create(SZipNotWritable);
end;

procedure TZipFile.DoProgress(const AFileName: string; const Header: TZipHeader; Position: Int64);
begin
  If Assigned(FOnProgress) then
    FOnProgress(Self, AFileName, Header, Position);
end;

{ the central directory as mormot.core.zip parsed it, in the APPNOTE shape }
procedure TZipFile.LoadEntries;
var
  I: Integer;
  E: PZipReadEntry;
  H: TZipHeader;
begin
  SetLength(FNames, FReader.Count);
  SetLength(FHeaders, FReader.Count);
  for I := 0 to FReader.Count - 1 do begin
    E := @FReader.Entry[I];
    FNames[I] := E^.zipName;
    H := Default(TZipHeader);
    H.MadeByVersion := E^.dir^.madeBy;
    H.RequiredVersion := E^.dir^.fileInfo.neededVersion;
    H.Flag := E^.dir^.fileInfo.flags;
    H.CompressionMethod := E^.dir^.fileInfo.zzipMethod;
    H.ModifiedDateTime := E^.dir^.fileInfo.zlastMod;
    H.CRC32 := E^.dir^.fileInfo.zcrc32;
    H.CompressedSize := E^.dir^.fileInfo.zzipSize;
    H.UncompressedSize := E^.dir^.fileInfo.zfullSize;
    H.FileNameLength := E^.dir^.fileInfo.nameLen;
    H.ExtraFieldLength := E^.dir^.fileInfo.extraLen;
    H.FileCommentLength := E^.dir^.commentLen;
    H.DiskNumberStart := E^.dir^.firstDiskNo;
    H.InternalAttributes := E^.dir^.intFileAttr;
    H.ExternalAttributes := E^.dir^.extFileAttr;
    H.LocalHeaderOffset := E^.dir^.localHeadOff;
    SetLength(H.FileName, H.FileNameLength);
    If H.FileNameLength > 0 then
      Move(E^.storedName^, H.FileName[0], H.FileNameLength);
    SetLength(H.ExtraField, H.ExtraFieldLength);
    If H.ExtraFieldLength > 0 then
      Move(PByte(E^.storedName)[H.FileNameLength], H.ExtraField[0], H.ExtraFieldLength);
    SetLength(H.FileComment, H.FileCommentLength);
    If H.FileCommentLength > 0 then
      Move(PByte(E^.storedName)[H.FileNameLength + H.ExtraFieldLength], H.FileComment[0], H.FileCommentLength);
    H.CompressedSize64 := E^.fileinfo.zzipSize;
    H.UncompressedSize64 := E^.fileinfo.zfullSize;
    H.LocalHeaderOffset64 := E^.fileinfo.offset;
    FHeaders[I] := H;
  end;
end;

{ the archive in memory: mormot.core.zip parses it, its errors become
  EZipException }
procedure TZipFile.OpenReader(Data: Pointer; Size: PtrInt);
begin
  FArchiveData := Data;
  FArchiveSize := Size;
  try
    FReader := TZipRead.Create(Data, Size);
  except
    on E: ESynZip do
      raise EZipException.Create(E.Message);
  end;
  LoadEntries;
end;

procedure TZipFile.Open(const ZipFileName: string; OpenMode: TZipMode);
begin
  Close;
  try
    case OpenMode of
      zmRead, zmReadWrite:
        begin
          If not FMap.Map(ZipFileName) then
            raise EZipException.CreateFmt(SZipCannotMap, [ZipFileName]);
          FMapped := True;
          OpenReader(FMap.Buffer, FMap.Size);
          If OpenMode = zmReadWrite then
            try
              { keeps the entries, appends behind them; the map stays valid
                for their local headers and data }
              FWriter := TZipWrite.CreateFrom(ZipFileName);
            except
              on E: ESynZip do
                raise EZipException.Create(E.Message);
            end;
        end;
      zmWrite:
        FWriter := TZipWrite.Create(ZipFileName);
    else
      raise EZipException.Create(SZipInvalidMode);
    end;
    FMode := OpenMode;
  except
    Close;
    raise;
  end;
end;

procedure TZipFile.Open(ZipFileStream: TStream; OpenMode: TZipMode);
var
  Remaining: Int64;
begin
  Close;
  If ZipFileStream = nil then
    raise EZipException.Create(SZipEmptyStream);
  try
    case OpenMode of
      zmRead:
        begin
          Remaining := ZipFileStream.Size - ZipFileStream.Position;
          If Remaining <= 0 then
            raise EZipException.Create(SZipEmptyStream);
          If ZipFileStream is TCustomMemoryStream then
            { the archive is the stream's memory from its position }
            OpenReader(PByte(TCustomMemoryStream(ZipFileStream).Memory) + ZipFileStream.Position, PtrInt(Remaining))
          else begin
            { any other stream: one copy of the archive }
            If Remaining > High(PtrInt) then
              raise EZipException.Create('The archive is too large for memory');
            SetLength(FSourceBuffer, PtrInt(Remaining));
            ZipFileStream.ReadBuffer(Pointer(FSourceBuffer)^, PtrInt(Remaining));
            OpenReader(Pointer(FSourceBuffer), PtrInt(Remaining));
          end;
        end;
      zmWrite:
        FWriter := TZipWrite.CreateAppend(ZipFileStream);
    else
      { zmReadWrite on a stream is not supported by mormot.core.zip }
      raise EZipException.Create(SZipInvalidMode);
    end;
    FMode := OpenMode;
  except
    Close;
    raise;
  end;
end;

function TZipFile.GetFileCount: Integer;
begin
  If FMode = zmClosed then
    raise EZipException.Create(SZipNotOpen);
  Result := Length(FNames);
end;

function TZipFile.GetFileNames: TArray<string>;
begin
  If FMode = zmClosed then
    raise EZipException.Create(SZipNotOpen);
  Result := Copy(FNames);
end;

function TZipFile.IndexOf(const FileName: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FNames) do
    If SameText(FNames[I], FileName) then
      Exit(I);
  Result := -1;
end;

function TZipFile.IndexOrRaise(const FileName: string): Integer;
begin
  Result := IndexOf(FileName);
  If Result < 0 then
    raise EZipFileNotFoundException.Create(FileName);
end;

{ the compressed bytes of the entry: behind its local header in the archive,
  and inside it }
function TZipFile.CreateEntrySource(Index: Integer): TStream;
var
  Local: TLocalFileHeader;
  DataOffset: Int64;
begin
  If not FReader.RetrieveLocalFileHeader(Index, Local) then
    raise EZipException.CreateFmt(SZipEntryInfo, [Index]);
  DataOffset := Int64(FReader.Entry[Index].fileinfo.offset) + Local.Size;
  If (DataOffset < 0) or (DataOffset > FArchiveSize) or
     (FHeaders[Index].CompressedSize64 > UInt64(FArchiveSize - DataOffset)) then
    raise EZipException.CreateFmt(SZipTruncated, [FNames[Index]]);
  Result := TZipEntrySourceStream.Create(FArchiveData + DataOffset, FHeaders[Index].CompressedSize64);
end;

procedure TZipFile.Read(Index: Integer; out Stream: TStream; out LocalHeader: TZipHeader; CheckCrc: Boolean);
var
  Source: TStream;
begin
  Stream := nil;
  RequireRead;
  If (Index < 0) or (Index > High(FHeaders)) then
    raise EZipException.CreateFmt(SZipIndexRange, [Index]);
  LocalHeader := FHeaders[Index];
  If LocalHeader.IsEncrypted then
    raise EZipException.CreateFmt(SZipEncrypted, [FNames[Index]]);
  { a stored entry's two sizes are the same span of bytes; a shorter
    compressed size would otherwise end the read early and look like EOF }
  If (LocalHeader.CompressionMethod = Z_STORED) and
     (LocalHeader.CompressedSize64 <> LocalHeader.UncompressedSize64) then
    raise EZipException.CreateFmt(SZipTruncated, [FNames[Index]]);
  Source := CreateEntrySource(Index);
  try
    Source := TZipEntryReadStream.Create(Source, LocalHeader.CompressionMethod, LocalHeader.UncompressedSize64, FNames[Index]);
    If CheckCrc then
      Source := TZipCRCReadStream.Create(Source, LocalHeader.CRC32, LocalHeader.UncompressedSize64, FNames[Index]);
    Stream := Source;
    Source := nil;
  finally
    Source.Free;
  end;
end;

procedure TZipFile.Read(const FileName: string; out Stream: TStream; out LocalHeader: TZipHeader; CheckCrc: Boolean);
begin
  RequireRead;
  Read(IndexOrRaise(FileName), Stream, LocalHeader, CheckCrc);
end;

procedure TZipFile.Read(Index: Integer; out Bytes: TBytes);
var
  Input: TStream;
  Header: TZipHeader;
  Empty: Byte;
begin
  Read(Index, Input, Header, True);
  try
    If Input.Size > High(Integer) then
      raise EZipException.Create('The entry does not fit in TBytes');
    SetLength(Bytes, Input.Size);
    If Length(Bytes) > 0 then
      Input.ReadBuffer(Bytes[0], Length(Bytes))
    else
      Input.Read(Empty, 1);  { an empty entry still has a deflate end and a CRC }
  finally
    Input.Free;
  end;
end;

procedure TZipFile.Read(const FileName: string; out Bytes: TBytes);
begin
  RequireRead;
  Read(IndexOrRaise(FileName), Bytes);
end;

{ the entry name as a relative path of this file system; a name that could
  leave the extraction directory - an absolute path, a drive or stream
  colon on Windows, a ".." component - is refused rather than "repaired" }
function LocalEntryPath(const Name: string): string;
var
  I, Start: Integer;
  Escapes: Boolean;
  {$ifdef MSWINDOWS}
  Component: string;
  Dot: Integer;
  {$endif}
begin
  Result := Name;
  {$ifdef MSWINDOWS}
  Result := StringReplace(Result, '\', '/', [rfReplaceAll]);
  Escapes := Pos(':', Result) > 0;
  {$else}
  Escapes := False;
  {$endif}
  Escapes := Escapes or ((Result <> '') and (Result[1] = '/'));
  Start := 1;
  for I := 1 to Length(Result) + 1 do
    If (I > Length(Result)) or (Result[I] = '/') then begin
      If (I - Start = 2) and (Result[Start] = '.') and (Result[Start + 1] = '.') then
        Escapes := True;
      {$ifdef MSWINDOWS}
      { Win32 strips a trailing dot/space and resolves DOS device names even
        with an extension, so those names cannot become ordinary files. }
      If (I > Start) and not ((I - Start = 1) and (Result[Start] = '.')) then begin
        If (Result[I - 1] = '.') or (Result[I - 1] = ' ') then
          Escapes := True;
        Component := UpperCase(Copy(Result, Start, I - Start));
        Dot := Pos('.', Component);
        If Dot > 0 then
          SetLength(Component, Dot - 1);
        If (Component = 'NUL') or (Component = 'CON') or (Component = 'PRN') or (Component = 'AUX') or
           ((Length(Component) = 4) and ((Copy(Component, 1, 3) = 'COM') or (Copy(Component, 1, 3) = 'LPT')) and
            (((Component[4] >= '1') and (Component[4] <= '9')) or
             (Component[4] = #$B9) or (Component[4] = #$B2) or (Component[4] = #$B3))) then
          Escapes := True;
      end;
      {$endif}
      Start := I + 1;
    end;
  If Escapes then
    raise EZipException.CreateFmt(SZipEscapes, [Name]);
  If PathDelim <> '/' then
    Result := StringReplace(Result, '/', PathDelim, [rfReplaceAll]);
end;

{ every entry into Path; the names are checked before anything is written,
  so an archive with one escaping name extracts nothing }
procedure TZipFile.ExtractAll(const Path: string);
var
  I: Integer;
  Name, Target, Dir: string;
  Targets: TArray<string>;
  Stream: TStream;
  Header: TZipHeader;
  F: TFileStream;
  Buf: array[0..ZipBufferSize - 1] of Byte;
  Got: Longint;
  {$ifdef UNIX}
  Link: TBytes;
  Mode: UInt32;
  {$endif}
begin
  RequireRead;
  Dir := Path;
  If Dir <> '' then
    Dir := IncludeTrailingPathDelimiter(Dir);
  SetLength(Targets, Length(FNames));
  for I := 0 to High(FNames) do
    If FNames[I] <> '' then
      Targets[I] := Dir + LocalEntryPath(FNames[I]);
  {$ifdef UNIX}
  { a symbolic link is an escaping name written as data: "../x" or "/abs"
    is refused before any file of this archive is created }
  for I := 0 to High(FHeaders) do begin
    Mode := FHeaders[I].ExternalAttributes shr 16;
    If (FNames[I] <> '') and ((FHeaders[I].MadeByVersion shr 8) = 3) and ((Mode and $F000) = $A000) then begin
      Read(I, Link);
      If Length(Link) = 0 then
        raise EZipException.CreateFmt(SZipEscapes, [FNames[I]]);
      LocalEntryPath(TEncoding.UTF8.GetString(Link));
    end;
  end;
  {$endif}
  for I := 0 to High(FHeaders) do begin
    Name := FNames[I];
    Target := Targets[I];
    If Name = '' then
      Continue;
    If Name[Length(Name)] = '/' then begin
      ForceDirectories(Target);
      Continue;
    end;
    ForceDirectories(ExtractFileDir(Target));
    {$ifdef UNIX}
    Mode := FHeaders[I].ExternalAttributes shr 16;
    If ((FHeaders[I].MadeByVersion shr 8) = 3) and ((Mode and $F000) = $A000) then begin
      Read(I, Link);
      DeleteFile(Target);
      If fpSymlink(PAnsiChar(TEncoding.UTF8.GetAnsiString(Link)), PAnsiChar(UTF8Encode(Target))) <> 0 then
        raise EZipException.CreateFmt(SZipSymlink, [Target]);
      DoProgress(Name, FHeaders[I], Length(Link));
      Continue;
    end;
    {$endif}
    Read(I, Stream, Header, True);
    try
      F := TFileStream.Create(Target, fmCreate);
      try
        try
          repeat
            Got := Stream.Read(Buf, SizeOf(Buf));
            If Got > 0 then
              F.WriteBuffer(Buf, Got);
          until Got <= 0;
        finally
          F.Free;
        end;
      except
        DeleteFile(Target);
        raise;
      end;
      FileSetDateFromWindowsTime(Target, FHeaders[I].ModifiedDateTime);
      DoProgress(Name, FHeaders[I], Stream.Size);
    finally
      Stream.Free;
    end;
  end;
end;

procedure TZipFile.Add(Data: TStream; const ArchiveFileName: string; Compression: TZipCompression);
var
  Remaining: Int64;
  Output: TStream;
  Buffer: TMemoryStream;
  N: Integer;
  H: TZipHeader;
begin
  RequireWrite;
  If ArchiveFileName = '' then
    raise EZipException.Create(SZipEmptyName);
  If not (Compression in [zcStored, zcDeflate]) then
    raise EZipException.CreateFmt(SZipUnsupportedMethod, [Ord(Compression)]);
  If Data <> nil then
    Remaining := Data.Size - Data.Position
  else
    Remaining := 0;
  If Remaining < 0 then
    Remaining := 0;
  If Remaining > High(UInt32) then
    FWriter.ForceZip64 := True;
  If Compression = zcDeflate then begin
    Output := FWriter.AddDeflatedStream(ArchiveFileName);
    try
      If Remaining > 0 then
        Output.CopyFrom(Data, Remaining);
    finally
      Output.Free;                  { finishes the entry }
    end;
  end else If (Data is TCustomMemoryStream) or (Remaining = 0) then begin
    If Remaining = 0 then
      FWriter.AddStored(ArchiveFileName, nil, 0)
    else begin
      FWriter.AddStored(ArchiveFileName, PByte(TCustomMemoryStream(Data).Memory) + Data.Position, Remaining);
      Data.Position := Data.Size;
    end;
  end else begin
    Buffer := TMemoryStream.Create;
    try
      Buffer.CopyFrom(Data, Remaining);
      FWriter.AddStored(ArchiveFileName, Buffer.Memory, Buffer.Size);
    finally
      Buffer.Free;
    end;
  end;
  { the entry as this object lists it until Close; the archive itself gets
    its header from mormot.core.zip }
  N := Length(FNames);
  SetLength(FNames, N + 1);
  SetLength(FHeaders, N + 1);
  FNames[N] := ArchiveFileName;
  H := Default(TZipHeader);
  H.CompressionMethod := Ord(Compression);
  H.UncompressedSize64 := UInt64(Remaining);
  If Remaining <= High(UInt32) then
    H.UncompressedSize := UInt32(Remaining)
  else
    H.UncompressedSize := $FFFFFFFF;
  FHeaders[N] := H;
  DoProgress(ArchiveFileName, H, Remaining);
end;

end.
