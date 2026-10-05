program zip_contract;
{$mode delphi}{$H+}{$codepage utf8}

{ System.Zip over mormot.core.zip (planning contract 3.2).  Oracles: an
  archive written by an independent implementation (Python's zipfile,
  embedded below as bytes) is read entry by entry with its known sizes, CRCs,
  times and names; archives written here are read back and checked against
  APPNOTE's layout (signatures, sizes, central directory and end record); a
  CRC damaged on purpose is caught; a hand-made ZIP64 central directory yields
  the 64-bit sizes; names that would leave the extraction directory are
  refused. }

uses
  {$ifdef UNIX}cthreads, cwstring, BaseUnix,{$endif}
  SysUtils,
  Classes,
  System.ZLib,
  System.Zip;

{$I zip_fixture.inc}

var
  Failures: Integer;
  Dir: string;

procedure Check(Cond: Boolean; const Msg: string);
begin
  If not Cond then begin
    Inc(Failures);
    WriteLn('FAIL ', Msg);
  end;
end;

function Pattern(Size, Seed: Integer): TBytes;
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, Size);
  for I := 0 to Size - 1 do
    Result[I] := Byte((I * 7 + Seed) xor (I shr 6));
end;

function SameBytes(const A, B: TBytes): Boolean;
begin
  Result := (Length(A) = Length(B)) and ((Length(A) = 0) or CompareMem(@A[0], @B[0], Length(A)));
end;

function U32(const B: TBytes; Ofs: Integer): Cardinal;
begin
  Result := B[Ofs] or (B[Ofs + 1] shl 8) or (B[Ofs + 2] shl 16) or (Cardinal(B[Ofs + 3]) shl 24);
end;

function U16(const B: TBytes; Ofs: Integer): Word;
begin
  Result := B[Ofs] or (B[Ofs + 1] shl 8);
end;

{ 1. the independent archive }
procedure ReadForeignArchive;
var
  M: TMemoryStream;
  Z: TZipFile;
  S: TStream;
  H: TZipHeader;
  B: TBytes;
  Y, Mo, D, Hh, Mi, Ss, Ms: Word;
  Expected: TBytes;
  I: Integer;
