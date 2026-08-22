program mormot_unicode_posix_probe;

{$mode delphiunicode}
{$codepage utf8}

uses
  mormot.core.fpcx64mm,
  cthreads,
  SysUtils,
  BaseUnix,
  mormot.core.base,
  mormot.core.os,
  mormot.core.search;

procedure Fail(Code: integer; const Msg: UnicodeString);
begin
  Writeln(StdErr, 'FAIL ', Code, ': ', Msg);
  Halt(Code);
end;

function Utf8Bytes(const Text: UnicodeString): RawByteString;
begin
  result := RawByteString(UTF8Encode(Text));
end;

function ContainsName(const Names: TRawUtf8DynArray;
  const Expected: RawByteString): boolean;
var
  i: PtrInt;
begin
  result := false;
  for i := 0 to high(Names) do
    if RawByteString(Names[i]) = Expected then
    begin
      result := true;
      exit;
    end;
end;

var
  Root, Nested, FileName, CreatedName, TouchLink, LibraryLink, DiskPath: TFileName;
  Env: TFileName;
  FoundNames: TFileNameDynArray;
  Names: TRawUtf8DynArray;
  Content, Output: RawByteString;
  Size: Int64;
  Stamp: TUnixMSTime;
  AvailableBytes, FreeBytes, TotalBytes: QWord;
  Lib: TLibHandle;
  ExitCode: integer;

begin
  Root := '/tmp/mooncompiler-unicode-' + IntToStr(fpGetPid) +
    '-каталог-漢🙂';
  Nested := Root + PathDelim + 'вложенный-目録';
  FileName := Nested + PathDelim + 'файл-数据🙂.txt';
  CreatedName := Nested + PathDelim + 'создан-作成🙂.txt';
  TouchLink := Root + PathDelim + 'касание-実行🙂';
  LibraryLink := Root + PathDelim + 'библиотека-加载🙂.so';

  If DirectoryExists(Root) then
    DirectoryDelete(Root);
  If EnsureDirectoryExists(Nested) = '' then
    Fail(1, 'EnsureDirectoryExists');
  try
    Content := 'unicode-posix-content';
    If not FileFromString(Content, FileName) then
      Fail(2, 'FileFromString');
    If not FileExists(FileName) then
      Fail(3, 'FileExists');
    If StringFromFile(FileName) <> Content then
      Fail(4, 'StringFromFile');
    If FileSize(FileName) <> Length(Content) then
      Fail(5, 'FileSize');
    If not FileInfoByName(FileName, Size, Stamp) or
       (Size <> Length(Content)) or (Stamp = 0) then
      Fail(6, 'FileInfoByName');
    If not FileIsReadable(FileName) or not FileIsWritable(FileName) then
      Fail(7, 'File access');
    If not FileSetDateFromUnixUtc(FileName, 1700000000) or
       (FileAgeToUnixTimeUtc(FileName) <> 1700000000) then
      Fail(8, 'File timestamp');
    FileSetHidden(FileName, true);
    FileSetHidden(FileName, false);

    Names := PosixFileNames(Root, true);
    If not ContainsName(Names,
       Utf8Bytes('вложенный-目録' + PathDelim +
         'файл-数据🙂.txt')) then
      Fail(9, 'PosixFileNames');

    DiskPath := Nested;
    If not GetDiskInfo(DiskPath, AvailableBytes, FreeBytes, TotalBytes) or
       (TotalBytes = 0) then
      Fail(10, 'GetDiskInfo');

    If not FileSymLink(TouchLink, '/usr/bin/touch') then
      Fail(11, 'touch symlink');
    If RunProcess(TouchLink, CreatedName, true) <> 0 then
      Fail(12, 'RunProcess');
    If not FileExists(CreatedName) then
      Fail(13, 'RunProcess argument');

    FoundNames := FileNames(Root, '*数据🙂.txt', [ffoSubFolder]);
    If (Length(FoundNames) <> 1) or
       (FoundNames[0] <> 'вложенный-目録' + PathDelim + 'файл-数据🙂.txt') then
      Fail(14, 'FileNames Unicode mask');
    FoundNames := FileNames(Root, '*.txt', [ffoSubFolder, ffoSortByName],
      'вложенный-目録' + PathDelim + 'создан-作成🙂.txt');
    If (Length(FoundNames) <> 1) or
       (FoundNames[0] <> 'вложенный-目録' + PathDelim + 'файл-数据🙂.txt') then
      Fail(15, 'FileNames Unicode ignore/result');

    Env := 'MOON_UNICODE=значение-値🙂' + #0#0;
    If RunCommand('test "$MOON_UNICODE" = "значение-値🙂"',
       true, Env) <> 0 then
      Fail(16, 'RunCommand environment');

    Output := RunRedirect('/bin/pwd', @ExitCode, nil, INFINITE, true, '', Nested);
    If (ExitCode <> 0) or (Output <> Utf8Bytes(Nested) + #10) then
      Fail(17, 'RunRedirect working directory');

    If FileExists('/lib/x86_64-linux-gnu/libm.so.6') then
    begin
      If not FileSymLink(LibraryLink, '/lib/x86_64-linux-gnu/libm.so.6') then
        Fail(18, 'library symlink');
      Lib := LibraryOpen(LibraryLink);
      If Lib = 0 then
        Fail(19, 'LibraryOpen');
      LibraryClose(Lib);
    end;
  finally
    DeleteFile(LibraryLink);
    DeleteFile(TouchLink);
    DeleteFile(CreatedName);
    DeleteFile(FileName);
    RemoveDir(Nested);
    RemoveDir(Root);
  end;
  Writeln('PASS mormot-unicode-posix-boundaries');
end.
