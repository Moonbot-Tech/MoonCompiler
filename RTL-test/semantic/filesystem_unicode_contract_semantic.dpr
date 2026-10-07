program filesystem_unicode_contract_semantic;

{$mode delphiunicode}

uses
  {$ifdef WINDOWS}Windows,{$else}BaseUnix,{$endif}
  SysUtils;

{$ifdef WINDOWS}
function NativeCreateSymbolicLink(LinkName, TargetName: PWideChar; Flags: DWORD): ByteBool;
  stdcall; external 'kernel32.dll' name 'CreateSymbolicLinkW';
{$endif}

type
  TGetDirectory = function: UnicodeString;

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create(MessageText);
end;

procedure RequireUnicode(var Value: UnicodeString);
begin
  // A var argument rejects a hidden byte-to-Unicode conversion at compile time.
  Check(StringElementSize(Value) = SizeOf(WideChar), 'Unicode element size');
end;

var
  GetDirectory: TGetDirectory;
  OriginalDir, RootDir, FileName, LinkName, LeafName: string;
  Search: TSearchRec;
  Link: TSymLinkRec;
  RawSearch: TRawbyteSearchRec;
  Handle: THandle;
  Id: TGUID;
  LinkCreated: Boolean;
begin
  // Assignment to string would silently conceal the incorrect return type.
  GetDirectory := @GetCurrentDir;
  Check(StringElementSize(GetCurrentDir) = SizeOf(WideChar), 'GetCurrentDir return type');
  RequireUnicode(Search.Name);
  RequireUnicode(Link.TargetName);
  Check(SizeOf(RawSearch.Name[1]) = 1, 'explicit raw-byte record must stay byte based');
  OriginalDir := GetDirectory();
  CreateGUID(Id);
  RootDir := IncludeTrailingPathDelimiter(GetTempDir) + 'moon-fs-' + GUIDToString(Id) + '-'+ #$6F22#$03A9;
  LeafName := 'file-' + #$6F22#$03A9 + '.txt';
  FileName := IncludeTrailingPathDelimiter(RootDir) + LeafName;
  LinkName := IncludeTrailingPathDelimiter(RootDir) + 'link-' + #$6F22#$03A9;
  LinkCreated := False;
  Check(CreateDir(RootDir), 'create Unicode directory');
  try
    Handle := FileCreate(FileName);
    Check(Handle <> THandle(-1), 'create Unicode file');
    FileClose(Handle);
    Check(SetCurrentDir(RootDir), 'set Unicode current directory');
    Check(GetDirectory() = RootDir, 'GetCurrentDir Unicode value');
    Check(StrComp(PChar(GetCurrentDir), PChar(RootDir)) = 0, 'direct PChar(GetCurrentDir)');
    Check(FindFirst('*', faAnyFile, Search) = 0, 'FindFirst Unicode directory');
    try
      while Search.Name <> LeafName do
        Check(FindNext(Search) = 0, 'FindNext lost Unicode file');
      Check(StrComp(PChar(Search.Name), PChar(LeafName)) = 0, 'direct PChar(Search.Name)');
    finally
      FindClose(Search);
    end;
    // The explicit byte API remains available independently of the public alias.
    Check(FindFirst(RawByteString('*'), faAnyFile, RawSearch) = 0, 'raw-byte FindFirst');
    FindClose(RawSearch);
    {$ifdef WINDOWS}
    LinkCreated := NativeCreateSymbolicLink(PWideChar(LinkName), PWideChar(FileName), 2);
    if not LinkCreated then
      Check(GetLastError = ERROR_PRIVILEGE_NOT_HELD, 'create native symbolic link');
    {$else}
    LinkCreated := fpSymlink(PAnsiChar(UTF8Encode(FileName)), PAnsiChar(UTF8Encode(LinkName))) = 0;
    Check(LinkCreated, 'create native symbolic link');
    {$endif}
    if LinkCreated then begin
      Check(FileGetSymLinkTarget(LinkName, Link), 'read Unicode symbolic link');
      Check(ExtractFileName(Link.TargetName) = LeafName, 'Unicode symbolic-link target');
      Check(StrComp(PChar(ExtractFileName(Link.TargetName)), PChar(LeafName)) = 0, 'direct PChar(link target)');
    end;
  finally
    Check(SetCurrentDir(OriginalDir), 'restore current directory');
    if LinkCreated then
      Check(DeleteFile(LinkName), 'remove symbolic link');
    if FileExists(FileName) then
      Check(DeleteFile(FileName), 'remove Unicode file');
    Check(RemoveDir(RootDir), 'remove Unicode directory');
  end;
  WriteLn('FILESYSTEM_UNICODE_CONTRACT_PASS');
end.