begin
  M := TMemoryStream.Create;
  Z := TZipFile.Create;
  try
    Check(Z.Mode = zmClosed, 'new TZipFile is closed');
    Check(Z.IndexOf('x') = -1, 'IndexOf on a closed archive is -1');
    try
      Z.FileCount;
      Check(False, 'FileCount on a closed archive accepted');
    except
      on EZipException do ;
    end;
    { the archive behind other bytes: the base is the stream position }
    I := $11223344;
    M.WriteBuffer(I, 4);
    M.WriteBuffer(PythonArchive[0], Length(PythonArchive));
    M.Position := 4;
    Z.Open(M, zmRead);
    Check(Z.Mode = zmRead, 'mode after Open');
    Check(Z.FileCount = 4, 'four entries: ' + IntToStr(Z.FileCount));
    Check((Z.FileNames[0] = 'stored.txt') and (Z.FileNames[1] = 'dir/deflated.bin') and
          (Z.FileNames[2] = #$043F#$0440#$0438#$0432#$0435#$0442'.txt') and (Z.FileNames[3] = 'empty.txt'),
      'names, the third one UTF-8 by bit 11: ' + Z.FileNames[2]);
    Check(Z.IndexOf('DIR/Deflated.BIN') = 1, 'IndexOf ignores case');
    Check(Z.IndexOf('nothing') = -1, 'IndexOf of an absent name');
    { stored entry as a stream }
    Z.Read('stored.txt', S, H, True);
    try
      Check(H.CompressionMethod = 0, 'stored method');
      Check(H.UncompressedSize64 = 17, 'stored size from the local header');
      Check(H.CRC32 = 4070280875, 'stored CRC');
      Check(TEncoding.UTF8.GetString(H.FileName) = 'stored.txt', 'local header name');
      DecodeDate(H.ModifiedTime, Y, Mo, D);
      DecodeTime(H.ModifiedTime, Hh, Mi, Ss, Ms);
      Check((Y = 2024) and (Mo = 5) and (D = 6) and (Hh = 7) and (Mi = 8) and (Ss = 10), 'DOS time of the entry');
      S.Position := 0;
      Check(S.Size = 17, 'entry stream size');
      SetLength(B, 17);
      S.ReadBuffer(B[0], 17);
      Check(TEncoding.ASCII.GetString(B) = 'stored bytes here', 'stored content');
      Check(S.Read(B[0], 1) = 0, 'nothing behind the entry');
    finally
      S.Free;
    end;
    { deflated entry via CopyFrom of exactly its size, index form }
    Z.Read(1, S, H, False);
    try
      Check(H.CompressionMethod = 8, 'deflate method');
      Check(H.UncompressedSize64 = 5000, 'deflated size');
      Check(H.CompressedSize64 = 318, 'compressed size');
      M.Position := 0;   { irrelevant: the entry stream keeps its own place }
      with TMemoryStream.Create do
        try
          CopyFrom(S, H.UncompressedSize64);
          Expected := Pattern(0, 0);
          SetLength(Expected, 5000);
          for I := 0 to 4999 do
            Expected[I] := Byte(I * 7);
          Check((Size = 5000) and CompareMem(Memory, @Expected[0], 5000), 'deflated content through CopyFrom');
        finally
          Free;
        end;
      Check(S.Position = 5000, 'position at the end');
      S.Position := 100;
      S.ReadBuffer(B[0], 10);
      Check(B[0] = (100 * 7) and $FF, 'seek back inside a deflated entry');
    finally
      S.Free;
    end;
    { whole entries }
    Z.Read(#$043F#$0440#$0438#$0432#$0435#$0442'.txt', B);
    Check(TEncoding.UTF8.GetString(B) = 'utf-8 name', 'UTF-8 named entry content');
    Z.Read('empty.txt', B);
    Check(Length(B) = 0, 'empty entry');
    try
      Z.Read('missing.txt', B);
      Check(False, 'missing entry accepted');
    except
      on E: EZipFileNotFoundException do
        Check(E.FileName = 'missing.txt', 'EZipFileNotFoundException.FileName');
    end;
    try
      Z.Read(7, B);
      Check(False, 'index 7 accepted');
    except
      on EZipException do ;
    end;
    Z.Close;
    Check(Z.Mode = zmClosed, 'closed again');
    Check(M.Size = 4 + Length(PythonArchive), 'a read-only open does not touch the stream');
  finally
    Z.Free;
    M.Free;
  end;
end;

{ 2. write, read back, check the layout }
type
  TProgressLog = class
    Calls: Integer;
    LastName: string;
    LastPosition: Int64;
    procedure OnProgress(Sender: TObject; FileName: string; Header: TZipHeader; Position: Int64);
  end;

procedure TProgressLog.OnProgress(Sender: TObject; FileName: string; Header: TZipHeader; Position: Int64);
begin
  Inc(Calls);
  LastName := FileName;
  LastPosition := Position;
end;

procedure WriteAndReadBack;
var
  Z: TZipFile;
  Src: TMemoryStream;
  Big, Small, Back: TBytes;
  FileName: string;
  Archive: TBytes;
  F: TFileStream;
  Log: TProgressLog;
  S: TStream;
  H: TZipHeader;
  Eocd, Cd: Integer;
  Names: TArray<string>;
begin
  FileName := Dir + 'written.zip';
  Big := Pattern(300000, 3);
  Small := TEncoding.UTF8.GetBytes('small text');
  Log := TProgressLog.Create;
  Z := TZipFile.Create;
  Src := TMemoryStream.Create;
  try
    Z.OnProgress := Log.OnProgress;
    Z.Open(FileName, zmWrite);
    Check(Z.Mode = zmWrite, 'zmWrite');
    Check(Z.FileCount = 0, 'no entries yet');
    Src.WriteBuffer(Big[0], Length(Big));
    Src.Position := 1000;                                  { from the position }
    Z.Add(Src, 'data/big.bin');
    Check(Src.Position = Src.Size, 'Add read the source to its end');
    Check(Log.Calls >= 1, 'progress after the entry');
    Check((Log.LastName = 'data/big.bin') and (Log.LastPosition = Length(Big) - 1000), 'final progress with the size');
    Src.Clear;
    Src.WriteBuffer(Small[0], Length(Small));
    Src.Position := 0;
    Z.Add(Src, #$0424#$0430#$0439#$043B'.txt', zcStored);
    Z.Add(nil, 'empty.txt');
    Z.Add(nil, 'dir/', zcStored);
    try
      Z.Add(nil, '');
      Check(False, 'empty name accepted');
    except
      on EZipException do ;
    end;
    try
      Z.Add(nil, 'x.bz2', zcBZIP2);
      Check(False, 'bzip2 accepted');
    except
      on EZipException do ;
    end;
    Check(Z.FileCount = 4, 'entries counted before Close');
    try
      Z.Read(0, Back);
      Check(False, 'Read in zmWrite accepted');
    except
      on EZipException do ;
    end;
    Z.Close;
    { the layout }
    F := TFileStream.Create(FileName, fmOpenRead);
    try
      SetLength(Archive, F.Size);
      F.ReadBuffer(Archive[0], F.Size);
    finally
      F.Free;
    end;
    Check(U32(Archive, 0) = $04034B50, 'starts with a local header');
    Check(U16(Archive, 8) = 8, 'first entry deflated');
    Check((U32(Archive, 22) = Length(Big) - 1000) or (U16(Archive, 6) and 8 <> 0), 'uncompressed size in the local header or a data descriptor');
    Check((U32(Archive, 14) = crc32(0, @Big[1000], Length(Big) - 1000)) or (U16(Archive, 6) and 8 <> 0), 'CRC in the local header or a data descriptor');
    Eocd := Length(Archive) - 22;
    Check(U32(Archive, Eocd) = $06054B50, 'ends with the end record');
    Check(U16(Archive, Eocd + 10) = 4, 'entry count in the end record');
    Cd := U32(Archive, Eocd + 16);
    Check(U32(Archive, Cd) = $02014B50, 'central directory where the end record says');
    Check(U32(Archive, Eocd + 12) = Eocd - Cd, 'central directory size');
    Check(U32(Archive, Cd + 42) = 0, 'first central entry points at offset 0');
    Check(U16(Archive, Cd + 4) and $FF >= 20, 'version needed >= 2.0');
    { read back }
    Z.Open(FileName, zmRead);
    Names := Z.FileNames;
    Check((Length(Names) = 4) and (Names[0] = 'data/big.bin') and (Names[1] = #$0424#$0430#$0439#$043B'.txt') and
          (Names[2] = 'empty.txt') and (Names[3] = 'dir/'), 'names read back');
    Z.Read('data/big.bin', Back);
    Check((Length(Back) = Length(Big) - 1000) and CompareMem(@Back[0], @Big[1000], Length(Back)), 'big entry read back');
    Z.Read(1, S, H, True);
    try
      Log.Calls := 0;
      Check((H.CompressionMethod = 0) and (H.UncompressedSize64 = Length(Small)), 'stored entry header');
      Check(H.UTF8Support, 'non-ASCII name flagged UTF-8 (bit 11)');
      SetLength(Back, Length(Small));
      S.ReadBuffer(Back[0], Length(Back));
      Check(SameBytes(Back, Small), 'stored entry content');
      Check((Log.Calls = 1) and (Log.LastPosition = Length(Back)), 'returned stream read progress');
    finally
      S.Free;
    end;
    Z.Read('empty.txt', Back);
    Check(Length(Back) = 0, 'empty entry read back');
    Check((Log.LastName = 'empty.txt') and (Log.LastPosition = 0), 'empty entry completion progress');
    Z.Read(0, S, H, False);
    S.Free;
    Check(Abs(Now - H.ModifiedTime) < 1, 'ModifiedTime is the time of writing');
    Z.Close;
    { append in zmReadWrite: the old central directory is overwritten }
    Z.Open(FileName, zmReadWrite);
    Check(Z.FileCount = 4, 'existing entries seen in zmReadWrite');
    Src.Position := 0;
    Z.Add(Src, 'appended.txt');
    Z.Close;
    Z.Open(FileName, zmRead);
    Check(Z.FileCount = 5, 'appended entry counted');
    Z.Read('appended.txt', Back);
    Check(SameBytes(Back, Small), 'appended entry content');
    Z.Read('data/big.bin', Back);
    Check(Length(Back) = Length(Big) - 1000, 'old entry intact after append');
    Z.Close;
  finally
    Src.Free;
    Z.Free;
    Log.Free;
  end;
end;

{ 3. damaged CRC and truncated archive }

procedure Damage;
var
  Z: TZipFile;
  M: TMemoryStream;
  B: TBytes;
  S: TStream;
  H: TZipHeader;
  Buf: array[0..63] of Byte;
  Got: Integer;
begin
  M := TMemoryStream.Create;
  Z := TZipFile.Create;
  try
    M.WriteBuffer(PythonArchive[0], Length(PythonArchive));
    { flip one byte of the stored entry's data: the local header is 30+10
      bytes, the data starts at 40 }
    PByte(M.Memory)[40] := PByte(M.Memory)[40] xor $FF;
    M.Position := 0;
    Z.Open(M, zmRead);
    try
      Z.Read('stored.txt', B);
      Check(False, 'damaged entry read without a CRC error');
    except
      on EZipCRCException do ;
    end;
    Z.Read('stored.txt', S, H, True);
    try
      Got := 0;
      try
        Got := S.Read(Buf, 5);       { the first bytes come through }
        Check(Got = 5, 'partial read before the CRC is known');
        S.Read(Buf, 64);             { the last byte raises }
        Check(False, 'CRC not checked on the last byte');
      except
        on EZipCRCException do ;
      end;
    finally
      S.Free;
    end;
    Z.Read('stored.txt', S, H, False);
    try
      Check(S.Read(Buf, 64) = 17, 'without CheckCrc the damaged bytes are returned');
    finally
      S.Free;
    end;
    Z.Close;
    { truncated: the end record is missing }
    M.Size := M.Size - 30;
    M.Position := 0;
    try
      Z.Open(M, zmRead);
      Check(False, 'truncated archive opened');
    except
      on EZipException do ;
    end;
    { empty stream }
    M.Clear;
    try
      Z.Open(M, zmRead);
      Check(False, 'empty stream opened for reading');
    except
      on EZipException do ;
    end;
    { an entry flagged encrypted (bit 0 in the central directory) is refused }
    M.Clear;
    M.WriteBuffer(PythonArchive[0], Length(PythonArchive));
    { the central directory of stored.txt starts at 518 (Python: EOCD at
      753, cd offset 518); its flag field is at +8 }
    PByte(M.Memory)[518 + 8] := PByte(M.Memory)[518 + 8] or 1;
    M.Position := 0;
    Z.Open(M, zmRead);
    try
      Z.Read('stored.txt', B);
      Check(False, 'encrypted entry read');
    except
      on E: EZipException do
        Check(Pos('encrypted', E.Message) > 0, 'encrypted entry message: ' + E.Message);
    end;
    Z.Read('empty.txt', B);
    Check(Length(B) = 0, 'other entries still readable');
    Z.Close;
    { a compressed size beyond the archive is refused, not read past it }
    M.Clear;
    M.WriteBuffer(PythonArchive[0], Length(PythonArchive));
    { the central entry of dir/deflated.bin is at 574, its compressed size
      field at +20 }
    PCardinal(PByte(M.Memory) + 594)^ := $7FFFFFF0;
    M.Position := 0;
    try
      Z.Open(M, zmRead);
      Z.Read('dir/deflated.bin', B);
      Check(False, 'entry data beyond the archive read');
    except
      on EZipException do ;
    end;
    Z.Close;
    { a local header offset beyond the archive is refused at Open, not
      followed into memory that is not the archive }
    M.Clear;
    M.WriteBuffer(PythonArchive[0], Length(PythonArchive));
    { the central entry of dir/deflated.bin is at 574, its local header
      offset field at +42 }
    PCardinal(PByte(M.Memory) + 574 + 42)^ := $7FFFFFF0;
    M.Position := 0;
    try
      Z.Open(M, zmRead);
      Z.Read('dir/deflated.bin', B);
      Check(False, 'local header beyond the archive followed');
    except
      on EZipException do ;
      on E: Exception do
        Check(False, 'local header beyond the archive raised ' + E.ClassName + ': ' + E.Message);
    end;
    Z.Close;
    { a stored entry whose central-directory uncompressed size is larger than
      the bytes actually stored: that used to come back as a short successful
      read (ReadBuffer then raised EReadError, ExtractAll wrote the stump
      and stopped).  It is a truncated entry. }
    M.Clear;
    M.WriteBuffer(PythonArchive[0], Length(PythonArchive));
    PCardinal(PByte(M.Memory) + 518 + 24)^ := 100;
    M.Position := 0;
    Z.Open(M, zmRead);
    try
      Z.Read('stored.txt', B);
      Check(False, 'short stored entry returned ' + IntToStr(Length(B)) + ' bytes');
    except
      on E: EZipException do
        Check(Pos('stored.txt', E.Message) > 0, 'short stored entry names itself: ' + E.Message);
      on E: Exception do
        Check(False, 'short stored entry: ' + E.ClassName + ': ' + E.Message);
    end;
    Z.Close;
  finally
    Z.Free;
    M.Free;
  end;
end;

{ 3b. names that would leave the extraction directory are refused, and
  nothing of such an archive is extracted }
procedure Escapes;
const
  Bad: array[0..3] of string = ('../evil.txt', 'a/../../evil.txt', '/abs.txt', 'x/..');
var
  Z: TZipFile;
  I: Integer;
  Target: string;
begin
  Target := Dir + 'escape' + PathDelim;
  Z := TZipFile.Create;
  try
    for I := 0 to High(Bad) do
    begin
      Z.Open(Dir + 'escape.zip', zmWrite);
      Z.Add(nil, 'ok.txt');
      Z.Add(nil, Bad[I]);
      Z.Close;
      Z.Open(Dir + 'escape.zip', zmRead);
      Check(Z.FileCount = 2, 'an escaping name is stored as it is');
      try
        Z.ExtractAll(Target);
        Check(False, 'extracted ' + Bad[I]);
      except
        on EZipException do ;
      end;
      Z.Close;
      Check(not FileExists(Dir + 'evil.txt') and not FileExists(Dir + 'escape' + PathDelim + 'evil.txt'), 'no file written for ' + Bad[I]);
      { the names are checked before anything is written }
      Check(not FileExists(Target + 'ok.txt'), 'nothing extracted from the archive with ' + Bad[I]);
    end;
    Z.Open(Dir + 'escape.zip', zmWrite);
    Z.Add(nil, 'a/b/../c.txt');       { .. in the middle is an escape too }
    Z.Close;
    Z.Open(Dir + 'escape.zip', zmRead);
    try
      Z.ExtractAll(Target);
      Check(False, 'extracted a/b/../c.txt');
    except
      on EZipException do ;
    end;
    Z.Close;
  finally
    Z.Free;
  end;
end;

{$ifdef UNIX}
{ the central-directory host and mode of one entry: UNIX + S_IFLNK }
procedure MarkUnixSymlink(const FileName, EntryName: string);
var
  F: TFileStream;
  B: TBytes;
  I, NameLen: Integer;
  Name: AnsiString;
begin
  F := TFileStream.Create(FileName, fmOpenReadWrite);
  try
    SetLength(B, F.Size);
    If Length(B) > 0 then
      F.ReadBuffer(B[0], Length(B));
    I := 0;
    while I <= Length(B) - 46 do begin
      If (B[I] = $50) and (B[I + 1] = $4B) and (B[I + 2] = 1) and (B[I + 3] = 2) then begin
        NameLen := B[I + 28] or (B[I + 29] shl 8);
        If (NameLen = Length(EntryName)) and (I + 46 + NameLen <= Length(B)) then begin
          SetString(Name, PAnsiChar(@B[I + 46]), NameLen);
          If Name = EntryName then begin
            PWord(@B[I + 4])^ := (PWord(@B[I + 4])^ and $00FF) or $0300;
            PCardinal(@B[I + 38])^ := Cardinal($A1FF) shl 16;
            F.Position := 0;
            F.WriteBuffer(B[0], Length(B));
            Exit;
          end;
        end;
      end;
      Inc(I);
    end;
  finally
    F.Free;
  end;
  Check(False, 'central header of ' + EntryName + ' not found');
end;

{ a symlink is a path stored as the entry's bytes; "../" and an absolute
  target are the same escape as a bad entry name, and nothing is written }
procedure SymlinkTargets;
var
  Z: TZipFile;
  Src: TMemoryStream;
  Target, LinkPath: string;
  Buf: array[0..255] of AnsiChar;
  N: cInt;
  Payload: RawByteString;
begin
  Target := Dir + 'symlink' + PathDelim;
  ForceDirectories(Target);
  Z := TZipFile.Create;
  Src := TMemoryStream.Create;
  try
    Payload := '../outside.txt';
    Src.WriteBuffer(Payload[1], Length(Payload));
    Src.Position := 0;
    Z.Open(Dir + 'symlink.zip', zmWrite);
    Z.Add(Src, 'link', zcStored);
    Z.Add(nil, 'ok.txt');
    Z.Close;
    MarkUnixSymlink(Dir + 'symlink.zip', 'link');
    Z.Open(Dir + 'symlink.zip', zmRead);
    try
      Z.ExtractAll(Target);
      Check(False, 'extracted a symlink to ../outside.txt');
    except
      on EZipException do ;
    end;
    Z.Close;
    Check(not FileExists(Target + 'ok.txt'), 'nothing written when the symlink target escapes');
    Check(not FileExists(Dir + 'outside.txt'), 'symlink target was not created outside');
    { a relative target inside the tree is a real link }
    Src.Clear;
    Payload := 'ok.txt';
    Src.WriteBuffer(Payload[1], Length(Payload));
    Src.Position := 0;
    Z.Open(Dir + 'symlink.zip', zmWrite);
    Z.Add(Src, 'link', zcStored);
    Src.Clear;
    Payload := 'inside';
    Src.WriteBuffer(Payload[1], Length(Payload));
    Src.Position := 0;
    Z.Add(Src, 'ok.txt', zcStored);
    Z.Close;
    MarkUnixSymlink(Dir + 'symlink.zip', 'link');
    Z.Open(Dir + 'symlink.zip', zmRead);
    Z.ExtractAll(Target);
    Z.Close;
    LinkPath := Target + 'link';
    FillChar(Buf, SizeOf(Buf), 0);
    Payload := UTF8Encode(LinkPath);
    N := fpReadLink(PAnsiChar(Payload), @Buf[0], SizeOf(Buf) - 1);
    Check((N = Length('ok.txt')) and (Copy(string(Buf), 1, N) = 'ok.txt'),
      'symlink points at ok.txt, readlink ' + IntToStr(N));
  finally
    Src.Free;
    Z.Free;
  end;
end;
{$endif}

{ 4. ZIP64 by metadata: a hand-made archive whose central directory marks
  the sizes and the offset as $FFFFFFFF and carries them in the 0x0001 extra
  field, whose end record marks everything as overflowed and points at the
  ZIP64 end record through the locator.  The entry is read: only a parser
  that follows the whole chain gets to its three bytes. }
procedure Zip64Metadata;
var
  Z: TZipFile;
  M: TMemoryStream;
  H: TZipHeader;
  S: TStream;
  B: TBytes;
  Name: TBytes;
  Local, Central, Extra, Z64, Loc, Eocd: TBytes;
  CdStart, Z64Pos: Int64;
  procedure P16(var B: TBytes; O: Integer; V: Word); begin B[O] := V and $FF; B[O + 1] := V shr 8; end;
  procedure P32(var B: TBytes; O: Integer; V: Cardinal); begin P16(B, O, V and $FFFF); P16(B, O + 2, V shr 16); end;
  procedure P64(var B: TBytes; O: Integer; V: UInt64); begin P32(B, O, Cardinal(V)); P32(B, O + 4, Cardinal(V shr 32)); end;
  procedure Put(const B: TBytes); begin M.WriteBuffer(B[0], Length(B)); end;
begin
  M := TMemoryStream.Create;
  Z := TZipFile.Create;
  try
    SetLength(B, 4);
    FillChar(B[0], 4, $EE);
    Put(B);                                         { the archive starts at 4 }
    Name := TEncoding.ASCII.GetBytes('abc.txt');
    SetLength(Local, 30);
    P32(Local, 0, $04034B50); P16(Local, 4, 45); P16(Local, 6, 0); P16(Local, 8, 0); P32(Local, 10, 0);
    P32(Local, 14, $352441C2);                      { CRC-32 of "abc" }
    P32(Local, 18, 3); P32(Local, 22, 3); P16(Local, 26, Length(Name)); P16(Local, 28, 0);
    Put(Local); Put(Name);
    Put(TEncoding.ASCII.GetBytes('abc'));
    CdStart := M.Position - 4;
    SetLength(Central, 46);
    P32(Central, 0, $02014B50); P16(Central, 4, (3 shl 8) or 45); P16(Central, 6, 45); P16(Central, 8, 0); P16(Central, 10, 0);
    P32(Central, 12, 0); P32(Central, 16, $352441C2);
    P32(Central, 20, $FFFFFFFF); P32(Central, 24, $FFFFFFFF);
    P16(Central, 28, Length(Name)); P16(Central, 30, 28); P16(Central, 32, 0); P16(Central, 34, 0); P16(Central, 36, 0);
    P32(Central, 38, 0); P32(Central, 42, $FFFFFFFF);
    Put(Central); Put(Name);
    SetLength(Extra, 28);
    P16(Extra, 0, 1); P16(Extra, 2, 24);
    P64(Extra, 4, 3);                               { uncompressed size }
    P64(Extra, 12, 3);                              { compressed size }
    P64(Extra, 20, 0);                              { local header offset }
    Put(Extra);
    Z64Pos := M.Position - 4;
    SetLength(Z64, 56);
    P32(Z64, 0, $06064B50); P64(Z64, 4, 44); P16(Z64, 12, 45); P16(Z64, 14, 45); P32(Z64, 16, 0); P32(Z64, 20, 0);
    P64(Z64, 24, 1); P64(Z64, 32, 1); P64(Z64, 40, Z64Pos - CdStart); P64(Z64, 48, CdStart);
    Put(Z64);
    SetLength(Loc, 20);
    P32(Loc, 0, $07064B50); P32(Loc, 4, 0); P64(Loc, 8, Z64Pos); P32(Loc, 16, 1);
    Put(Loc);
    SetLength(Eocd, 22);
    P32(Eocd, 0, $06054B50); P16(Eocd, 4, 0); P16(Eocd, 6, 0); P16(Eocd, 8, $FFFF); P16(Eocd, 10, $FFFF);
    P32(Eocd, 12, $FFFFFFFF); P32(Eocd, 16, $FFFFFFFF); P16(Eocd, 20, 0);
    Put(Eocd);
    M.Position := 4;
    Z.Open(M, zmRead);
    Check(Z.FileCount = 1, 'ZIP64 end record: one entry');
    Check(Z.FileNames[0] = 'abc.txt', 'ZIP64 entry name');
    Z.Read(0, S, H, True);
    try
      Check(H.UncompressedSize64 = 3, 'local header size');
      Check(S.Size = 3, 'stream size through the ZIP64 extra field');
      SetLength(B, 3);
      S.ReadBuffer(B[0], 3);
      Check(TEncoding.ASCII.GetString(B) = 'abc', 'content behind the ZIP64 chain');
    finally
      S.Free;
    end;
    Z.Read('abc.txt', B);
    Check(TEncoding.ASCII.GetString(B) = 'abc', 'whole read behind the ZIP64 chain');
    Z.Close;
    { the locator pointing outside the archive is refused }
    M.Position := M.Size - 22 - 20 + 8;
    Z64Pos := M.Size;
    M.WriteBuffer(Z64Pos, 8);
    M.Position := 4;
    try
      Z.Open(M, zmRead);
      Check(False, 'ZIP64 locator pointing past the end accepted');
    except
      on EZipException do ;
    end;
  finally
    Z.Free;
    M.Free;
  end;
end;

{ 5. ExtractAll with subdirectories and a large entry read piecewise }
procedure Extract;
var
  Z: TZipFile;
  Src: TMemoryStream;
  Big, Back: TBytes;
  Target: string;
  F: TFileStream;
  S: TStream;
  H: TZipHeader;
  Buf: array[0..1023] of Byte;
  Total, Got: Int64;
  I: Integer;
begin
  Target := Dir + 'extract' + PathDelim;
  Big := Pattern(2000000, 9);
  Z := TZipFile.Create;
  Src := TMemoryStream.Create;
  try
    Z.Open(Dir + 'tree.zip', zmWrite);
    Src.WriteBuffer(Big[0], Length(Big));
    Src.Position := 0;
    Z.Add(Src, 'a/b/large.bin');
    Src.Position := 0;
    Z.Add(Src, 'a/stored.bin', zcStored);
    Z.Add(nil, 'top.txt');
    Z.Add(nil, 'emptydir/', zcStored);
    Z.Close;
    Z.Open(Dir + 'tree.zip', zmRead);
    Z.ExtractAll(Target);
    Check(DirectoryExists(Target + 'emptydir'), 'directory entry extracted');
    Check(FileExists(Target + 'a' + PathDelim + 'b' + PathDelim + 'large.bin'), 'nested file extracted');
    Check(FileExists(Target + 'a' + PathDelim + 'stored.bin'), 'stored file extracted');
    Check(FileExists(Target + 'top.txt'), 'top-level file extracted');
    Check(Abs(Now - FileDateToDateTime(FileAge(Target + 'top.txt'))) < 5 / MinsPerDay, 'extracted file dated by the entry (written just now)');
    F := TFileStream.Create(Target + 'a' + PathDelim + 'b' + PathDelim + 'large.bin', fmOpenRead);
    try
      SetLength(Back, F.Size);
      F.ReadBuffer(Back[0], F.Size);
      Check(SameBytes(Back, Big), 'extracted content');
    finally
      F.Free;
    end;
    { the large entry in 1 KB pieces straight from the archive }
    Z.Read('a/b/large.bin', S, H, True);
    try
      Total := 0;
      I := 0;
      repeat
        Got := S.Read(Buf, SizeOf(Buf));
        If (Got > 0) and (Buf[0] <> Big[Total]) then
          Inc(I);
        Inc(Total, Got);
      until Got = 0;
      Check((Total = Length(Big)) and (I = 0), 'piecewise read of the large entry');
    finally
      S.Free;
    end;
    Z.Close;
  finally
    Src.Free;
    Z.Free;
  end;
end;

procedure RemoveTree(const Path: string);
var
  SR: TUnicodeSearchRec;
begin
  If FindFirst(Path + '*', faAnyFile, SR) = 0 then begin
    repeat
      If (SR.Name = '.') or (SR.Name = '..') then
        Continue;
      If (SR.Attr and faDirectory) <> 0 then
        RemoveTree(Path + SR.Name + PathDelim)
      else
        DeleteFile(Path + SR.Name);
    until FindNext(SR) <> 0;
    FindClose(SR);
  end;
  RemoveDir(Path);
end;

{ the archive of section 2 for an independent reader (the gate checks it
  with Python's zipfile) }
procedure KeepWritten(const Target: string);
var
  Source, Dest: TFileStream;
begin
  Source := TFileStream.Create(Dir + 'written.zip', fmOpenRead);
  try
    Dest := TFileStream.Create(Target, fmCreate);
    try
      Dest.CopyFrom(Source, Source.Size);
    finally
      Dest.Free;
    end;
  finally
    Source.Free;
  end;
end;

{ flip one stored byte so the CRC fails after some of the entry was written }
procedure FlipStoredData(const FileName, EntryName: string);
var
  F: TFileStream;
  B: TBytes;
  I, NameLen, ExtraLen: Integer;
  Name: AnsiString;
begin
  F := TFileStream.Create(FileName, fmOpenReadWrite);
  try
    SetLength(B, F.Size);
    If Length(B) > 0 then
      F.ReadBuffer(B[0], Length(B));
    I := 0;
    while I <= Length(B) - 30 do begin
      If (B[I] = $50) and (B[I + 1] = $4B) and (B[I + 2] = 3) and (B[I + 3] = 4) then begin
        NameLen := B[I + 26] or (B[I + 27] shl 8);
        ExtraLen := B[I + 28] or (B[I + 29] shl 8);
        If (NameLen = Length(EntryName)) and (I + 30 + NameLen <= Length(B)) then begin
          SetString(Name, PAnsiChar(@B[I + 30]), NameLen);
          If Name = EntryName then begin
            B[I + 30 + NameLen + ExtraLen] := B[I + 30 + NameLen + ExtraLen] xor $FF;
            F.Position := 0;
            F.WriteBuffer(B[0], Length(B));
            Exit;
          end;
        end;
      end;
      Inc(I);
    end;
  finally
    F.Free;
  end;
  Check(False, 'local header of ' + EntryName + ' not found');
end;

procedure CorruptExtract;
var
  Z: TZipFile;
  Src: TMemoryStream;
  Bytes: TBytes;
  I: Integer;
  Target: string;
begin
  Target := Dir + 'corrupt' + PathDelim;
  ForceDirectories(Target);
  SetLength(Bytes, 70000);
  for I := 0 to High(Bytes) do
    Bytes[I] := Byte(I);
  Src := TMemoryStream.Create;
  Z := TZipFile.Create;
  try
    Src.WriteBuffer(Bytes[0], Length(Bytes));
    Src.Position := 0;
    Z.Open(Dir + 'corrupt.zip', zmWrite);
    Z.Add(Src, 'big.bin', zcStored);
    Z.Close;
    FlipStoredData(Dir + 'corrupt.zip', 'big.bin');
    Z.Open(Dir + 'corrupt.zip', zmRead);
    try
      Z.ExtractAll(Target);
      Check(False, 'damaged entry extracted');
    except
      on EZipException do ;
    end;
    Z.Close;
    Check(not FileExists(Target + 'big.bin'), 'CRC failure left the partial file');
  finally
    Src.Free;
    Z.Free;
  end;
end;

{$ifdef MSWINDOWS}
{ CreateFile drops trailing dots and spaces, and NUL is the NUL device }
procedure WindowsNames;
const
  Bad: array[0..8] of string = ('evil.txt.', 'trail ', 'NUL', '...', 'NUL.txt', 'CON', 'PRN.bin', 'COM1.log', 'LPT9');
var
  Z: TZipFile;
  I: Integer;
  Target: string;
begin
  Target := Dir + 'winnames' + PathDelim;
  Z := TZipFile.Create;
  try
    for I := 0 to High(Bad) do begin
      Z.Open(Dir + 'winnames.zip', zmWrite);
      Z.Add(nil, 'ok.txt');
      Z.Add(nil, Bad[I]);
      Z.Close;
      Z.Open(Dir + 'winnames.zip', zmRead);
      try
        Z.ExtractAll(Target);
        Check(False, 'extracted ' + Bad[I]);
      except
        on EZipException do ;
      end;
      Z.Close;
      Check(not FileExists(Target + 'ok.txt'), 'wrote ok.txt despite ' + Bad[I]);
      Check(not FileExists(Target + 'evil.txt'), 'trailing dot became evil.txt for ' + Bad[I]);
    end;
  finally
    Z.Free;
  end;
end;
{$endif}

{ Streaming ZIP producers put sizes and CRC in the central directory and
  a descriptor; the local header cannot supply them. }
procedure DataDescriptors;
var
  M: TMemoryStream;
  Z: TZipFile;
  B: TBytes;
  FileName: string;
  I: Integer;
begin
  M := TMemoryStream.Create;
  Z := TZipFile.Create;
  try
    M.WriteBuffer(DescriptorArchive[0], Length(DescriptorArchive));
    M.Position := 0;
    try
      Z.Open(M, zmRead);
      Check(Z.FileCount = 3, 'descriptor archive entries');
      Z.Read('stored', B);
      Check(TEncoding.ASCII.GetString(B) = 'abc', 'stored descriptor content');
      Z.Read('deflated', B);
      Check(TEncoding.ASCII.GetString(B) = 'abc', 'deflated descriptor content');
      Z.Read('empty', B);
      Check(Length(B) = 0, 'empty descriptor entry');
    except
      on E: Exception do
        Check(False, 'valid descriptor archive: ' + E.ClassName + ': ' + E.Message);
    end;
    Z.Close;
    FileName := Dir + 'descriptor-append.zip';
    If ParamCount > 0 then
      FileName := ParamStr(1) + '.descriptors.zip';
    M.SaveToFile(FileName);
    for I := 1 to 2 do begin
      Z.Open(FileName, zmReadWrite);
      Z.Add(nil, 'added' + IntToStr(I));
      Z.Close;
      Z.Open(FileName, zmRead);
      Check(Z.FileCount = 3 + I, 'append keeps descriptor entries');
      Z.Read('stored', B);
      Check(TEncoding.ASCII.GetString(B) = 'abc', 'append keeps stored descriptor');
      Z.Read('deflated', B);
      Check(TEncoding.ASCII.GetString(B) = 'abc', 'append keeps deflated descriptor');
      Z.Read('empty', B);
      Check(Length(B) = 0, 'append keeps empty descriptor');
      Z.Close;
    end;
  finally
    Z.Free;
    M.Free;
  end;
end;

{ mORMot allows an unsupported compression method on a directory header;
  a direct Read still has to reject it without double-freeing its stream. }
procedure UnsupportedDirectoryMethod;
var
  M: TMemoryStream;
  Z: TZipFile;
  B: TBytes;
begin
  M := TMemoryStream.Create;
  Z := TZipFile.Create;
  try
    M.WriteBuffer(PythonArchive[0], Length(PythonArchive));
    PByte(M.Memory)[479 + 30 + 8] := Ord('/');
    PByte(M.Memory)[698 + 46 + 8] := Ord('/');
    PWord(PByte(M.Memory) + 479 + 8)^ := 12;
    PWord(PByte(M.Memory) + 698 + 10)^ := 12;
    M.Position := 0;
    Z.Open(M, zmRead);
    try
      Z.Read(3, B);
      Check(False, 'unsupported directory compression accepted');
    except
      on EZipException do ;
      on E: Exception do
        Check(False, 'unsupported directory compression raised ' + E.ClassName);
    end;
    Z.Close;
  finally
    Z.Free;
    M.Free;
  end;
end;

{ The deflate end is independent of the uncompressed size in the directory. }
procedure EntryEnds;
var
  Z: TZipFile;
  M: TMemoryStream;
  S: TStream;
  H: TZipHeader;
  B, Prefix: TBytes;
  CaseIndex, Style, I: Integer;
  Name: string;
  Failed: Boolean;
begin
  Z := TZipFile.Create;
  M := TMemoryStream.Create;
  try
    SetLength(Prefix, 4999);
    for I := 0 to High(Prefix) do
      Prefix[I] := Byte(I * 7);
    for CaseIndex := 0 to 2 do begin
      M.Clear;
      M.WriteBuffer(PythonArchive[0], Length(PythonArchive));
      Name := 'dir/deflated.bin';
      case CaseIndex of
        0: PByte(M.Memory)[103] := PByte(M.Memory)[103] and $FE; { clear RFC 1951 BFINAL }
        1: begin
          PCardinal(PByte(M.Memory) + 574 + 24)^ := 4999;
          PCardinal(PByte(M.Memory) + 574 + 16)^ := crc32(0, @Prefix[0], Length(Prefix));
        end;
        2: begin
          Name := 'empty.txt';
          PCardinal(PByte(M.Memory) + 698 + 16)^ := 123;
        end;
      end;
      for Style := 0 to 1 do begin
        M.Position := 0;
        Z.Open(M, zmRead);
        Failed := False;
        try
          If Style = 0 then
            Z.Read(Name, B)
          else begin
            Z.Read(Name, S, H, True);
            try
              SetLength(B, S.Size + 1);
              S.Read(B[0], Length(B));
            finally
              S.Free;
            end;
          end;
        except
          on E: EZipException do begin
            Failed := True;
            If CaseIndex = 2 then
              Check(E is EZipCRCException, 'empty entry CRC exception type');
          end;
        end;
        Check(Failed, 'invalid entry end accepted, case ' + IntToStr(CaseIndex) + ', style ' + IntToStr(Style));
        Z.Close;
      end;
    end;
  finally
    M.Free;
    Z.Free;
  end;
end;

procedure WriteFromPosition;
var
  M: TMemoryStream;
  Z: TZipFile;
  Prefix: Cardinal;
  B: TBytes;
begin
  M := TMemoryStream.Create;
  Z := TZipFile.Create;
  try
    Prefix := $12345678;
    M.Size := 4096;
    FillChar(M.Memory^, M.Size, $AA);
    M.WriteBuffer(Prefix, SizeOf(Prefix));
    Z.Open(M, zmWrite);
    Z.Add(nil, 'empty.txt');
    Z.Close;
    Check(PCardinal(M.Memory)^ = Prefix, 'archive preserves the stream prefix');
    Check(M.Size = M.Position, 'Close removes the old stream tail');
    M.Position := SizeOf(Prefix);
    try
      Z.Open(M, zmRead);
      Z.Read(0, B);
      Check(Length(B) = 0, 'entry written behind a prefix');
    except
      on E: EZipException do
        Check(False, 'archive written at nonzero position: ' + E.Message);
    end;
    Z.Close;
  finally
    Z.Free;
    M.Free;
  end;
end;

begin
  Failures := 0;
  Dir := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'rtl-zip-' + IntToStr(GetProcessID) + PathDelim;
  ForceDirectories(Dir);
  try
    ReadForeignArchive;
    WriteAndReadBack;
    If ParamCount >= 1 then
      KeepWritten(ParamStr(1));
    Damage;
    EntryEnds;
    DataDescriptors;
    UnsupportedDirectoryMethod;
    WriteFromPosition;
    Escapes;
    CorruptExtract;
    {$ifdef MSWINDOWS}
    WindowsNames;
    {$endif}
    {$ifdef UNIX}
    SymlinkTargets;
    {$endif}
    Zip64Metadata;
    Extract;
  finally
    RemoveTree(Dir);
  end;
  If Failures <> 0 then
    Halt(1);
  WriteLn('ZIP_CONTRACT_PASS');
end.
