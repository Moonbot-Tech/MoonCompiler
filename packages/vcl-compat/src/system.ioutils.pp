unit System.IOUtils;
{
   This file is part of the Free Pascal run time library.
    Copyright (c) 2022 the Free Pascal development team

   FPC/Lazarus Replacement for IOUtils from Delphi 10.4
   Initially written 2022 by Dirk Jansen, completed by Michael Van Canneyt

   See the file COPYING.FPC, included in this distribution,
   for details about the copyright.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

}

{$MODE OBJFPC}
{$H+}
{ $IFDEF VER_3_2}
{$modeswitch nestedprocvars}
{ $ELSE}
{$modeswitch functionreferences}
{$modeswitch anonymousfunctions}
{ $ENDIF}
{$modeswitch arrayoperators}
{$SCOPEDENUMS ON}

interface

{$IFDEF FPC_DOTTEDUNITS}
uses
  System.Classes, System.SysUtils, System.Types, Fcl.Streams.Extra;
{$ELSE FPC_DOTTEDUNITS}
uses
  Classes, SysUtils, Types, streamex;
{$ENDIF FPC_DOTTEDUNITS}

type

  TPathPrefixType = (pptNoPrefix, pptExtended, pptExtendedUNC);
  TSearchOption    = (soTopDirectoryOnly, soAllDirectories);
  TFileMode        = (fmCreateNew, fmCreate, fmOpen, fmOpenOrCreate,
                      fmTruncate, fmAppend);
  TFileAccess      = (faRead, faWrite, faReadWrite);
  TFileShare       = (fsNone, fsRead, fsWrite, fsReadWrite);
  {$IF DEFINED(WINDOWS)}
    TFileAttribute = (faReadOnly, faHidden, faSystem, faDirectory, faArchive,
                      faDevice, faNormal, faTemporary, faSparseFile,
                      faReparsePoint, faCompressed, faOffline,
                      faNotContentIndexed, faEncrypted, faSymLink) ;
  {$ELSEIF DEFINED(UNIX)}
    TFileAttribute = (faNamedPipe, faCharacterDevice, faDirectory, faBlockDevice,
                      faNormal, faSymLink, faSocket, faWhiteout,
                      faOwnerRead, faOwnerWrite, faOwnerExecute,
                      faGroupRead, faGroupWrite, faGroupExecute,
                      faOthersRead, faOthersWrite, faOthersExecute,
                      faUserIDExecution, faGroupIDExecution, faStickyBit);
  {$ELSE}
    TFileAttribute = (faReadOnly, faHidden, faSystem, faDirectory, faArchive,
                      faNormal, faSymLink);

  {$ENDIF}

  TFileAttributes = set of TFileAttribute;

  TFilterPredicate       = function(const aPath: string; const SearchRec: TSearchRec): Boolean;
{$IFDEF VER3_2}
  TFilterPredicateLocal = function(const aPath: string; const SearchRec: TSearchRec): Boolean is nested;
{$ELSE}
  TFilterPredicateLocal = reference to function(const aPath: string; const SearchRec: TSearchRec): Boolean;
{$ENDIF}
  TFilterPredicateObject = function(const aPath: string; const SearchRec: TSearchRec): Boolean of object;

  { TDirectory }

type
  TDirectory = class
  protected
    class function GetFilesAndDirectories(const aPath, aSearchPattern: string;
      const aSearchOption: TSearchOption; const SearchAttributes: TFileAttributes;
      const aPredicate: TFilterPredicateLocal): TStringDynArray;  static;
  public
    class procedure Copy(const SourceDirName, DestDirName: string); overload; static;
    class procedure Copy(const SourceDirName, DestDirName: string; const IgnoreErrors: Boolean); overload; static;
    class procedure CreateDirectory(const aPath: string); static;
    class procedure Delete(const aPath: string); overload; static;
    class procedure Delete(const aPath: string; const Recursive: Boolean); overload; static;
    class function Exists(const aPath: string; FollowLink: Boolean = True): Boolean; static;
    class function GetAttributes(const aPath: string; FollowLink: Boolean = True): TFileAttributes; static;
    class function GetCurrentDirectory: string; static;
    class procedure SetCurrentDirectory(const aPath: string); static;
    class function GetLogicalDrives: TStringDynArray; static;
    class function GetCreationTime(const aPath: string): TDateTime; static;
    class function GetCreationTimeUtc(const aPath: string): TDateTime; static;
    class function GetLastAccessTime(const aPath: string): TDateTime; static;
    class function GetLastAccessTimeUtc(const aPath: string): TDateTime; static;
    class function GetLastWriteTime(const aPath: string): TDateTime; static;
    class function GetLastWriteTimeUtc(const aPath: string): TDateTime; static;
    class procedure SetAttributes(const aPath: string; const Attributes: TFileAttributes); static;
    class procedure SetCreationTime(const aPath: string; const CreationTime: TDateTime); static;
    class procedure SetCreationTimeUtc(const aPath: string; const CreationTime: TDateTime); static;
    class procedure SetLastAccessTime(const aPath: string; const LastAccessTime: TDateTime); static;
    class procedure SetLastAccessTimeUtc(const aPath: string; const LastAccessTime: TDateTime); static;
    class procedure SetLastWriteTime(const aPath: string; const LastWriteTime: TDateTime); static;
    class procedure SetLastWriteTimeUtc(const aPath: string; const LastWriteTime: TDateTime); static;
    class function GetParent(const aPath: string): string; static;
    class function GetDirectories(const aPath: string): TStringDynArray; overload; static;
    class function GetDirectories(const aPath: string; const aPredicate: TFilterPredicateLocal): TStringDynArray; overload; static;
    class function GetDirectories(const aPath: string; const aPredicate: TFilterPredicateObject): TStringDynArray; overload; static;
    class function GetDirectories(const aPath: string; const aPredicate: TFilterPredicate): TStringDynArray; overload; static;
    class function GetDirectories(const aPath, aSearchPattern: string): TStringDynArray; overload; static;
    class function GetDirectories(const aPath, aSearchPattern: string; const aPredicate: TFilterPredicateLocal): TStringDynArray; overload; static;
    class function GetDirectories(const aPath, aSearchPattern: string; const aPredicate: TFilterPredicateObject): TStringDynArray; overload; static;
    class function GetDirectories(const aPath, aSearchPattern: string; const aPredicate: TFilterPredicate): TStringDynArray; overload; static;
    class function GetDirectories(const aPath, aSearchPattern: string; const aSearchOption: TSearchOption): TStringDynArray; overload; static;
    class function GetDirectories(const aPath, aSearchPattern: string; const aSearchOption: TSearchOption; const aPredicate: TFilterPredicateLocal): TStringDynArray; overload; static;
    class function GetDirectories(const aPath, aSearchPattern: string; const aSearchOption: TSearchOption; const aPredicate: TFilterPredicateObject): TStringDynArray; overload; static;
    class function GetDirectories(const aPath, aSearchPattern: string; const aSearchOption: TSearchOption; const aPredicate: TFilterPredicate): TStringDynArray; overload; static;
    class function GetDirectories(const aPath: string; const aSearchOption: TSearchOption; const aPredicate: TFilterPredicateLocal): TStringDynArray; overload; static;
    class function GetDirectories(const aPath: string; const aSearchOption: TSearchOption; const aPredicate: TFilterPredicateObject): TStringDynArray; overload; static;
    class function GetDirectories(const aPath: string; const aSearchOption: TSearchOption; const aPredicate: TFilterPredicate): TStringDynArray; overload; static;
    class function GetDirectoryRoot(const aPath: string): string; static;
    class function GetDirectoriesEnumerator(const aPath: string): specialize IEnumerable<string>; overload; static;
    class function GetDirectoriesEnumerator(const aPath: string; const aPredicate: TFilterPredicate): specialize IEnumerable<string>; overload; static;
    class function GetDirectoriesEnumerator(const aPath, aSearchPattern: string): specialize IEnumerable<string>; overload; static;
    class function GetDirectoriesEnumerator(const aPath, aSearchPattern: string; const aPredicate: TFilterPredicate): specialize IEnumerable<string>; overload; static;
    class function GetDirectoriesEnumerator(const aPath, aSearchPattern: string; const aSearchOption: TSearchOption): specialize IEnumerable<string>; overload; static;
    class function GetDirectoriesEnumerator(const aPath, aSearchPattern: string; const aSearchOption: TSearchOption; const aPredicate: TFilterPredicate): specialize IEnumerable<string>; overload; static;
    class function GetDirectoriesEnumerator(const aPath: string; const aSearchOption: TSearchOption; const aPredicate: TFilterPredicate): specialize IEnumerable<string>; overload; static;
    class function GetFiles(const aPath: string): TStringDynArray; overload; static;
    class function GetFilesEnumerator(const aPath: string): specialize IEnumerable<string>; overload; static;
    class function GetFilesEnumerator(const aPath: string; const aPredicate: TFilterPredicate): specialize IEnumerable<string>; overload; static;
    class function GetFilesEnumerator(const aPath, aSearchPattern: string): specialize IEnumerable<string>; overload; static;
    class function GetFilesEnumerator(const aPath, aSearchPattern: string; const aPredicate: TFilterPredicate): specialize IEnumerable<string>; overload; static;
    class function GetFilesEnumerator(const aPath, aSearchPattern: string; const aSearchOption: TSearchOption): specialize IEnumerable<string>; overload; static;
    class function GetFilesEnumerator(const aPath, aSearchPattern: string; const aSearchOption: TSearchOption; const aPredicate: TFilterPredicate): specialize IEnumerable<string>; overload; static;
    class function GetFilesEnumerator(const aPath: string; const aSearchOption: TSearchOption; const aPredicate: TFilterPredicate): specialize IEnumerable<string>; overload; static;
    class function GetFiles(const aPath: string; const aPredicate: TFilterPredicateLocal): TStringDynArray; overload; static;
    class function GetFiles(const aPath: string; const aPredicate: TFilterPredicateObject): TStringDynArray; overload; static;
    class function GetFiles(const aPath: string; const aPredicate: TFilterPredicate): TStringDynArray; overload; static;
    class function GetFiles(const aPath, aSearchPattern: string): TStringDynArray; overload; static;
    class function GetFiles(const aPath, aSearchPattern: string; const aPredicate: TFilterPredicateLocal): TStringDynArray; overload; static;
    class function GetFiles(const aPath, aSearchPattern: string; const aPredicate: TFilterPredicateObject): TStringDynArray; overload; static;
    class function GetFiles(const aPath, aSearchPattern: string; const aPredicate: TFilterPredicate): TStringDynArray; overload; static;
    class function GetFiles(const aPath, aSearchPattern: string; const aSearchOption: TSearchOption): TStringDynArray; overload; static;
    class function GetFiles(const aPath, aSearchPattern: string;const aSearchOption: TSearchOption;const aPredicate: TFilterPredicateLocal): TStringDynArray; overload; static;
    class function GetFiles(const aPath, aSearchPattern: string;const aSearchOption: TSearchOption;const aPredicate: TFilterPredicateObject): TStringDynArray; overload; static;
    class function GetFiles(const aPath, aSearchPattern: string;const aSearchOption: TSearchOption;const aPredicate: TFilterPredicate): TStringDynArray; overload; static;
    class function GetFiles(const aPath: string;const aSearchOption: TSearchOption;const aPredicate: TFilterPredicateLocal): TStringDynArray; overload; static;
    class function GetFiles(const aPath: string;const aSearchOption: TSearchOption;const aPredicate: TFilterPredicateObject): TStringDynArray; overload; static;
    class function GetFiles(const aPath: string;const aSearchOption: TSearchOption;const aPredicate: TFilterPredicate): TStringDynArray; overload; static;
    class function GetFileSystemEntries(const aPath: string): TStringDynArray;overload; static;
    class function GetFileSystemEntriesEnumerator(const aPath: string): specialize IEnumerable<string>; overload; static;
    class function GetFileSystemEntriesEnumerator(const aPath: string; const aPredicate: TFilterPredicate): specialize IEnumerable<string>; overload; static;
    class function GetFileSystemEntriesEnumerator(const aPath, aSearchPattern: string): specialize IEnumerable<string>; overload; static;
    class function GetFileSystemEntriesEnumerator(const aPath, aSearchPattern: string; const aPredicate: TFilterPredicate): specialize IEnumerable<string>; overload; static;
    class function GetFileSystemEntriesEnumerator(const aPath: string; const aSearchOption: TSearchOption; const aPredicate: TFilterPredicate): specialize IEnumerable<string>; overload; static;
    class function GetFileSystemEntries(const aPath: string; const aPredicate: TFilterPredicateLocal): TStringDynArray; overload; static;
    class function GetFileSystemEntries(const aPath: string; const aPredicate: TFilterPredicateObject): TStringDynArray; overload; static;
    class function GetFileSystemEntries(const aPath: string; const aPredicate: TFilterPredicate): TStringDynArray; overload; static;
    class function GetFileSystemEntries(const aPath, aSearchPattern: string): TStringDynArray; overload; static;
    class function GetFileSystemEntries(const aPath, aSearchPattern: string; const aPredicate: TFilterPredicateLocal): TStringDynArray; overload; static;
    class function GetFileSystemEntries(const aPath, aSearchPattern: string; const aPredicate: TFilterPredicateObject): TStringDynArray; overload; static;
    class function GetFileSystemEntries(const aPath, aSearchPattern: string; const aPredicate: TFilterPredicate): TStringDynArray; overload; static;
    class function GetFileSystemEntries(const aPath: string; const aSearchOption: TSearchOption; const aPredicate: TFilterPredicateLocal): TStringDynArray; overload; static;
    class function GetFileSystemEntries(const aPath: string; const aSearchOption: TSearchOption; const aPredicate: TFilterPredicateObject): TStringDynArray; overload; static;
    class function GetFileSystemEntries(const aPath: string; const aSearchOption: TSearchOption; const aPredicate: TFilterPredicate): TStringDynArray; overload; static;
    Class Procedure ForAllEntries(const aPath, aPattern: string; const aBefore, aAfter: TFilterPredicateLocal; aRecursive: Boolean); static;
    class function IsEmpty(const aPath: string): Boolean; static;
    class function IsRelativePath(const aPath: string): Boolean; static;
    class procedure Move(const SourceDirName, DestDirName: string); static;
  end;

  { TPath }

  TPath = class
  private
    class var FAltDirectorySeparatorChar: Char;
    class var FDirectorySeparatorChar: Char;
    class var FExtensionSeparatorChar: Char;
    class var FPathSeparator: Char;
    class var FVolumeSeparatorChar: Char;
    class var FInvalidPathChars : TCharArray;
    class var FinvalidFileNameChars : TCharArray;
    // FNMatch is case sensitive!
    class function FNMatch(const Pattern, Name: string): Boolean; static;
    class function IntGetPathRoot(const aPath: string): string; static;
    // Return position of first char after \\?\(UNC). Optionally return prefixtype.
    class function SkipExtendedPrefix(const aPath: string; out Prefix: TPathPrefixType): SizeInt; static;
    class function SkipExtendedPrefix(const aPath: String): SizeInt; static;
  {$ifdef mswindows}
    class function SkipRoot(const aPath: string): SizeInt; static;
  {$endif}
  public
    class constructor Create;
    class function IsValidPathChar(const AChar: Char): Boolean; static;
    class function IsValidFileNameChar(const AChar: Char): Boolean; static;
    class function HasValidPathChars(const aPath: string; const UseWildcards: Boolean = false): Boolean; inline; static;
    class function HasValidPathChars(const aPath: string; out Index: Integer; const UseWildcards: Boolean = false): Boolean; static;
    class function HasValidFileNameChars(const FileName: string; const UseWildcards: Boolean = False): Boolean; inline; static;
    class function HasValidFileNameChars(const FileName: string; out Index: Integer; const UseWildcards: Boolean = False): Boolean; static;
    class function GetExtendedPrefix(const aPath: string): TPathPrefixType; static;
    class function IsDriveRooted(const aPath: string): Boolean; static;
    class function IsExtendedPrefixed(const aPath: string): Boolean; static;
    class function IsRelativePath(const aPath: string): Boolean; static;
    class function IsUNCPath(const aPath: string): Boolean; static;
    class function IsUNCRooted(const aPath: string): Boolean; static;
    class function GetGUIDFileName(const UseSeparator: Boolean = False): string; static;
    class function DriveExists(const aPath: string): Boolean; static;
    class function MatchesPattern(const FileName, Pattern: string; const CaseSensitive: Boolean): Boolean; static;
    class function ChangeExtension(const aPath, Extension: string): string; static;
    class function Combine(const Path1, Path2: string; const ValidateParams: Boolean = True): string; static;
    class function Combine(const Path1, Path2, Path3: string; const ValidateParams: Boolean = True): string; static;
    class function Combine(const Path1, Path2, Path3, Path4: string; const ValidateParams: Boolean = True): string; static;
    class function Combine(const Paths: array of string; const ValidateParams: Boolean = True): string; static;
    class function GetDirectoryName(FileName: string): string; static;
    class function GetExtension(const FileName: string): string; static;
    class function GetFileName(const FileName: string): string; static;
    class function GetFileNameWithoutExtension(const FileName: string): string; static;
    class function GetFullPath(const aPath: string): string; static;
    class function GetInvalidFileNameChars: TCharArray; static;
    class function GetInvalidPathChars: TCharArray; static;
    class function GetPathRoot(const aPath: string): string; static;
    class function GetRandomFileName: string; static;
    class function GetTempFileName: string; static;
    class function GetTempPath: string; static;
    class function GetHomePath: string; static;
    class function GetDocumentsPath: string; static;
    class function GetDesktopPath: string; static;
    class function GetSharedDocumentsPath: string; static;
    class function GetLibraryPath: string; static;
    class function GetAppPath: string; static;
    class function GetCachePath: string;  static;
    class function GetPublicPath: string; static;
    class function GetPicturesPath: string; static;
    class function GetSharedPicturesPath: string; static;
    class function GetCameraPath: string; static;
    class function GetSharedCameraPath: string; static;
    class function GetMusicPath: string; static;
    class function GetSharedMusicPath: string; static;
    class function GetMoviesPath: string; static;
    class function GetSharedMoviesPath: string; static;
    class function GetAlarmsPath: string; static;
    class function GetSharedAlarmsPath: string; static;
    class function GetDownloadsPath: string; static;
    class function GetSharedDownloadsPath: string; static;
    class function GetRingtonesPath: string; static;
    class function GetSharedRingtonesPath: string; static;
    class function GetTemplatesPath: string;
    class function Exists(const aPath: string; aFollowLink: Boolean = True): Boolean; static;
    class function GetAttributes(const aPath: string; aFollowLink: Boolean = True): TFileAttributes; static;
    class procedure SetAttributes(const aPath: string; const aAttributes: TFileAttributes); static;
    class function HasExtension(const aPath: string): Boolean; static;
    class function IsPathRooted(const aPath: string): Boolean; static;
    class property ExtensionSeparatorChar: Char read FExtensionSeparatorChar;
    class property AltDirectorySeparatorChar: Char read FAltDirectorySeparatorChar;
    class property DirectorySeparatorChar: Char read FDirectorySeparatorChar;
    class property PathSeparator: Char read FPathSeparator;
    class property VolumeSeparatorChar: Char read FVolumeSeparatorChar;
  end;

  { TFile }

  TFile = class
  private
    class function DetectFileEncoding(const aPath: String; out BOMLength: Integer): TEncoding; static;
    class procedure GetFileTimestamps(const aFilename: TFileName; var aCreate, aWrite, aAccess: TDateTime; IsUTC : Boolean); static;
    class procedure SetFileTimestamps(const aFilename: TFileName;
      const aCreate, aWrite, aAccess: PDateTime; IsUTC: Boolean); static;
  public
    class function IntegerToFileAttributes(const Attributes: Integer): TFileAttributes; static;
    class function FileAttributesToInteger(const Attributes: TFileAttributes): Integer; static;
    class function Create(const aPath: string): TFileStream; overload; static;
    class function Create(const aPath: string; const BufferSize: Integer): TFileStream; overload; static;
    Class function OpenOrCreate(const aPath: string) : TFileStream; static;
    class procedure AppendAllText(const aPath, aContents: string); overload; static;
    class procedure AppendAllText(const aPath, Contents: string; const Encoding: TEncoding); overload; static;
    class function AppendText(const aPath: string): TStreamWriter; static;
    class procedure Copy(const SourceFileName, DestFileName: string); overload; static;
    class procedure Copy(const SourceFileName, DestFileName: string; const Overwrite: Boolean); overload; static;
    class function CreateSymLink(const Link, Target: string): Boolean; static;
    class function CreateText(const aPath: string): TStreamWriter; static;
    class procedure Delete(const aPath: string); static;
//{$IFDEF MSWINDOWS}
//    class procedure Decrypt(const aPath: string);
//    class procedure Encrypt(const aPath: string);
//{$ENDIF MSWINDOWS}
    class function Exists(const aPath: string; FollowLink: Boolean = True): Boolean; static;
    class function GetSize(const Path: string): Int64; static;
    class function GetAttributes(const aPath: string; FollowLink: Boolean = True): TFileAttributes; static;
    class function GetCreationTime(const aPath: string): TDateTime; static;
    class function GetCreationTimeUtc(const aPath: string): TDateTime; static;
    class function GetLastAccessTime(const aPath: string): TDateTime; static;
    class function GetLastAccessTimeUtc(const aPath: string): TDateTime; static;
    class function GetLastWriteTime(const aPath: string): TDateTime; static;
    class function GetLastWriteTimeUtc(const aPath: string): TDateTime; static;
    class function GetSymLinkTarget(const aFileName: string; var SymLinkRec: TSymLinkRec): Boolean; overload; static;
    class function GetSymLinkTarget(const aFileName: string; var TargetName: RawByteString): Boolean; overload; static;
    class function GetSymLinkTarget(const aFileName: Unicodestring; var TargetName: UnicodeString): Boolean; overload; static;
    class procedure Move(SourceFileName, DestFileName: string); static;
    class function Open(const aPath: string; const aMode: TFileMode): TFileStream; overload; static;
    class function Open(const aPath: string; const aMode: TFileMode; const aAccess: TFileAccess): TFileStream; overload; static;
    class function Open(const aPath: string; const aMode: TFileMode; const aAccess: TFileAccess; const aShare: TFileShare): TFileStream; overload; static;
    class function OpenRead(const aPath: string): TFileStream; static;
    class function OpenText(const aPath: string): TStreamReader; static;
    class function OpenWrite(const aPath: string): TFileStream; static;
    class function ReadAllBytes(const aPath: string): TBytes; static;
    class function ReadAllLines(const aPath: string): TStringDynArray; overload; static;
    class function ReadAllLines(const aPath: string; const aEncoding: TEncoding): TStringDynArray; overload; static;
    class function ReadAllText(const aPath: string): string; overload; static;
    class function ReadAllText(const aPath: string; const aEncoding: TEncoding): string; overload; static;
    class procedure Replace(const aSource, aDestination, aBackup: string); overload; static;
{$IFDEF MSWINDOWS}
    class procedure Replace(const aSource, aDestination, aBackup: string; const aIgnoreMetadataErrors: Boolean); overload; static;
{$ENDIF MSWINDOWS}
    class procedure SetAttributes(const aPath: string; const aAttributes: TFileAttributes); static;
    class procedure SetCreationTime(const aPath: string; const CreationTime: TDateTime); static;
    class procedure SetCreationTimeUtc(const aPath: string; const CreationTime: TDateTime); static;
    class procedure SetLastAccessTime(const aPath: string; const LastAccessTime: TDateTime); static;
    class procedure SetLastAccessTimeUtc(const aPath: string; const LastAccessTime: TDateTime); static;
    class procedure SetLastWriteTime(const aPath: string; const LastWriteTime: TDateTime); static;
    class procedure SetLastWriteTimeUtc(const aPath: string; const LastWriteTime: TDateTime); static;
    class procedure WriteAllBytes(const aPath: string; const aBytes: TBytes); static;
    class procedure WriteAllLines(const aPath: string; const aContents: TStringDynArray); overload; static;
    class procedure WriteAllLines(const aPath: string; const aContents: TStringDynArray; const aEncoding: TEncoding); overload; static;
    class procedure WriteAllText(const aPath, aContents: string); overload; static;
    class procedure WriteAllText(const aPath, aContents: string; const aEncoding: TEncoding); overload; static;
  end;

implementation

{$IFDEF FPC_DOTTEDUNITS}
uses
  {$IfDef MSWINDOWS}
    WinApi.Windows, WinApi.WinDirs,
  {$EndIf}
  {$IfDef WINCE}
    WinApi.Windows,
  {$EndIf}
  {$IfDef Unix}
    UnixApi.Base,
  {$EndIf}
   System.DateUtils
  ;
{$ELSE FPC_DOTTEDUNITS}
uses
  {$IfDef MSWINDOWS}
    windows, WinDirs,
  {$EndIf}
  {$IfDef WINCE}
    windows,
  {$EndIf}
  {$IfDef UNIX}
    BaseUnix,
  {$EndIf}
   DateUtils
  ;
{$ENDIF FPC_DOTTEDUNITS}

type
  TStringArrayEnumerator = class(TInterfacedObject,
    specialize IEnumerator<string>)
  private
    FItems: TStringDynArray;
    FIndex: Integer;
    function GetCurrent: string;
    function MoveNext: Boolean;
    procedure Reset;
  public
    constructor Create(const aItems: TStringDynArray);
  end;

  TStringArrayEnumerable = class(TInterfacedObject,
    specialize IEnumerable<string>)
  private
    FItems: TStringDynArray;
    function GetEnumerator: specialize IEnumerator<string>;
  public
    constructor Create(const aItems: TStringDynArray);
  end;

ResourceString
  SErrFileExists = 'File "%s" already exists';
  SErrFileNotFound  = 'File "%s" does not exist';
  SErrInvalidCharsInPath = 'Filename "%s" contains invalid characters.' ;
  SErrEmptyPath = 'Error: aPath is empty.'  ;

  {$IfDef Unix}
  errStatFailed = 'Fstat for %a failed. Err.No.: %d';
  {$EndIf}

constructor TStringArrayEnumerator.Create(const aItems: TStringDynArray);
begin
  inherited Create;
  FItems:=aItems;
  FIndex:=-1;
end;

function TStringArrayEnumerator.GetCurrent: string;
begin
  Result:=FItems[FIndex];
end;

function TStringArrayEnumerator.MoveNext: Boolean;
begin
  Result:=FIndex<High(FItems);
  if Result then
    Inc(FIndex);
end;

procedure TStringArrayEnumerator.Reset;
begin
  FIndex:=-1;
end;

constructor TStringArrayEnumerable.Create(const aItems: TStringDynArray);
begin
  inherited Create;
  FItems:=aItems;
end;

function TStringArrayEnumerable.GetEnumerator: specialize IEnumerator<string>;
begin
  Result:=TStringArrayEnumerator.Create(FItems);
end;

{$IFDEF MSWINDOWS}
Const
  WinAttrs : Array[TFileAttribute] of Integer =
     (FILE_ATTRIBUTE_READONLY, FILE_ATTRIBUTE_HIDDEN, FILE_ATTRIBUTE_SYSTEM,
      FILE_ATTRIBUTE_DIRECTORY,FILE_ATTRIBUTE_ARCHIVE, FILE_ATTRIBUTE_DEVICE,
      FILE_ATTRIBUTE_NORMAL, FILE_ATTRIBUTE_TEMPORARY,FILE_ATTRIBUTE_SPARSE_FILE,
      FILE_ATTRIBUTE_REPARSE_POINT, FILE_ATTRIBUTE_COMPRESSED, FILE_ATTRIBUTE_OFFLINE,
      FILE_ATTRIBUTE_NOT_CONTENT_INDEXED, FILE_ATTRIBUTE_ENCRYPTED,FILE_ATTRIBUTE_REPARSE_POINT);
{$ENDIF}
{$IFDEF WINCE}
  { Missing attributes are put to zero }
Const
  WinAttrs : Array[TFileAttribute] of Integer =
     (FILE_ATTRIBUTE_READONLY, FILE_ATTRIBUTE_HIDDEN, FILE_ATTRIBUTE_SYSTEM,
      FILE_ATTRIBUTE_DIRECTORY,FILE_ATTRIBUTE_ARCHIVE, 0{FILE_ATTRIBUTE_DEVICE},
      FILE_ATTRIBUTE_NORMAL, FILE_ATTRIBUTE_TEMPORARY,FILE_ATTRIBUTE_SPARSE_FILE,
      FILE_ATTRIBUTE_REPARSE_POINT, FILE_ATTRIBUTE_COMPRESSED, FILE_ATTRIBUTE_OFFLINE,
      FILE_ATTRIBUTE_NOT_CONTENT_INDEXED, FILE_ATTRIBUTE_ENCRYPTED,FILE_ATTRIBUTE_REPARSE_POINT);
{$ENDIF}

{$IFDEF WINDOWS}
function FileAttributesToFlags(const Attributes: TFileAttributes): Integer;

var
  A : TFileAttribute;
begin
  Result:=0;
  For a in TFileAttributes do
    if a in Attributes then
      Result:=Result+WinAttrs[a];
end;

function FlagsToFileAttributes(const Flags : Integer) : TFileAttributes;

var
  A : TFileAttribute;
begin
  Result:=[];
  For a in TFileAttributes do
    if (Flags and WinAttrs[a])<>0 then
      Include(Result,a);
end;
{$ENDIF}

{$IFDEF unix}

Const
  UnixModes : Array[TFileAttribute] of Integer =
    (
    0,0,0,0, // 0 means it can't be set
    0,0,0,0,
    S_IRUSR, S_IWUSR,S_IXUSR,
    S_IRGRP,S_IWGRP, S_IXGRP,
    S_IROTH,S_IWOTH,S_IXOTH,
    S_ISUID,S_ISGID,0 {S_IVTX}
    );

function FileAttributesToMode(const Attributes: TFileAttributes): Integer;

var
  A : TFileAttribute;
begin
  Result:=0;
  For a in TFileAttributes do
    if a in Attributes then
      Result:=Result+UnixModes[a];
end;

function ModeToFileAttributes(const Flags : Integer) : TFileAttributes;

var
  A : TFileAttribute;
begin
  Result:=[];
  For a in TFileAttributes do
    if (Flags and UnixModes[a])<>0 then
      Include(Result,a);
end;
{$ENDIF}


function UTCtoLocal(const UTCDateTime: TDateTime): TDateTime;
begin
  Result:={$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}SysUtils.UniversalTimeToLocal(UTCDateTime,GetLocalTimeOffset);
 end;

{$ifdef windows}
function MakeWinApiPath(const Path: string): string; forward;
{$endif}
procedure RaisePathError(const Path: string; Code: Integer);
var
  Error: EInOutError;
begin
  Error:=EInOutError.CreateFmt('%s: %s',[Path,SysErrorMessage(Code)]);
  Error.ErrorCode:=Code;
  raise Error;
end;

function MissingPathError(Code: Integer): Boolean;
begin
{$ifdef unix}
  Result:=(Code=ESysENOENT) or (Code=ESysENOTDIR);
{$else}
  Result:=(Code=ERROR_FILE_NOT_FOUND) or (Code=ERROR_PATH_NOT_FOUND);
{$endif}
end;

procedure RequireDirectory(const Path: string);
var
  Attr,Code: Integer;
begin
  Attr:=FileGetAttr(Path);
  if Attr<0 then
    begin
    Code:=GetLastOSError;
    if not MissingPathError(Code) then
      RaisePathError(Path,Code);
    end;
  if (Attr<0) or ((Attr and {$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}SysUtils.faDirectory)=0) then
    raise EDirectoryNotFoundException.CreateFmt('Directory not found: %s',[Path]);
end;

function CheckedFindFirst(const Pattern: string; Attr: LongInt; out Rec: TSearchRec): Integer;
begin
{$ifdef unix}
  fpSetErrno(0);
{$endif}
  Result:=FindFirst(Pattern,Attr,Rec);
  if Result=0 then
    Exit;
{$ifdef unix}
  if MissingPathError(fpGetErrno) then
    RequireDirectory(ExtractFileDir(Pattern))
  else if fpGetErrno<>0 then
    RaisePathError(Pattern,fpGetErrno);
{$else}
  if (Result<>ERROR_FILE_NOT_FOUND) and (Result<>ERROR_NO_MORE_FILES) then
    RaisePathError(Pattern,Result);
{$endif}
end;

function CheckedFindNext(var Rec: TSearchRec; const Path: string): Integer;
begin
{$ifdef unix}
  fpSetErrno(0);
{$endif}
  Result:=FindNext(Rec);
  if Result=0 then
    Exit;
{$ifdef unix}
  if MissingPathError(fpGetErrno) then
    RequireDirectory(Path)
  else if fpGetErrno<>0 then
    RaisePathError(Path,fpGetErrno);
{$else}
  if Result<>ERROR_NO_MORE_FILES then
    RaisePathError(Path,Result);
{$endif}
end;

function SameFileIdentity(const A,B: string): Boolean;
{$ifdef unix}
var
  SA,SB: Stat;
begin
  Result:=(fpStat(A,SA)=0) and (fpStat(B,SB)=0) and
    (SA.st_dev=SB.st_dev) and (SA.st_ino=SB.st_ino);
end;
{$else}
var
  HA,HB: THandle;
  IA,IB: BY_HANDLE_FILE_INFORMATION;
  PA,PB: UnicodeString;
begin
  Result:=False;
  PA:=MakeWinApiPath(A);
  PB:=MakeWinApiPath(B);
  HA:=CreateFileW(PWideChar(PA),0,FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE,
    nil,OPEN_EXISTING,FILE_FLAG_BACKUP_SEMANTICS,0);
  if HA=INVALID_HANDLE_VALUE then
    Exit;
  try
    HB:=CreateFileW(PWideChar(PB),0,FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE,
      nil,OPEN_EXISTING,FILE_FLAG_BACKUP_SEMANTICS,0);
    if HB=INVALID_HANDLE_VALUE then
      Exit;
    try
      Result:=GetFileInformationByHandle(HA,IA) and GetFileInformationByHandle(HB,IB) and
        (IA.dwVolumeSerialNumber=IB.dwVolumeSerialNumber) and
        (IA.nFileIndexHigh=IB.nFileIndexHigh) and (IA.nFileIndexLow=IB.nFileIndexLow);
    finally
      CloseHandle(HB);
    end;
  finally
    CloseHandle(HA);
  end;
end;
{$endif}

{$ifdef windows}
function IOGetFinalPathNameByHandleW(Handle: THandle; Buffer: PWideChar; Size,Flags: DWORD): DWORD;
  stdcall; external 'kernel32' name 'GetFinalPathNameByHandleW';

function ResolvedDirectory(const Path: string): string;
var
  Handle: THandle;
  Buffer: UnicodeString;
  Count: DWORD;
begin
  Buffer:=MakeWinApiPath(Path);
  Handle:=CreateFileW(PWideChar(Buffer),0,FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE,
    nil,OPEN_EXISTING,FILE_FLAG_BACKUP_SEMANTICS,0);
  if Handle=INVALID_HANDLE_VALUE then
    RaisePathError(Path,GetLastOSError);
  try
    SetLength(Buffer,512);
    repeat
      Count:=IOGetFinalPathNameByHandleW(Handle,PWideChar(Buffer),Length(Buffer),0);
      if Count=0 then
        RaisePathError(Path,GetLastOSError);
      if Count<Length(Buffer) then
        Break;
      SetLength(Buffer,Count);
    until False;
    SetLength(Buffer,Count);
    Result:=string(Buffer);
  finally
    CloseHandle(Handle);
  end;
end;

function IOCreateSymbolicLinkW(Link, Target: PWideChar; Flags: DWORD): ByteBool;
  stdcall; external 'kernel32' name 'CreateSymbolicLinkW';
{$endif}

function CreatePathLink(const Link,Target: string): Boolean;
{$ifdef unix}
var
  LinkPath,TargetPath: RawByteString;
{$endif}
{$ifdef windows}
var
  LinkPath,TargetPath,TargetProbe: UnicodeString;
  Flags: DWORD;
{$endif}
begin
{$ifdef unix}
  LinkPath:=ToSingleByteFileSystemEncodedFileName(Link);
  TargetPath:=ToSingleByteFileSystemEncodedFileName(Target);
  Result:=fpSymlink(PAnsiChar(TargetPath),PAnsiChar(LinkPath))=0;
{$else}
  LinkPath:=MakeWinApiPath(Link);
  { Relative reparse targets are stored verbatim by CreateSymbolicLinkW.
    Normalize separators without resolving the target against the process CWD. }
  TargetPath:=UnicodeString(SetDirSeparators(Target));
  TargetProbe:=TargetPath;
  if not TPath.IsPathRooted(string(TargetProbe)) then
    TargetProbe:=ExtractFilePath(LinkPath)+TargetProbe;
  Flags:=Ord(DirectoryExists(TargetProbe));
  Result:=IOCreateSymbolicLinkW(PWideChar(LinkPath),PWideChar(TargetPath),Flags or 2);
  if not Result and (GetLastError=ERROR_INVALID_PARAMETER) then
    Result:=IOCreateSymbolicLinkW(PWideChar(LinkPath),PWideChar(TargetPath),Flags);
{$endif}
end;

{ TPath }

class constructor TPath.Create;
var
  C : Char;
begin
  FAltDirectorySeparatorChar:=#0;
  For C in AllowDirectorySeparators do
    if (C<>System.DirectorySeparator) and (FAltDirectorySeparatorChar=#0) then
      FAltDirectorySeparatorChar:=C;
  FExtensionSeparatorChar   := System.ExtensionSeparator;
  FDirectorySeparatorChar   := System.DirectorySeparator;
  FPathSeparator            := System.PathSeparator;

  if Length(DriveSeparator)>0 then
  begin
    {$if defined(UNIX) or defined(WASI)}
    FVolumeSeparatorChar     := DriveSeparator[1]
    {$else}
    FVolumeSeparatorChar     := DriveSeparator
    {$endif}
  end
  else
    FVolumeSeparatorChar    :=#0;
end;

class function TPath.IsValidPathChar(const AChar: Char): Boolean;


begin
  Result:=(Ord(aChar)<32);
{$IFNDEF UNIX}
  Result:=Result or CharInSet(aChar,[ '"', '<', '>', '|']);
{$ENDIF}
  Result:=Not Result;
end;

class function TPath.IsValidFileNameChar(const AChar: Char): Boolean;
begin
  Result:=(Ord(aChar)<32);
{$IFNDEF UNIX}
  Result:=Result or CharInSet(aChar,[ '"', '*', '/', ':', '<', '>', '?', '\', '|']);
{$ELSE}
  Result:=Result or CharInSet(aChar,[ '/', '~']) ;
{$ENDIF}
  Result:=Not Result;
end;

class function TPath.SkipExtendedPrefix(const aPath: String): SizeInt;

Var
  P : TPathPrefixType;

begin
  Result:=SkipExtendedPrefix(aPath,P);
end;

class function TPath.SkipExtendedPrefix(const aPath: string; out Prefix: TPathPrefixType): SizeInt;

Const
   pPrefix = '\\?\';
   UNCPrefix = pPrefix +'UNC\';
   LenPrefix = Length(pPrefix);
   lenUNCPrefix = Length(UNCPrefix);

begin
  Prefix:=GetExtendedPrefix(aPath);
  case Prefix of
  TPathPrefixType.pptExtended:
    Result:=LenPrefix+1;
  TPathPrefixType.pptExtendedUNC:
    Result:=LenUNCPrefix+1;
  else
    Result:=1;
  end;
end;

{$ifdef mswindows}
class function TPath.SkipRoot(const aPath: string): SizeInt;
var
  P, Start: PChar;
  Skip: SizeInt;
begin
  P := PChar(aPath); // Guarantee terminating #0 to avoid explicit length checks.
  if P[0] in AllowDirectorySeparators then
    if P[1] in AllowDirectorySeparators then
    begin
      Start := P;
      Inc(P, 2);
      // UNC: \\server\share, \\?\UNC\server\share, \\.\UNC\server\share. Devices: \\.\device, \\?\device.
      if (P[0] in ['.', '?']) and (P[1] in AllowDirectorySeparators) and
        (P[2] in ['u', 'U']) and (P[3] in ['n', 'N']) and (P[4] in ['c', 'C']) and (P[5] in AllowDirectorySeparators) then
        Inc(P, 6);
      // Skip two slash-delimited components. For UNC — server (P points to) and share, for devices — point/question mark (P points to) and device name.
      for Skip := 0 to 1 do
        repeat
          if P^ = #0 then break;
          Inc(P); // Includes the slash.
        until P[-1] in AllowDirectorySeparators; // Breaks on slash.
      Result := SizeUint(Pointer(P) - Pointer(Start)) div sizeof(Char);
    end else
      Result := 1 // One slash.
  else if (P[0] in ['a' .. 'z', 'A' .. 'Z']) and (P[1] = ':') then
    Result := 2 + ord(P[2] in AllowDirectorySeparators) // Drive plus maybe slash.
  else
    Result := 0;
end;
{$endif}

class function TPath.HasValidPathChars(const aPath: string;
  const UseWildcards: Boolean): Boolean;
var
  dummy: Integer;
begin
  Result:=TPath.HasValidPathChars(aPath, dummy, UseWildcards);
end;

class function TPath.HasValidPathChars(const aPath: string;
  out Index: integer; const UseWildcards: Boolean): Boolean;
var
  P: PChar;
  S,I,Len: Integer;
  C : Char;
  CheckWC : Boolean;
begin
  Len:=Length(aPath);
  if Len=0 then
    Exit(True);
  Result:=False;
  CheckWC:=not UseWildcards;
  P:=PChar(aPath);
  S:=SkipExtendedPrefix(aPath);
  Inc(P,S-1);
  for I:=S to Len do
    begin
    Index:=i;
    C:=P^;
    if CheckWC and (CharInSet(C,['?','*'])) then
      exit;
    if not IsValidPathChar(C) then
      exit;
    Inc(P);
    end;
  Result:=True;
end;

class function TPath.HasValidFileNameChars(const FileName: string;
  const UseWildcards: Boolean): Boolean;
var
  dummy: Integer;
begin
  Result:=HasValidFileNameChars(FileName, dummy, UseWildCards);
end;

class function TPath.HasValidFileNameChars(const FileName: string;
  out Index: Integer; const UseWildcards: Boolean): Boolean;
var
  P: PChar;
  S,I,Len: Integer;
  C : Char;
  CheckWC : Boolean;
begin
  Len:=Length(FileName);
  if Len=0 then
    Exit(True);
  Result:=False;
  CheckWC:=not UseWildcards;
  P:=PChar(FileName);
  S:=SkipExtendedPrefix(FileName);
  Inc(P,S-1);
  for I:=S to Len do
    begin
    Index:=I;
    C:=P^;
    if CheckWC and (CharInSet(C,['?','*'])) then
      exit;
    if not IsValidFileNameChar(C) then
      exit;
    Inc(P);
    end;
  Result:=True;
end;

class function TPath.GetExtendedPrefix(const aPath: string): TPathPrefixType;
begin
  Result:=TPathPrefixType.pptNoPrefix;
{$IFDEF MSWINDOWS}
  if aPath.ToUpper.StartsWith(PathDelim + PathDelim + '?' + PathDelim + 'UNC' + PathDelim) then
    Result:=TPathPrefixType.pptExtendedUNC
  else if aPath.StartsWith(PathDelim + PathDelim + '?' + PathDelim) then
    Result:=TPathPrefixType.pptExtended
{$ENDIF}
end;

class function TPath.IsDriveRooted(const aPath: string): Boolean;
begin
  {$IfDef MSWINDOWS}
    Result:=(Length(aPath) > 1) and
              (aPath[1] in ['a'..'z', 'A'..'Z']) and
              (aPath[2] = ':');
  {$Else}
    Result:=False;
  {$EndIf}
end;

class function TPath.IsExtendedPrefixed(const aPath: string): Boolean;
begin
{$IfDef MSWINDOWS}
  Result:=aPath.StartsWith(PathDelim + PathDelim + '?' + PathDelim);
{$Else}
  Result:=False;
{$EndIf}

end;

class function TPath.IsRelativePath(const aPath: string): Boolean;
begin
  Result:=(not aPath.StartsWith(PathDelim)) and
            (not TPath.IsDriveRooted(aPath)) and
            (not TPath.IsUNCRooted(aPath));
end;

class function TPath.IsUNCPath(const aPath: string): Boolean;
begin
  {$IfDef MSWINDOWS}
    Result:=IsUNCRooted(aPath) and HasValidPathChars(aPath,False)
  {$Else}
    Result:=False;
  {$EndIf}
end;

class function TPath.IsUNCRooted(const aPath: string): Boolean;
begin
  {$IfDef MSWINDOWS}
  Result:=False;
  if (Length(aPath)>=3) and ((Copy(aPath,1,2)=PathDelim+PathDelim) or (Copy(aPath,1,2)='//')) then
    If (aPath[3]='?') then
      Result:=GetExtendedPrefix(aPath) = TPathPrefixType.pptExtendedUNC
    else
      Result:=IsValidPathChar(aPath[3]);
  {$Else}
    Result:=False;
  {$EndIf}
end;

class function TPath.GetGUIDFileName(const UseSeparator: Boolean): string;
var
  Guid: TGUID;
begin
  CreateGUID(Guid);
  Result:=GUIDToString(Guid);
  if not UseSeparator then
    Result:=StringReplace(Result, '-', '', [rfReplaceAll]);
  Result:=Copy(Result, 2, Length(Result) - 2);
end;

class function TPath.DriveExists(const aPath: string): Boolean;
begin
  Result:=False;
  {$IfDef MSWINDOWS}
    try
      case GetDriveType(PChar(ExtractFileDrive(aPath))) of
        DRIVE_REMOVABLE,
        DRIVE_FIXED,
        DRIVE_REMOTE,
        DRIVE_CDROM,
        DRIVE_RAMDISK: Result:=True;
      end;
    except
      { no exception }
    end;
  {$EndIf}
end;

{ assumes that pattern and name have the same code page }
class function TPath.FNMatch(const Pattern, Name: string): Boolean;
Var
  LenPat,LenName : longint;

  function NameUtf8CodePointLen(index: longint): longint;
    var
      MaxLookAhead: longint;
    begin
      MaxLookAhead:=LenName-Index+1;
      { abs so that in case of an invalid sequence, we count this as one
        codepoint }
      NameUtf8CodePointLen:=abs(Utf8CodePointLen(pansichar(@Name[index]),MaxLookAhead,true));
      { if the sequence was incomplete, use the incomplete sequence as
        codepoint }
      if NameUtf8CodePointLen=0 then
        NameUtf8CodePointLen:=MaxLookAhead;
    end;

    procedure GoToLastByteOfUtf8CodePoint(var j: longint);
      begin
        inc(j,NameUtf8CodePointLen(j)-1);
      end;

  { input:
      i: current position in pattern (start of utf-8 code point)
      j: current position in name (start of utf-8 code point)
      update_i_j: should i and j be changed by the routine or not

    output:
      i: if update_i_j, then position of last matching part of code point in
         pattern, or first non-matching code point in pattern. Otherwise the
         same value as on input.
      j: if update_i_j, then position of last matching part of code point in
         name, or first non-matching code point in name. Otherwise the
         same value as on input.
      result: true if match, false if no match
  }
  function CompareUtf8CodePoint(var i,j: longint; update_i_j: boolean): Boolean;
    var
      bytes,
      new_i,
      new_j: longint;
    begin
      bytes:=NameUtf8CodePointLen(j);
      new_i:=i;
      new_j:=j;
      { ensure that a part of an UTF-8 codepoint isn't interpreted
        as '*' or '?' }
      repeat
        dec(bytes);
        Result:=
          (new_j<=LenName) and
          (new_i<=LenPat) and
          (Pattern[new_i]=Name[new_j]);
        inc(new_i);
        inc(new_j);
      until not(Result) or
            (bytes=0);
      if update_i_j then
        begin
          i:=new_i;
          j:=new_j;
        end;
    end;


  Function DoFNMatch(i,j:longint):Boolean;
  Var
    UTF8, Found : boolean;
  Begin
    Found:=true;
    { ensure that we don't skip partial characters in UTF-8-encoded strings }
    UTF8:=StringCodePage(Name)=CP_UTF8;
    While Found and (i<=LenPat) Do
     Begin
       Case Pattern[i] of
        '?' :
          begin
            Found:=(j<=LenName);
            if UTF8 then
              GoToLastByteOfUtf8CodePoint(j);
          end;
        '*' : Begin
              {find the next character in pattern, different of ? and *}
                while Found do
                  begin
                    inc(i);
                    if i>LenPat then
                      Break;
                    case Pattern[i] of
                      '*' : ;
                      '?' : begin
                              if j>LenName then
                                begin
                                  DoFNMatch:=false;
                                  Exit;
                                end;
                              if UTF8 then
                                GoToLastByteOfUtf8CodePoint(j);
                              inc(j);
                            end;
                      else
                        Found:=false;
                      end;
                 end;
                Assert((i>LenPat) or ( (Pattern[i]<>'*') and (Pattern[i]<>'?') ));
                { Now, find in name the character which i points to, if the * or
                  ? wasn't the last character in the pattern, else, use up all
                  the chars in name }
                Found:=false;
                if (i<=LenPat) then
                  begin
                    repeat
                      {find a letter (not only first !) which matches pattern[i]}
                      if UTF8 then
                        begin
                          while (j<=LenName) and
                                ((name[j]<>pattern[i]) or
                                 not CompareUtf8CodePoint(i,j,false)) do
                            begin
                              GoToLastByteOfUtf8CodePoint(j);
                              inc(j);
                            end;
                        end
                      else
                        begin
                          while (j<=LenName) and (name[j]<>pattern[i]) do
                            inc (j);
                        end;
                      if (j<LenName) then
                        begin
                          { while positions i/j have already been checked, in
                            case of UTF-8 we have to ensure that we don't split
                            a code point. Otherwise we can skip over comparing
                            the same characters twice }
                          if DoFnMatch(i+ord(not UTF8),j+ord(not UTF8)) then
                            begin
                              i:=LenPat;
                              j:=LenName;{we can stop}
                              Found:=true;
                              Break;
                            end
                          { We didn't find one, need to look further }
                          else
                            begin
                              if UTF8 then
                                GoToLastByteOfUtf8CodePoint(j);
                              inc(j);
                            end;
                        end
                      else if j=LenName then
                        begin
                          Found:=true;
                          Break;
                        end;
                      { This 'until' condition must be j>LenName, not j>=LenName.
                        That's because when we 'need to look further' and
                        j = LenName then loop must not terminate. }
                    until (j>LenName);
                  end
                else
                  begin
                    j:=LenName;{we can stop}
                    Found:=true;
                  end;
              end;
        #128..#255:
          begin
            Found:=(j<=LenName) and (pattern[i]=name[j]);
            if Found and UTF8 then
              begin
                { ensure that a part of an UTF-8 codepoint isn't matched with
                  '*' or '?' }
                Found:=CompareUtf8CodePoint(i,j,true);
                { at this point, either Found is false (and we'll stop), or
                  both pattern[i] and name[j] are the end of the current code
                  point and equal }
              end
          end
       else {not a wildcard character in pattern}
         Found:=(j<=LenName) and (pattern[i]=name[j]);
       end;
       inc(i);
       inc(j);
     end;
    DoFnMatch:=Found and (j>LenName);
  end;

Begin {start FNMatch}
  LenPat:=Length(Pattern);
  LenName:=Length(Name);
  FNMatch:=DoFNMatch(1,1);
End;

class function TPath.MatchesPattern(const FileName, Pattern: string;
  const CaseSensitive: Boolean): Boolean;

Var
  lFile,lPattern : String;

begin
  lFile:=FileName;
  lPattern:=Pattern;
  if not CaseSensitive then
    begin
    lFile:=LowerCase(lFile);
    lPattern:=LowerCase(lPattern);
    end;
  if not HasValidFileNameChars(FileName, False) then
    raise EArgumentException.CreateFmt(SErrInvalidCharsInPath, [FileName]);
  Result:=(Pattern=AllFilesMask) or FNMatch(lPattern,lFile);
end;

class function TPath.ChangeExtension(const aPath, Extension: string): string;
begin
  Result:=ChangeFileExt(aPath, Extension);
end;

class function TPath.Combine(const Path1, Path2: string; const ValidateParams : Boolean = True): string;
begin
  Result:=TPath.Combine([Path1,Path2],ValidateParams)
end;

class function TPath.Combine(const Path1, Path2, Path3 : string; const ValidateParams : Boolean = True): string;

begin
  Result:=Combine([Path1,Path2,Path3],ValidateParams);
end;

class function TPath.Combine(const Path1, Path2, Path3,Path4 : string; const ValidateParams : Boolean = True): string;

begin
  Result:=Combine([Path1,Path2,Path3,Path4],ValidateParams);
end;

function AppendPathDelim(const Path: string): string;
begin
  if (Path = '') or (Path[Length(Path)] in AllowDirectorySeparators)
  {$ifdef mswindows}
    //don't add a PathDelim to e.g. 'C:'
    or ((Length(Path) = 2) and (Path[2] = ':') and (UpCase(Path[1]) in ['A'..'Z']))
  {$endif}
  then
    Result:=Path
  else
    Result:=Path + DirectorySeparator;
end;

class function TPath.Combine(const Paths: array of string; const ValidateParams: Boolean = True): string;
var
{$ifdef mswindows} nRoot : SizeInt; {$endif}
  Path: String;
begin
  Result := '';
  for Path in Paths do
  begin
    if Path = '' then
      continue;
    if ValidateParams and not TPath.HasValidPathChars(Path, False) then
      Raise EInOutArgumentException.CreateFmt(SErrInvalidCharsInPath,[Path],Path);
  {$ifdef mswindows}
    // Path starts with one \: root-relative.
    if (Path[1] in AllowDirectorySeparators) and ((Length(Path) < 2) or not (Path[2] in AllowDirectorySeparators)) then
    begin
      nRoot := SkipRoot(Result);
      if (nRoot > 0) and (Result[nRoot] in AllowDirectorySeparators) then
        dec(nRoot); // Skip trailing \ if present, as Path already starts with a separator.
      Result := Copy(Result, 1, nRoot) + Path;
    end else
  {$endif}
    if TPath.IsRelativePath(Path) then
      Result := AppendPathDelim(Result) + Path
    else
      Result := Path;
  end;
end;

class function TPath.GetDirectoryName(FileName: string): string;
begin
  Result:=ExcludeTrailingPathDelimiter(ExtractFileDir(FileName));
end;

class function TPath.GetExtension(const FileName: string): string;
begin
  Result:=ExtractFileExt(FileName);
end;

class function TPath.GetFileName(const FileName: string): string;
begin
  Result:=ExtractFileName(FileName);
end;

class function TPath.GetFileNameWithoutExtension(const FileName: string
  ): string;
begin
  Result:=ChangeFileExt(ExtractFileName(FileName), '');
end;

class function TPath.GetFullPath(const aPath: string): string;
begin
  Result:=ExpandFileName(aPath);
end;

class function TPath.GetInvalidFileNameChars: TCharArray;

Const
   ExtraChars : Array of Char
   {$IFNDEF UNIX}
     = ('"', '*', '/', ':', '<', '>', '?', '\', '|');
   {$ELSE}
     = ( '/', '~');
   {$ENDIF}

Var
  I : Integer;

begin
  if Length(FInvalidFileNameChars)=0 then
    begin
    SetLength(FInvalidFileNameChars,32+Length(ExtraChars));
    For I:=0 to 31 do
      FInvalidFileNameChars[i]:=Char(I);
    For I:=0 to Length(ExtraCHars)-1 do
      FInvalidFileNameChars[32+I]:=ExtraChars[i];
    end;
  Result:=FInvalidFilenameChars;
end;

class function TPath.GetInvalidPathChars: TCharArray;

Const
   {$IFDEF UNIX}
   ExtraChars : Array of Char = ( '"', '<', '>', '|' );
   {$ELSE}
   ExtraChars : Array of Char = ();
   {$ENDIF}
Var
  I : Integer;

begin
  if Length(FInvalidPathChars)=0 then
    begin
    SetLength(FInvalidPathChars,32+Length(ExtraChars));
    For I:=0 to 31 do
      FInvalidPathChars[i]:=Char(I);
    For I:=0 to Length(ExtraCHars)-1 do
      FInvalidPathChars[32+I]:=ExtraChars[i];
    end;
  Result:=FInvalidPathChars;

end;

class function TPath.GetPathRoot(const aPath: string): string;
begin
  if Trim(aPath) = '' then
    raise EInOutError.Create(SErrEmptyPath);
  if not HasValidPathChars(aPath, True) then
    raise EInOutError.CreateFmt(SErrInvalidCharsInPath, [aPath]);

  Result:=IntGetPathRoot(aPath);
end;

{$IF DEFINED(Unix)}
class function TPath.IntGetPathRoot(const aPath: string): string;

begin
  if (aPath <> '') and (aPath.Chars[0] = PathDelim) then
    Result:=PathDelim
  else
    Result:='';
end;
{$ELSEIF DEFINED(WINDOWS)}
class function TPath.IntGetPathRoot(const aPath: string): string;

var
  lPath: string;
  NeedSeparator: Boolean;
  aPos, ResLen, len: Integer;
  PPT: TPathPrefixType;

begin
  lPath:=SetDirSeparators(aPath);
  len:=Length(lPath);
  NeedSeparator:=False;
  aPos:=SkipExtendedPrefix(lPath, PPT);
  ResLen:=0;
  if IsDriveRooted(lPath) then  // Drive letter
    begin
    ResLen:=aPos+1;
    NeedSeparator:=(Len > 2) and (lPath[aPos]=PathDelim);
    if NeedSeparator and (PPT in [TPathPrefixType.pptExtended, TPathPrefixType.pptExtendedUNC]) then
      NeedSeparator:=False;
    end
  else if IsUNCRooted(aPath) then // UNC aPath
    begin
      aPos:=Pos(PathDelim,lPath,3);
      if aPos > 0 then
        begin
        ResLen:=apos;
        aPos:=Pos(PathDelim,aPath,aPos+1);
        if aPos>0 then
          ResLen:=aPos-1
        end
      else
        ResLen:=Len;
    end
  else if aPos<=Len then
    begin
    ResLen:= Ord(lPath[aPos]=PathDelim);
    if aPos<Len then
      ResLen:=ResLen+Ord(lPath[aPos+1]=PathDelim);
    end;
  Result:=Copy(lPath,1,ResLen);
  if NeedSeparator then
    Result:=Result+PathDelim;
end;
{$ELSEIF DEFINED(HASAMIGA)}
class function TPath.IntGetPathRoot(const aPath: string): string;
begin
  if Pos(DriveSeparator, aPath) > 0 then
    Result := Copy(aPath, 1, Pos(DriveSeparator, aPath))
  else
    Result := '';
end;
{$ELSE}
class function TPath.IntGetPathRoot(const aPath: string): string;
begin
  Result:='';
end;
{$ENDIF}


class function TPath.GetRandomFileName: string;

Const
  SDigits = '01234567890';
  SUppers = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  SLowers = 'abcdefghijklmnopqrstuvwxyz';

  SelectChars : Array[0..2] of string = (SDigits,SUppers,SLowers);
  SelectLengths : Array[0..2] of integer = (Length(SDigits),Length(SUppers),Length(SLowers));
  FNLen = 12;
  ExtLen = 3;
  DotAt = FNLen-ExtLen;

var
  C,I: Byte;

begin
  Result:=''; // DO NOT LOCALIZE
  SetLength(Result,FNLen);
  for i:=1 to FNLen do
    if i <> DotAt then
      begin
      C:=Random(3);
      Result[I]:=SelectChars[C][1+Random(SelectLengths[C])];
      end
    else
      Result[i]:=ExtensionSeparatorChar;
end;

class function TPath.GetTempFileName: string;
begin
  Result:={$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}SysUtils.GetTempFileName;
end;

class function TPath.GetTempPath: string;
begin
  Result:=IncludeTrailingPathDelimiter({$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}SysUtils.GetTempDir);
end;

class function TPath.GetHomePath: string;
begin
  Result:={$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}SysUtils.GetUserDir;
end;

{$ifdef UNIX}
type
  TSpecialDir = (sdDesktop, sdDocuments, sdDownloads, sdMusic, sdPictures, sdPublic, sdTemplates, sdVideos);
{$IFNDEF darwin}
function GetSpecialDir(const AType: TSpecialDir): string;

const
  Names : array[TSpecialDir] of string
        = ('DESKTOP', 'DOCUMENTS', 'DOWNLOAD',  'MUSIC', 'PICTURES', 'PUBLICSHARE', 'TEMPLATES', 'VIDEOS');

var
  cfg,varname: string;
  L: TStringList;
begin
  Result := '';
  // XDG variable name
  varName:=Format('XDG_%s_DIR',[Names[AType]]);
  Cfg:=GetEnvironmentVariable('XDG_CONFIG_HOME');
  if (Cfg='') then
    Cfg:=GetUserDir+'.config/user-dirs.dirs'
  else
    CFG:=IncludeTrailingPathDelimiter(CFG)+'user-dirs.dirs';
  if not FileExists(Cfg) then
    Exit;
  L:=TStringList.Create;
  try
    L.LoadFromFile(Cfg);
    Result:=AnsiDequotedStr(L.Values[VarName],'"');
  finally
    FreeAndNil(L);
  end;
  Result:=StringReplace(Result,'$HOME', ExcludeTrailingPathDelimiter(GetUserDir), [rfIgnoreCase]);
end;
{$else}
function GetSpecialDir(const AType: TSpecialDir): string;

begin
  // Todo
  Result:='';
end;
{$endif}
{$endif}

class function TPath.GetDocumentsPath: string;
begin
  Result:='';
  {$IfDef MSWINDOWS}
    Result:=GetWindowsSpecialDir(CSIDL_PERSONAL, False);
  {$ELSE}
    {$IFDEF UNIX}
      Result:=GetSpecialDir(TSpecialDir.sdDocuments);
    {$ELSE}
      Result:=GetUserDir;
    {$ENDIF}
  {$ENDIF}
end;

class function TPath.GetDesktopPath: string;
begin
  Result:='';
  {$IfDef MSWINDOWS}
    Result:=GetWindowsSpecialDir(CSIDL_DESKTOPDIRECTORY, False);
  {$ELSE}
    {$IFDEF UNIX}
      Result:=GetSpecialDir(TSpecialDir.sdDesktop);
    {$ELSE}
      Result:=GetUserDir;
    {$ENDIF}
  {$EndIf}
end;

class function TPath.GetSharedDocumentsPath: string;
begin
  Result:='';
  {$IfDef MSWINDOWS}
    Result:=GetWindowsSpecialDir(CSIDL_COMMON_DOCUMENTS, False);
  {$ELSE}
    {$IFDEF UNIX}
      Result:=GetSpecialDir(TSpecialDir.sdPublic);
    {$ELSE}
      Result:=GetUserDir;
    {$ENDIF}
  {$EndIf}
end;

class function TPath.GetLibraryPath: string;
begin
{$IFDEF UNIX}
  Result := GetCurrentDir;
{$ELSE}
  Result:=ExtractFilePath(ParamStr(0));
{$ENDIF}
end;

class function TPath.GetAppPath: string;
begin
  Result:=ExtractFilePath(ParamStr(0));
end;

class function TPath.GetCachePath: string;
begin
  {$IfDef MSWINDOWS}
    Result:=GetWindowsSpecialDir(CSIDL_LOCAL_APPDATA, False);
  {$ELSE}
    {$IFDEF UNIX}
      Result:=GetUserDir+'.cache'; // Check darwin
    {$ELSE}
    Result:={$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}SysUtils.GetTempDir;
    {$ENDIF}
  {$EndIf}
end;

class function TPath.GetPublicPath: string;
begin
  Result:='';
  {$IfDef MSWINDOWS}
    Result:=GetWindowsSpecialDir(CSIDL_COMMON_APPDATA, False);
  {$ELSE}
    {$IFDEF UNIX}
      Result:=GetSpecialDir(TSpecialDir.sdPublic);
    {$ELSE}
      Result:=GetUserDir;
    {$ENDIF}
  {$EndIf}
end;

class function TPath.GetPicturesPath: string;
begin
  Result:='';
  {$IfDef MSWINDOWS}
    Result:=GetWindowsSpecialDir(CSIDL_MYPICTURES, False);
  {$ELSE}
    {$IFDEF UNIX}
      Result:=GetSpecialDir(TSpecialDir.sdPictures);
    {$ELSE}
      Result:=GetUserDir;
    {$ENDIF}
  {$EndIf}
end;

class function TPath.GetSharedPicturesPath: string;
begin
  Result:='';
  {$IfDef MSWINDOWS}
    Result:=GetWindowsSpecialDir(CSIDL_COMMON_PICTURES, False);
  {$ELSE}
    {$IFDEF UNIX}
      Result:=GetSpecialDir(TSpecialDir.sdPublic);
    {$ELSE}
      Result:=GetUserDir;
    {$ENDIF}
  {$EndIf}
end;

class function TPath.GetCameraPath: string;
begin
  Result:='';
  {$IfDef MSWINDOWS}
    Result:=GetWindowsSpecialDir(CSIDL_MYPICTURES, False);
  {$EndIf}
end;

class function TPath.GetSharedCameraPath: string;
begin
  Result:='';
  {$IfDef MSWINDOWS}
    Result:=GetWindowsSpecialDir(CSIDL_COMMON_PICTURES, False);
  {$ELSE}
    {$IFDEF UNIX}
      Result:=GetSpecialDir(TSpecialDir.sdPublic);
    {$ELSE}
      Result:=GetUserDir;
    {$ENDIF}
  {$EndIf}
end;

class function TPath.GetMusicPath: string;
begin
  Result:='';
  {$IfDef MSWINDOWS}
    Result:=GetWindowsSpecialDir(CSIDL_MYMUSIC, False);
  {$ELSE}
    {$IFDEF UNIX}
      Result:=GetSpecialDir(TSpecialDir.sdMusic);
    {$ELSE}
      Result:=GetUserDir;
    {$ENDIF}
  {$EndIf}
end;

class function TPath.GetSharedMusicPath: string;
begin
  Result:='';
  {$IfDef MSWINDOWS}
    Result:=GetWindowsSpecialDir(CSIDL_COMMON_MUSIC, False);
  {$ELSE}
    {$IFDEF UNIX}
      Result:=GetSpecialDir(TSpecialDir.sdPublic);
    {$ELSE}
      Result:=GetUserDir;
    {$ENDIF}
  {$EndIf}
end;

class function TPath.GetMoviesPath: string;
begin
  Result:='';
  {$IfDef MSWINDOWS}
    Result:=GetWindowsSpecialDir(CSIDL_MYVIDEO, False);
  {$ELSE}
    {$IFDEF UNIX}
      Result:=GetSpecialDir(TSpecialDir.sdVideos);
    {$ELSE}
      Result:=GetUserDir;
    {$ENDIF}
  {$EndIf}
end;

class function TPath.GetSharedMoviesPath: string;
begin
  Result:='';
  {$IfDef MSWINDOWS}
    Result:=GetWindowsSpecialDir(CSIDL_COMMON_VIDEO, False);
  {$ELSE}
    {$IFDEF UNIX}
      Result:=GetSpecialDir(TSpecialDir.sdPublic);
    {$ELSE}
      Result:=GetUserDir;
    {$ENDIF}
  {$EndIf}
end;

class function TPath.GetAlarmsPath: string;
begin
  Result:='';
  {$IfDef MSWINDOWS}
    Result:=GetWindowsSpecialDir(CSIDL_MYMUSIC, False);
  {$ELSE}
    {$IFDEF UNIX}
      Result:=GetSpecialDir(TSpecialDir.sdMusic);
    {$ELSE}
      Result:=GetUserDir;
    {$ENDIF}
  {$EndIf}
end;

class function TPath.GetSharedAlarmsPath: string;
begin
  Result:='';
  {$IfDef MSWINDOWS}
    Result:=GetWindowsSpecialDir(CSIDL_COMMON_MUSIC, False);
  {$ELSE}
    {$IFDEF UNIX}
      Result:=GetSpecialDir(TSpecialDir.sdPublic);
    {$ELSE}
      Result:=GetUserDir;
    {$ENDIF}
  {$EndIf}
end;

class function TPath.GetDownloadsPath: string;
begin
  Result:='';
  {$IfDef MSWINDOWS}
    Result:=GetWindowsSpecialDir(CSIDL_LOCAL_APPDATA, False);
  {$ELSE}
    {$IFDEF UNIX}
      Result:=GetSpecialDir(TSpecialDir.sdDownloads);
    {$ELSE}
      Result:=GetUserDir;
    {$ENDIF}
  {$EndIf}
end;

class function TPath.GetSharedDownloadsPath: string;
begin
  Result:='';
  {$IfDef MSWINDOWS}
    Result:=GetWindowsSpecialDir(CSIDL_COMMON_APPDATA, False);
  {$ELSE}
    {$IFDEF UNIX}
      Result:=GetSpecialDir(TSpecialDir.sdPublic);
    {$ELSE}
      Result:=GetUserDir;
    {$ENDIF}
  {$EndIf}
end;

class function TPath.GetRingtonesPath: string;
begin
  Result:='';
  {$IfDef MSWINDOWS}
    Result:=GetWindowsSpecialDir(CSIDL_MYMUSIC, False);
  {$ELSE}
    {$IFDEF UNIX}
      Result:=GetSpecialDir(TSpecialDir.sdMusic);
    {$ELSE}
      Result:=GetUserDir;
    {$ENDIF}
  {$EndIf}
end;

class function TPath.GetSharedRingtonesPath: string;
begin
  Result:='';
  {$IfDef MSWINDOWS}
    Result:=GetWindowsSpecialDir(CSIDL_COMMON_MUSIC, False);
  {$ELSE}
    {$IFDEF UNIX}
      Result:=GetSpecialDir(TSpecialDir.sdPublic);
    {$ELSE}
      Result:=GetUserDir;
    {$ENDIF}
  {$EndIf}
end;

class function TPath.GetTemplatesPath: string;

begin
  Result:='';
{$IfDef MSWINDOWS}
  Result:=GetWindowsSpecialDir(CSIDL_PERSONAL, False);
{$ELSE}
  {$IFDEF UNIX}
    Result:=GetSpecialDir(TSpecialDir.sdTemplates);
  {$ELSE}
    Result:=GetUserDir;
  {$ENDIF}
{$EndIf}

end;

class function TPath.Exists(const aPath: string; aFollowLink: Boolean): Boolean;
begin
  Result:=TDirectory.Exists(aPath, aFollowLink) or TFile.Exists(aPath, aFollowLink);
end;

class function TPath.GetAttributes(const aPath: string; aFollowLink: Boolean
  ): TFileAttributes;
begin
  Result:=TFile.GetAttributes(aPath, aFollowLink);
end;

class procedure TPath.SetAttributes(const aPath: string;
  const aAttributes: TFileAttributes);
begin
  TFile.SetAttributes(aPath, aAttributes);
end;

class function TPath.HasExtension(const aPath: string): Boolean;
begin
  Result:=not (aPath = ChangeFileExt(aPath, ''));
end;

class function TPath.IsPathRooted(const aPath: string): Boolean;
begin
  Result:=aPath.StartsWith(PathDelim) or TPath.IsDriveRooted(aPath);
end;

{ TFile }

class procedure TFile.GetFileTimestamps(const aFilename: TFileName; var aCreate, aWrite, aAccess: TDateTime; IsUTC: Boolean);

var
  DateTime: TDateTimeInfoRec;

begin
   if FileGetDateTimeInfo(aFileName,DateTime) then
     begin
     aCreate:=DateTime.CreationTime;
     aWrite:=DateTime.TimeStamp;
     aAccess:=DateTime.LastAccessTime;
     if isUTC then
       begin
       aCreate:=LocalTimeToUniversal(aCreate);
       aWrite:=LocalTimeToUniversal(aWrite);
       aAccess:=LocalTimeToUniversal(aAccess);
       end;
     end
   else
     raise EInOutError.CreateFmt(SErrFileNotFound, [aFileName]);
end;

class function TFile.IntegerToFileAttributes(const Attributes: Integer
  ): TFileAttributes;
  procedure AddIfSet(var FileAttribs: TFileAttributes; const BitValue: Integer; FileAttrib: TFileAttribute);
  begin
    if (Attributes and BitValue) = BitValue then
      FileAttribs:=FileAttribs + [FileAttrib];
  end;
begin
  {$If Defined(UNIX)}
    // Assume full mode
    Result:=ModeToFileAttributes(Attributes);
  {$ElseIf Defined(WINDOWS)}
    // Assume all flags
    Result:=FlagsToFileAttributes(Attributes);
  {$Else}
    { Attributes supported by TSearchRec}
    Result:=[];
    AddIfSet(Result, {$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}SysUtils.faDirectory,         TFileAttribute.faDirectory);
    AddIfSet(Result, {$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}SysUtils.faSymLink{%H-},      TFileAttribute.faSymLink);
    AddIfSet(Result, {$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}SysUtils.faNormal,            TFileAttribute.faNormal);
    AddIfSet(Result, {$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}SysUtils.faDirectory,  TFileAttribute.faDirectory);
    AddIfSet(Result, {$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}SysUtils.faSymLink{%H-},    TFileAttribute.faSymLink);
    AddIfSet(Result, {$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}SysUtils.faHidden{%H-},     TFileAttribute.faHidden);
    AddIfSet(Result, {$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}SysUtils.faSysFile{%H-},    TFileAttribute.faSystem);
    AddIfSet(Result, {$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}SysUtils.faArchive,    TFileAttribute.faArchive);
  {$EndIf}
end;

{$IFDEF UNIX}
// We need full mode here, not just what TSearchRec has to offer
function FileGetMode(const FN: string; FollowLink: Boolean): Integer;
var
  st: tstat;
  Res : Integer;

begin
  Result:=-1;
  if FollowLink then
    Res:=fpstat(FN,st)
  else
    Res:=fplstat(FN, st);
  if Res=0 then
    Result := st.st_mode
end;
{$ENDIF UNIX}


class function TFile.FileAttributesToInteger(const Attributes: TFileAttributes
  ): Integer;
  procedure AddIfSet(var AttribValue: Integer; const BitValue: Integer; FileAttrib: TFileAttribute);
  begin
    if FileAttrib in Attributes then
      AttribValue:=AttribValue or BitValue;
  end;
begin
  Result:=0;
  {$IFDEF UNIX}
  // Assume full mode
  Result:=FileAttributesToMode(Attributes);
  {$ELSE}
    {$IFDEF WINDOWS}
      // Assume all flags
      Result:=FileAttributesToFlags(Attributes);
    {$ELSE}
       // Assume attrs as in TSearchRec
      AddIfSet(Result, {$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}SysUtils.faDirectory,  TFileAttribute.faDirectory);
      AddIfSet(Result, {$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}SysUtils.faSymLink{%H-},    TFileAttribute.faSymLink);
      AddIfSet(Result, {$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}SysUtils.faNormal,     TFileAttribute.faNormal);
      AddIfSet(Result, {$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}SysUtils.faReadOnly,   TFileAttribute.faReadOnly);
      AddIfSet(Result, {$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}SysUtils.faHidden{%H-},     TFileAttribute.faHidden);
      AddIfSet(Result, {$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}SysUtils.faSysFile{%H-},    TFileAttribute.faSystem);
      AddIfSet(Result, {$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}SysUtils.faArchive,    TFileAttribute.faArchive);
    {$EndIf}
  {$EndIf}
end;

class function TFile.Create(const aPath: string): TFileStream;
begin
  Result:=Create(aPath,0);
end;

class function TFile.Create(const aPath: string; const BufferSize: Integer
  ): TFileStream;
begin
  Result:=TFileStream.Create(aPath,{$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}Classes.fmCreate);
end;

class function TFile.OpenOrCreate(const aPath: string): TFileStream;
begin
  If Exists(aPath) then
    Result:=Open(aPath,TfileMode.fmOpen)
  else
    Result:=Create(aPath);
end;

class function TFile.DetectFileEncoding(const aPath: String; out
  BOMLength: Integer): TEncoding;

Var
  B : TBytes;
  Count: LongInt;

begin
  With TFileStream.Create(aPath,fmOpenRead or fmShareDenyWrite) do
    try
      SetLength(B,4);
      Count:=FileRead(Handle,B[0],4);
      If Count<0 then
        raise EReadError.CreateFmt('Could not read file: %s',[aPath]);
      SetLength(B,Count);
      Result:=nil;
      BOMLength:=TEncoding.GetBufferEncoding(B,Result,TEncoding.UTF8);
    finally
      Free;
    end;
end;

class procedure TFile.AppendAllText(const aPath, aContents: string);

Var
  Encoding : TEncoding;
  BOMLength : Integer;

begin
  if FileExists(aPath) then
    Encoding:=DetectFileEncoding(aPath,BOMlength)
  else
    Encoding:=TEncoding.UTF8;
  AppendAllText(aPath,aContents,Encoding);
end;

class procedure TFile.AppendAllText(const aPath, Contents: string;
  const Encoding: TEncoding);

Var
  B : TBytes;
  F : TFileStream;

begin
  If Encoding=nil then
    raise EInOutArgumentException.Create('Encoding must not be nil',aPath);
  F:=OpenOrCreate(aPath);
  try
    {$IF SIZEOF(CHAR)=1}
    B:=Encoding.GetAnsiBytes(Contents);
    {$ELSE}
    B:=Encoding.GetBytes(Contents);
    {$ENDIF}
    F.Seek(0,soEnd);
    If Length(B)>0 then
      F.WriteBuffer(B[0],Length(B));
  finally
    F.Free;
  end;
end;

class function TFile.AppendText(const aPath: string): TStreamWriter;
begin
  Result:=TStreamWriter.Create(aPath,True)
end;

type
  TCopyFileFlag = (
    cffOverwriteFile,
    cffCreateDestDirectory,
    cffPreserveTime
    );
  TCopyFileFlags = set of TCopyFileFlag;


function CopyFile(const SrcFilename, DestFilename: string; Flags: TCopyFileFlags; ExceptionOnError: Boolean): boolean;
var
  SrcHandle: THandle;
  DestHandle: THandle;
  Buffer: array[1..4096] of byte;
  ReadCount, WriteCount, TryCount: LongInt;
begin
  Result:=False;
  if SameFileIdentity(SrcFilename,DestFilename) then
    begin
    if ExceptionOnError then
      raise EInOutError.Create('Source and destination refer to the same file');
    Exit;
    end;
  // check overwrite
  if (not (TCopyFileFlag.cffOverwriteFile in Flags)) and FileExists(DestFileName) then
    begin
    If ExceptionOnError then
      raise EInOutError.CreateFmt(SErrFileExists,[DestFileName]);
    Exit;
    end;
  // check directory
  if (TCopyFileFlag.cffCreateDestDirectory in Flags)
     and (not DirectoryExists(ExtractFilePath(DestFileName)))
     and (not ForceDirectories(ExtractFilePath(DestFileName))) then
    exit;
  TryCount:=0;
  While TryCount <> 3 Do Begin
    SrcHandle:=FileOpen(SrcFilename, fmOpenRead or fmShareDenyWrite);
    if THandle(SrcHandle)=feInvalidHandle then Begin
      Inc(TryCount);
      Sleep(10);
    End
    Else Begin
      TryCount:=0;
      Break;
    End;
  End;
  If TryCount > 0 Then
  begin
    if ExceptionOnError then
      raise EFOpenError.CreateFmt({SFOpenError}'Unable to open file "%s"', [SrcFilename])
    else
      exit;
  end;
  try
    DestHandle:=FileCreate(DestFileName);
    if (THandle(DestHandle)=feInvalidHandle) then
    begin
      if ExceptionOnError then
        raise EFCreateError.CreateFmt({SFCreateError}'Unable to create file "%s"',[DestFileName])
      else
        Exit;
    end;
    try
      repeat
        ReadCount:=FileRead(SrcHandle,Buffer[1],High(Buffer));
        If ReadCount<0 then
          begin
          If ExceptionOnError then
            raise EReadError.CreateFmt('Unable to read file "%s"',[SrcFilename]);
          Exit;
          end;
        If ReadCount=0 then Break;
        WriteCount:=FileWrite(DestHandle,Buffer[1],ReadCount);
        if WriteCount<ReadCount then
        begin
          if ExceptionOnError then
            raise EWriteError.CreateFmt({SFCreateError}'Unable to write to file "%s"',[DestFileName])
          else
            Exit;
        end;
      until false;
    finally
      FileClose(DestHandle);
    end;
    if (TCopyFileFlag.cffPreserveTime in Flags) then
      FileSetDate(DestFilename, FileGetDate(SrcHandle));
    Result:=True;
  finally
    FileClose(SrcHandle);
  end;
end;


class procedure TFile.Copy(const SourceFileName, DestFileName: string);
begin
   CopyFile(SourceFileName, DestFileName, [TCopyFileFlag.cffPreserveTime],True);
end;

class procedure TFile.Copy(const SourceFileName, DestFileName: string;
  const Overwrite: Boolean);
begin
  if Overwrite then
    CopyFile(SourceFileName, DestFileName, [TCopyFileFlag.cffOverwriteFile, TCopyFileFlag.cffPreserveTime],True)
  else
    CopyFile(SourceFileName, DestFileName, [TCopyFileFlag.cffPreserveTime],True);
end;

class function TFile.CreateSymLink(const Link, Target: string): Boolean;
begin
  Result:=CreatePathLink(Link,Target);
end;

class function TFile.CreateText(const aPath: string): TStreamWriter;
begin
  Result:=TStreamWriter.Create(aPath,False);
end;

class procedure TFile.Delete(const aPath: string);
begin
  if not {$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}SysUtils.DeleteFile(aPath) then
    RaisePathError(aPath,GetLastOSError);
end;

class function TFile.Exists(const aPath: string; FollowLink: Boolean): Boolean;
begin
  Result:=FileExists(aPath, FollowLink);
end;

class procedure TFile.SetFileTimestamps(const aFilename: TFileName;
  const aCreate, aWrite, aAccess: PDateTime; IsUTC: Boolean);
{$IFDEF MSWINDOWS}
var
  FileHandle: THandle;
  Flags: Cardinal;
  CreateTime,WriteTime,AccessTime: TFileTime;
  CreateTimePtr,WriteTimePtr,AccessTimePtr: PFileTime;

  function ToFileTime(const aValue: TDateTime): TFileTime;
  var
    SystemTime: TSystemTime;
    LocalFileTime: TFileTime;
  begin
    DateTimeToSystemTime(aValue,SystemTime);
    if not SystemTimeToFileTime(SystemTime,LocalFileTime) then
      raise EArgumentOutOfRangeException.Create('Invalid date/timestamp');
    if IsUTC then
      Result:=LocalFileTime
    else if not LocalFileTimeToFileTime(LocalFileTime,Result) then
      RaiseLastOSError;
  end;

begin
  CreateTimePtr:=Nil;
  WriteTimePtr:=Nil;
  AccessTimePtr:=Nil;
  if aCreate<>Nil then
    begin
    CreateTime:=ToFileTime(aCreate^);
    CreateTimePtr:=@CreateTime;
    end;
  if aWrite<>Nil then
    begin
    WriteTime:=ToFileTime(aWrite^);
    WriteTimePtr:=@WriteTime;
    end;
  if aAccess<>Nil then
    begin
    AccessTime:=ToFileTime(aAccess^);
    AccessTimePtr:=@AccessTime;
    end;
  Flags:=FILE_ATTRIBUTE_NORMAL;
  if (GetFileAttributes(PChar(aFilename)) and FILE_ATTRIBUTE_DIRECTORY)<>0 then
    Flags:=FILE_FLAG_BACKUP_SEMANTICS;
  FileHandle:=CreateFile(PChar(aFilename),FILE_WRITE_ATTRIBUTES,
    FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE,Nil,OPEN_EXISTING,
    Flags,0);
  if FileHandle=INVALID_HANDLE_VALUE then
    RaiseLastOSError;
  try
    if not SetFileTime(FileHandle,CreateTimePtr,AccessTimePtr,WriteTimePtr) then
      RaiseLastOSError;
  finally
    CloseHandle(FileHandle);
  end;
end;
{$ELSE MSWINDOWS}
{$IFDEF UNIX}
var
  Info: TStat;
  Times: TUTimBuf;
  FileNameBytes: RawByteString;
begin
  FileNameBytes:=UTF8Encode(aFilename);
  if fpStat(PAnsiChar(FileNameBytes),Info)<>0 then
    RaiseLastOSError;
  { POSIX has no portable creation-time setter.  Delphi likewise validates
    the path and deliberately leaves creation time unchanged. }
  if (aWrite=Nil) and (aAccess=Nil) then
    Exit;
  Times.actime:=Info.st_atime;
  Times.modtime:=Info.st_mtime;
  if aAccess<>Nil then
    Times.actime:=DateTimeToUnix(aAccess^,IsUTC);
  if aWrite<>Nil then
    Times.modtime:=DateTimeToUnix(aWrite^,IsUTC);
  if fpUTime(PAnsiChar(FileNameBytes),@Times)<>0 then
    RaiseLastOSError;
end;
{$ELSE UNIX}
begin
  if (aWrite<>Nil) and (FileSetDate(aFilename,aWrite^)<>0) then
    raise EInOutError.CreateFmt(SErrFileNotFound,[aFilename]);
end;
{$ENDIF UNIX}
{$ENDIF MSWINDOWS}

{$IFDEF MSWINDOWS}
{ canonicalize a long or overflowing path for the W API: the two-call
  GetFullPathNameW resolves relative, drive-relative, dot and
  forward-slash forms (a raw '\\?\'+Path prefix disables exactly that
  normalization inside the API, so prefixing a relative path never
  worked); canonical UNC gets '\\?\UNC\', a drive path gets '\\?\' }
function MakeWinApiPath(const Path: string): string;
var
  Len: DWORD;
begin
  if TPath.IsExtendedPrefixed(Path) or
     ((Length(Path)>=4) and (Copy(Path,1,4)='\\.\')) then
    Exit(Path);
  Len:=GetFullPathNameW(PWideChar(Path),0,nil,nil);
  if Len=0 then
    exit(Path);
  SetLength(Result,Len);
  Len:=GetFullPathNameW(PWideChar(Path),Len,PWideChar(Result),nil);
  if (Len=0) or (Len>=DWORD(Length(Result))) then
    exit(Path);
  SetLength(Result,Len);
  if (Length(Result)>=2) and (Result[1]='\') and (Result[2]='\') then
    Result:='\\?\UNC\'+Copy(Result,3,Length(Result)-2)
  else
    Result:='\\?\'+Result;
end;
{$ENDIF}

class function TFile.GetSize(const Path: string): Int64;
{$IFDEF MSWINDOWS}
var
  Info: TWin32FileAttributeData;
begin
  { the short-path hit stays 0 allocations + 1 GetFileAttributesExW;
    '\\?\' and '\\.\' pass through untouched }
  if TPath.IsExtendedPrefixed(Path) or
     ((Length(Path)>=4) and (Path[1]='\') and (Path[2]='\') and
      (Path[3]='.') and (Path[4]='\')) then
    begin
    if GetFileAttributesEx(PChar(Path),GetFileExInfoStandard,@Info) then
      exit((Int64(Info.nFileSizeHigh) shl 32)+Info.nFileSizeLow);
    exit(-1);
    end;
  if Length(Path)<MAX_PATH then
    begin
    if GetFileAttributesEx(PChar(Path),GetFileExInfoStandard,@Info) then
      exit((Int64(Info.nFileSizeHigh) shl 32)+Info.nFileSizeLow);
    { a short path whose expanded absolute form exceeds MAX_PATH }
    if GetLastError<>ERROR_FILENAME_EXCED_RANGE then
      exit(-1);
    end;
  if GetFileAttributesEx(PChar(MakeWinApiPath(Path)),GetFileExInfoStandard,@Info) then
    Result:=(Int64(Info.nFileSizeHigh) shl 32)+Info.nFileSizeLow
  else
    Result:=-1;
end;
{$ELSE}
{$IFDEF UNIX}
var
  Info: TStat;
begin
  if fpStat(Path,Info)=0 then
    Result:=Info.st_size
  else
    Result:=-1;
end;
{$ELSE}
var
  Info: TSearchRec;
begin
  if FindFirst(Path,faAnyFile,Info)=0 then
    try
      Result:=Info.Size;
    finally
      FindClose(Info);
    end
  else
    Result:=-1;
end;
{$ENDIF UNIX}
{$ENDIF MSWINDOWS}

class function TFile.GetAttributes(const aPath: string; FollowLink: Boolean
  ): TFileAttributes;
var
  Attr,Code: Integer;
begin
  Attr:={$ifdef unix}FileGetMode(aPath,FollowLink){$else}FileGetAttr(aPath){$endif};
  if Attr<0 then
    begin
    Code:=GetLastOSError;
    if MissingPathError(Code) then
      raise EFileNotFoundException.CreateFmt('File not found: %s',[aPath]);
    RaisePathError(aPath,Code);
    end;
  Result:=IntegerToFileAttributes(Attr);
end;

class function TFile.GetCreationTime(const aPath: string): TDateTime;

var
  Dummy1, Dummy2: TDateTime;
begin
  Result:=MinDateTime;
  Dummy1:=MinDateTime;
  Dummy2:=MinDateTime;
  GetFileTimestamps(aPath, Result, Dummy1, Dummy2, False);
end;

class function TFile.GetCreationTimeUtc(const aPath: string): TDateTime;
var
  Dummy1, Dummy2: TDateTime;
begin
  Result:=MinDateTime;
  Dummy1:=MinDateTime;
  Dummy2:=MinDateTime;
  GetFileTimestamps(aPath, Result, Dummy1, Dummy2, True);
end;

class function TFile.GetLastAccessTime(const aPath: string): TDateTime;
var
  Dummy1, Dummy2: TDateTime;
begin
  Result:=MinDateTime;
  Dummy1:=MinDateTime;
  Dummy2:=MinDateTime;
  GetFileTimestamps(aPath, Dummy1, Dummy2, Result, False);
end;

class function TFile.GetLastAccessTimeUtc(const aPath: string): TDateTime;
var
  Dummy1, Dummy2: TDateTime;
begin
  Result:=MinDateTime;
  Dummy1:=MinDateTime;
  Dummy2:=MinDateTime;
  GetFileTimestamps(aPath, Dummy1, Dummy2, Result,True);
end;

class function TFile.GetLastWriteTime(const aPath: string): TDateTime;
var
  Dummy1, Dummy2: TDateTime;
begin
  Result:=MinDateTime;
  Dummy1:=MinDateTime;
  Dummy2:=MinDateTime;
  GetFileTimestamps(aPath, Dummy1, Result, Dummy2, False);
end;

class function TFile.GetLastWriteTimeUtc(const aPath: string): TDateTime;
var
  Dummy1, Dummy2: TDateTime;
begin
  Result:=MinDateTime;
  Dummy1:=MinDateTime;
  Dummy2:=MinDateTime;
  GetFileTimestamps(aPath, Dummy1, Result, Dummy2,True);
end;

class function TFile.GetSymLinkTarget(const aFileName: string;
  var SymLinkRec: TSymLinkRec): Boolean;
begin
  Result:=FileGetSymLinkTarget(aFileName,SymLinkRec);
end;

class function TFile.GetSymLinkTarget(const aFileName: string;
  var TargetName: RawByteString): Boolean;
begin
  Result:=FileGetSymLinkTarget(aFileName,TargetName);
end;

class function TFile.GetSymLinkTarget(const aFileName: Unicodestring;
  var TargetName: UnicodeString): Boolean;
begin
  Result:=FileGetSymLinkTarget(aFileName,TargetName);
end;

class procedure TFile.Move(SourceFileName, DestFileName: string);
begin
  if FileExists(DestFileName) then
    raise EInOutError.CreateFmt(SerrFileExists, [DestFileName]);
  if RenameFile(SourceFileName, DestFileName) then
    Exit;
  Copy(SourceFileName, DestFileName);
  if FileExists(DestFileName) and FileExists(SourceFileName) then
    Delete(SourceFileName);
end;

class function TFile.Open(const aPath: string; const aMode: TFileMode
  ): TFileStream;
begin
  Result:=Open(aPath,aMode,TFileAccess.faReadWrite)
end;

class function TFile.Open(const aPath: string; const aMode: TFileMode;
  const aAccess: TFileAccess): TFileStream;
begin
  Result:=Open(aPath, aMode, aAccess, TFileShare.fsNone);
end;

class function TFile.Open(const aPath: string; const aMode: TFileMode;
  const aAccess: TFileAccess; const aShare: TFileShare): TFileStream;

Const
 // faRead, faWrite, faReadWrite
   AccessModes : Array[TFileAccess] of Word = ({$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}SysUtils.fmOpenRead, {$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}SysUtils.fmOpenWrite,fmOpenReadWrite)  ;
   // fsNone, fsRead, fsWrite, fsReadWrite
   ShareModes : Array[TFileShare] of word = (fmShareExclusive, fmShareDenyRead, fmShareDenyWrite,fmShareDenyNone);

Var
  acMode,sMode,fMode : Word;

begin
  acMode:=AccessModes[aAccess];
  sMode:=ShareModes[aShare];
  fMode:=acMode or sMode;
  case aMode of
  TFileMode.fmCreateNew :
    begin
    if Exists(aPath) then
      Raise EInOutError.CreateFmt(SErrFileExists,[aPath]);
    Result:=TFileStream.Create(aPath,fMode);
    end;
  TFileMode.fmCreate:
    Result:=TFileStream.Create(aPath, {$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}Classes.fmCreate or sMode);
  TFileMode.fmOpen:
    begin
    if not Exists(aPath) then
      Raise EInOutError.CreateFmt(SErrFileNotFound,[aPath]);
    Result:=TFileStream.Create(aPath,fMode);
    end;
  TFileMode.fmOpenOrCreate:
    begin
    if Exists(aPath) then
      Result:=TFileStream.Create(aPath,fMode)
    else
      Result:=TFileStream.Create(aPath,{$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}Classes.fmCreate or sMode);
    end;
  TFileMode.fmTruncate:
    begin
    if not Exists(aPath) then
      raise EInoutError.CreateFmt(SErrFileNotFound, [aPath]);
    Result:=TFileStream.Create(aPath,fMode);
    Result.Size:=0;
    end;
  TFileMode.fmAppend:
    begin
    if Exists(aPath) then
    begin
      Result:=TFileStream.Create(aPath, fMode);
      Result.Seek(0,soEnd);
    end
    else
      Result:=TFileStream.Create(aPath, {$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}Classes.fmCreate or sMode);
    end;
  end;
end;

class function TFile.OpenRead(const aPath: string): TFileStream;
begin
  Result:=TFileStream.Create(aPath, fmOpenRead or fmShareDenyWrite);
end;

class function TFile.OpenText(const aPath: string): TStreamReader;

var
  F : TFileStream;

begin
  Result:=Nil;
  F:=TFilestream.Create(aPath,fmOpenRead or fmShareDenyWrite);
  try
    Result := TStreamReader.Create(F,BUFFER_SIZE,True);
  except
    F.Free;
    Raise;
  end
end;

class function TFile.OpenWrite(const aPath: string): TFileStream;
begin
  try
    Result:=TFileStream.Create(aPath,fmOpenWrite);
  except
    on E: EFOpenError do
      begin
      if not FileExists(aPath) then
        raise EFileNotFoundException.CreateFmt('File not found: %s',[aPath]);
      raise;
      end;
  end;
end;

class function TFile.ReadAllBytes(const aPath: string): TBytes;
const
  InitialCapacity = 16384;
var
  Stream: TFileStream;
  SizeHint: Int64;
  Used, Capacity, NewCapacity: SizeInt;
  Count: LongInt;
  NextByte: Byte;
begin
  Result:=[];
  Stream:=OpenRead(aPath);
  try
    { Size is only a capacity hint: procfs/FIFOs may reject seeking, and a
      readable pseudo-file can report zero despite containing data. }
    SizeHint:=Stream.Size;
    If SizeHint>0 then
      Capacity:=SizeHint
    else
      Capacity:=InitialCapacity;
    SetLength(Result,Capacity);
    Used:=0;
    repeat
      If Used=Capacity then
        begin
        { Do not reallocate an ordinary file just to discover EOF. }
        Count:=FileRead(Stream.Handle,NextByte,1);
        If Count<=0 then
          Break;
        If Capacity>High(SizeInt) div 2 then
          raise EReadError.CreateFmt('File is too large: %s',[aPath]);
        NewCapacity:=Capacity*2;
        If NewCapacity<InitialCapacity then
          NewCapacity:=InitialCapacity;
        SetLength(Result,NewCapacity);
        Capacity:=NewCapacity;
        Result[Used]:=NextByte;
        Inc(Used);
        end;
      If Capacity-Used>High(LongInt) then
        Count:=High(LongInt)
      else
        Count:=Capacity-Used;
      { THandleStream.Read maps an OS read error to zero. Use FileRead here
        so ReadAllBytes can distinguish a failed read from a real EOF. }
      Count:=FileRead(Stream.Handle,Result[Used],Count);
      If Count<=0 then
        Break;
      Inc(Used,Count);
    until False;
    If Count<0 then
      raise EReadError.CreateFmt('Could not read file: %s',[aPath]);
    SetLength(Result,Used);
  finally
    Stream.Free;
  end;
end;

class function TFile.ReadAllLines(const aPath: string): TStringDynArray;
begin
  With TStringList.Create do
    try
      Text:=ReadAllText(aPath);
      Result:=ToStringArray;
    finally
      Free;
    end;
end;

class function TFile.ReadAllLines(const aPath: string; const aEncoding: TEncoding
  ): TStringDynArray;
begin
  With TStringList.Create do
    try
      Text:=ReadAllText(aPath,aEncoding);
      Result:=ToStringArray;
    finally
      Free;
    end;
end;

function ReadFileText(const aPath: string; const aEncoding: TEncoding): string;

  function IsValidUTF8(const Bytes: TBytes; StartIndex: Integer): Boolean;
  var
    B0, B1: Byte;
    I, L: Integer;
  begin
    I:=StartIndex;
    L:=Length(Bytes);
    While I<L do
      begin
      B0:=Bytes[I];
      If B0<$80 then
        Inc(I)
      else If (B0>=$c2) and (B0<=$df) then
        begin
        If (I+1>=L) or ((Bytes[I+1] and $c0)<>$80) then
          Exit(False);
        Inc(I,2);
        end
      else If (B0>=$e0) and (B0<=$ef) then
        begin
        If I+2>=L then
          Exit(False);
        B1:=Bytes[I+1];
        If ((B1 and $c0)<>$80) or ((Bytes[I+2] and $c0)<>$80) or
           ((B0=$e0) and (B1<$a0)) or ((B0=$ed) and (B1>$9f)) then
          Exit(False);
        Inc(I,3);
        end
      else If (B0>=$f0) and (B0<=$f4) then
        begin
        If I+3>=L then
          Exit(False);
        B1:=Bytes[I+1];
        If ((B1 and $c0)<>$80) or ((Bytes[I+2] and $c0)<>$80) or
           ((Bytes[I+3] and $c0)<>$80) or
           ((B0=$f0) and (B1<$90)) or ((B0=$f4) and (B1>$8f)) then
          Exit(False);
        Inc(I,4);
        end
      else
        Exit(False);
      end;
    Result:=True;
  end;

Var
  B : TBytes;
  BOMLength: Integer;
  Encoding, FoundEncoding: TEncoding;

begin
  B:=TFile.ReadAllBytes(aPath);
  FoundEncoding:=aEncoding;
  BOMLength:=TEncoding.GetBufferEncoding(B,FoundEncoding,TEncoding.UTF8);
  Encoding:=FoundEncoding;
  If not Assigned(aEncoding) and (BOMLength=0) and
     (Encoding=TEncoding.UTF8) and not IsValidUTF8(B,0) then
    begin
    Encoding:=TEncoding.ANSI;
    end;
{$if sizeof(char)=1}
  Result:=Encoding.GetAnsiString(B,BOMLength,Length(B)-BOMLength);
{$else}
  Result:=Encoding.GetString(B,BOMLength,Length(B)-BOMLength);
{$endif}
end;

class function TFile.ReadAllText(const aPath: string): string;
begin
  Result:=ReadFileText(aPath,nil);
end;

class function TFile.ReadAllText(const aPath: string; const aEncoding: TEncoding): string;
begin
  If aEncoding=nil then
    raise EInOutArgumentException.Create('Encoding must not be nil',aPath);
  Result:=ReadFileText(aPath,aEncoding);
end;

procedure RaiseReplaceError;
var
  Code: Integer;
  Error: EInOutError;
begin
  Code:=GetLastOSError;
  Error:=EInOutError.Create(SysErrorMessage(Code));
  Error.ErrorCode:=Code;
  raise Error;
end;

procedure CheckReplacePaths(const Source, Destination, Backup: string);
begin
  If (Source='') or (Destination='') or (Backup='') then
    raise EInOutArgumentException.Create('Replacement paths must not be empty',Backup);
  If not FileExists(Source) then
    raise EFileNotFoundException.CreateFmt('File not found: %s',[Source]);
  If not FileExists(Destination) then
    raise EFileNotFoundException.CreateFmt('File not found: %s',[Destination]);
  If not DirectoryExists(ExtractFilePath(ExpandFileName(Backup))) then
    raise EDirectoryNotFoundException.CreateFmt('Directory not found: %s',[Backup]);
end;

{$IFDEF MSWINDOWS}
function ReplaceFileW(lpReplacedFileName, lpReplacementFileName, lpBackupFileName: LPCWSTR; dwReplaceFlags: DWORD; lpExclude: LPVOID; lpReserved: LPVOID): BOOL; stdcall; external 'kernel32' name 'ReplaceFileW';

class procedure TFile.Replace(const aSource, aDestination, aBackup: string; const aIgnoreMetadataErrors: Boolean);
var
  Source, Destination, Backup: UnicodeString;
  Flags: DWORD;
begin
  CheckReplacePaths(aSource,aDestination,aBackup);
  Source:=MakeWinApiPath(aSource);
  Destination:=MakeWinApiPath(aDestination);
  Backup:=MakeWinApiPath(aBackup);
  Flags:=0;
  If aIgnoreMetadataErrors then
    Flags:=REPLACEFILE_IGNORE_MERGE_ERRORS;
  If not ReplaceFileW(PWideChar(Destination),PWideChar(Source),PWideChar(Backup),Flags,nil,nil) then
    RaiseReplaceError;
end;
{$ENDIF MSWINDOWS}

class procedure TFile.Replace(const aSource, aDestination, aBackup: string);
{$IFDEF UNIX}
var
  SourceInfo, DestinationInfo, BackupInfo: TStat;
  SourceBytes, DestinationBytes, BackupBytes: RawByteString;

  function SameFile(const First, Second: TStat): Boolean;
  begin
    Result:=(First.st_dev=Second.st_dev) and (First.st_ino=Second.st_ino);
  end;
{$ENDIF}
begin
{$IFDEF MSWINDOWS}
  Replace(aSource,aDestination,aBackup,False);
{$ELSE}
  CheckReplacePaths(aSource,aDestination,aBackup);
{$IFDEF UNIX}
  SourceBytes:=UTF8Encode(aSource);
  DestinationBytes:=UTF8Encode(aDestination);
  BackupBytes:=UTF8Encode(aBackup);
  If (fpStat(PAnsiChar(SourceBytes),SourceInfo)<>0) or
     (fpStat(PAnsiChar(DestinationBytes),DestinationInfo)<>0) then
    RaiseReplaceError;
  If SameFile(SourceInfo,DestinationInfo) then
    raise EInOutError.Create('Replacement source and destination must be distinct');
  If (fpStat(PAnsiChar(BackupBytes),BackupInfo)=0) and
     (SameFile(BackupInfo,SourceInfo) or SameFile(BackupInfo,DestinationInfo)) then
    raise EInOutError.Create('Replacement backup must be distinct');
{$ENDIF}
  CopyFile(aDestination,aBackup,[TCopyFileFlag.cffOverwriteFile],True);
  { Rename replaces the destination without truncating a live reader's file.
    A failed rename leaves the source and destination intact, with a backup. }
  If not RenameFile(aSource,aDestination) then
    RaiseReplaceError;
{$ENDIF}
end;

class procedure TFile.SetAttributes(const aPath: string; const aAttributes: TFileAttributes);
var
  Code: Integer;
begin
{$ifdef unix}
  if fpChmod(aPath,FileAttributesToInteger(aAttributes))=0 then
    Exit;
  Code:=GetLastOSError;
{$else}
  Code:={$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}SysUtils.FileSetAttr(aPath,FileAttributesToInteger(aAttributes));
  if Code=0 then
    Exit;
{$endif}
  if MissingPathError(Code) then
    raise EFileNotFoundException.CreateFmt('File not found: %s',[aPath]);
  RaisePathError(aPath,Code);
end;

class procedure TFile.SetCreationTime(const aPath: string;
  const CreationTime: TDateTime);
begin
  SetFileTimestamps(aPath,@CreationTime,Nil,Nil,False);
end;

class procedure TFile.SetCreationTimeUtc(const aPath: string;
  const CreationTime: TDateTime);
begin
  SetFileTimestamps(aPath,@CreationTime,Nil,Nil,True);
end;

class procedure TFile.SetLastAccessTime(const aPath: string;
  const LastAccessTime: TDateTime);
begin
  SetFileTimestamps(aPath,Nil,Nil,@LastAccessTime,False);
end;

class procedure TFile.SetLastAccessTimeUtc(const aPath: string;
  const LastAccessTime: TDateTime);
begin
  SetFileTimestamps(aPath,Nil,Nil,@LastAccessTime,True);
end;

class procedure TFile.SetLastWriteTime(const aPath: string;
  const LastWriteTime: TDateTime);
begin
  SetFileTimestamps(aPath,Nil,@LastWriteTime,Nil,False);
end;

class procedure TFile.SetLastWriteTimeUtc(const aPath: string;
  const LastWriteTime: TDateTime);
begin
  SetFileTimestamps(aPath,Nil,@LastWriteTime,Nil,True);
end;

class procedure TFile.WriteAllBytes(const aPath: string; const aBytes: TBytes);
begin
  With Create(aPath) do
    try
      If Length(aBytes)>0 then
        WriteBuffer(aBytes,Length(aBytes));
    finally
      Free
    end;
end;

class procedure TFile.WriteAllLines(const aPath: string;
  const aContents: TStringDynArray);
var
  Lines: TStringList;
begin
  Lines:=TStringList.Create;
  try
    Lines.SetStrings(aContents);
    Lines.WriteBOM:=False;
    Lines.SaveToFile(aPath,TEncoding.UTF8);
  finally
    Lines.Free;
  end;
end;

class procedure TFile.WriteAllLines(const aPath: string;
  const aContents: TStringDynArray; const aEncoding: TEncoding);
var
  L : TStringList;
begin
  If aEncoding=nil then
    raise EInOutArgumentException.Create('Encoding must not be nil',aPath);
  L:=TStringList.Create;
  try
    L.SetStrings(aContents);
    L.SaveToFile(aPath,aEncoding);
  finally
    L.Free;
  end;

end;

class procedure TFile.WriteAllText(const aPath, aContents: string);
begin
{$IF SIZEOF(CHAR)=1}
  WriteAllBytes(aPath,TEncoding.UTF8.GetAnsiBytes(aContents));
{$ELSE}
  WriteAllBytes(aPath,TEncoding.UTF8.GetBytes(aContents));
{$ENDIF}
end;

class procedure TFile.WriteAllText(const aPath, aContents: string;
  const aEncoding: TEncoding);
var
  Bytes, Preamble: TBytes;
  Stream: TFileStream;
begin
  If aEncoding=nil then
    raise EInOutArgumentException.Create('Encoding must not be nil',aPath);
{$IF SIZEOF(CHAR)=1}
  Bytes:=aEncoding.GetAnsiBytes(aContents);
{$ELSE}
  Bytes:=aEncoding.GetBytes(aContents);
{$ENDIF}
  Preamble:=aEncoding.GetPreamble;
  Stream:=Create(aPath);
  try
    If Length(Preamble)>0 then
      Stream.WriteBuffer(Preamble[0],Length(Preamble));
    If Length(Bytes)>0 then
      Stream.WriteBuffer(Bytes[0],Length(Bytes));
  finally
    Stream.Free;
  end;
end;

{ TDirectory }

class function TDirectory.GetFilesAndDirectories(const aPath,
  aSearchPattern: string; const aSearchOption: TSearchOption;
  const SearchAttributes: TFileAttributes;
  const aPredicate: TFilterPredicateLocal): TStringDynArray;
const
   lfaDirectory = {$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}SysUtils.faDirectory;

  function FilterPredicate(const aPath: string; const SearchRec: TSearchRec): Boolean;
  begin
    Result:=(SearchRec.Name <> '.') and (SearchRec.Name <> '..');
    if Result and Assigned(aPredicate) then
      Result:=aPredicate(aPath, SearchRec);
  end;
var
  SearchRec: TSearchRec;
  IntPath:   TFileName;
begin
  RequireDirectory(aPath);
  IntPath     :=IncludeTrailingPathDelimiter(aPath);
  Result      :=[];
  if (CheckedFindFirst(IntPath + aSearchPattern, TFile.FileAttributesToInteger(SearchAttributes), SearchRec) = 0) then
    try
      repeat
        if FilterPredicate(aPath, SearchRec) then
          Result:=Result + [IntPath + SearchRec.Name];
      until CheckedFindNext(SearchRec,aPath) <> 0;
    finally
      {$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}SysUtils.FindClose(SearchRec);
    end;
  if (aSearchOption=TSearchOption.soAllDirectories) and (CheckedFindFirst(IntPath + AllFilesMask,
    lfaDirectory or {$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}SysUtils.faSymLink, SearchRec) = 0) then
    try
      repeat
        if SearchRec.IsDirectory and not SearchRec.IsCurrentOrParentDir and
           ((SearchRec.Attr and {$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}SysUtils.faSymLink)=0) then
           Result:=Result + GetFilesAndDirectories(IntPath + SearchRec.Name, aSearchPattern, aSearchOption, SearchAttributes, aPredicate)
      until CheckedFindNext(SearchRec,aPath) <> 0;
   Finally
     {$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}SysUtils.FindClose(SearchRec);
   end;
end;

class procedure TDirectory.Copy(const SourceDirName, DestDirName: string);
begin
  Copy(SourceDirName,DestDirName,False);
end;

class procedure TDirectory.Copy(const SourceDirName, DestDirName: string; const IgnoreErrors: Boolean);
var
  Parent,NextParent: string;
  Attr,Code: Integer;

  procedure CopyTree(const Source,Destination: string);
  var
    Rec: TSearchRec;
    FromPath,ToPath: string;
{$ifdef unix}
    LinkTarget: RawByteString;
{$else}
    WideSource,WideDestination: UnicodeString;
    CopyFlags: DWORD;
{$endif}
  begin
    CreateDirectory(Destination);
    if CheckedFindFirst(IncludeTrailingPathDelimiter(Source)+AllFilesMask,
      {$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}SysUtils.faAnyFile or
      {$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}SysUtils.faSymLink,Rec)<>0 then
      Exit;
    try
      repeat
        if Rec.IsCurrentOrParentDir then
          Continue;
        FromPath:=TPath.Combine(Source,Rec.Name);
        ToPath:=TPath.Combine(Destination,Rec.Name);
        try
          if (Rec.Attr and {$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}SysUtils.faSymLink)<>0 then
            begin
{$ifdef unix}
            LinkTarget:=fpReadLink(ToSingleByteFileSystemEncodedFileName(FromPath));
            if LinkTarget='' then
              RaisePathError(FromPath,GetLastOSError);
            if fpSymlink(PAnsiChar(LinkTarget),PAnsiChar(ToSingleByteFileSystemEncodedFileName(ToPath)))<>0 then
              RaisePathError(ToPath,GetLastOSError);
{$else}
            WideSource:=MakeWinApiPath(FromPath);
            WideDestination:=MakeWinApiPath(ToPath);
            CopyFlags:=COPY_FILE_COPY_SYMLINK;
            if Rec.IsDirectory then
              CopyFlags:=CopyFlags or $80; { COPY_FILE_DIRECTORY, Windows 10 build 19041+ }
            if CopyFileExW(PWideChar(WideSource),PWideChar(WideDestination),nil,nil,nil,
                CopyFlags)=0 then
              RaisePathError(ToPath,GetLastOSError);
{$endif}
            end
          else if Rec.IsDirectory then
            CopyTree(FromPath,ToPath)
          else
            TFile.Copy(FromPath,ToPath,True);
        except
          on E: EInOutError do if not IgnoreErrors then raise;
          on E: EStreamError do if not IgnoreErrors then raise;
          on E: EDirectoryNotFoundException do if not IgnoreErrors then raise;
        end;
      until CheckedFindNext(Rec,Source)<>0;
    finally
      {$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}SysUtils.FindClose(Rec);
    end;
  end;

begin
  RequireDirectory(SourceDirName);
  if DestDirName='' then
    raise EArgumentException.Create('Destination directory must not be empty');
{$ifdef unix}
  { Preserve native symlink/.. traversal; lexical ExpandFileName would erase it. }
  if TPath.IsPathRooted(DestDirName) then
    Parent:=DestDirName
  else
    Parent:=IncludeTrailingPathDelimiter(GetCurrentDir)+DestDirName;
{$else}
  Parent:=ExpandFileName(DestDirName);
{$endif}
  Parent:=ExcludeTrailingPathDelimiter(Parent);
  { Find the existing prefix without creating any destination directory. }
  repeat
    Attr:=FileGetAttr(Parent);
    if Attr>=0 then
      Break;
    Code:=GetLastOSError;
    if not MissingPathError(Code) then
      RaisePathError(Parent,Code);
    NextParent:=ExtractFileDir(Parent);
    if (NextParent=Parent) or (NextParent='') then
      RaisePathError(Parent,Code);
    Parent:=NextParent;
  until False;
  RequireDirectory(Parent);
{$ifdef windows}
  Parent:=ResolvedDirectory(Parent);
{$endif}
  repeat
    if SameFileIdentity(SourceDirName,Parent) then
      raise EArgumentException.Create('Cannot copy a directory into itself');
{$ifdef unix}
    NextParent:=IncludeTrailingPathDelimiter(Parent)+'..';
    RequireDirectory(NextParent);
    if SameFileIdentity(Parent,NextParent) then
      Break;
{$else}
    NextParent:=ExtractFileDir(Parent);
    if (NextParent=Parent) or (NextParent='') then
      Break;
{$endif}
    Parent:=NextParent;
  until False;
  CopyTree(SourceDirName,DestDirName);
end;

class procedure TDirectory.CreateDirectory(const aPath: string);
begin
  if not ForceDirectories(aPath) then
    RaisePathError(aPath,GetLastOSError);
end;

function DeleteDirectory(const DirectoryName: string; OnlyChildren: boolean): boolean;
const
  //Don't follow symlinks on *nix, just delete them
  DeleteMask = faAnyFile {$ifdef unix} or {$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}sysutils.faSymLink{%H-} {$endif unix};
var
  FileInfo: TSearchRec;
  CurSrcDir: String;
  CurFilename: String;
begin
  Result:=false;
{$ifdef unix}
  if fpS_ISLNK(FileGetMode(DirectoryName,False)) then
{$else}
  if (FileGetAttr(DirectoryName) and {$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}SysUtils.faSymLink)<>0 then
{$endif}
    begin
    if OnlyChildren then
      Exit;
{$ifdef windows}
    Result:=RemoveDir(DirectoryName);
{$else}
    Result:={$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}SysUtils.DeleteFile(DirectoryName);
{$endif}
    Exit;
    end;
  CurSrcDir:=ExpandFileName(DirectoryName);
  CurSrcDir:=IncludeTrailingPathDelimiter(CurSrcDir);
  if CheckedFindFirst(CurSrcDir+AllFilesMask,DeleteMask,FileInfo)=0 then
    Try
      repeat
        // check if special file
        if (FileInfo.Name='.') or (FileInfo.Name='..') or (FileInfo.Name='') then
          continue;
        CurFilename:=CurSrcDir+FileInfo.Name;
        if ((FileInfo.Attr and {$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}sysutils.faDirectory)>0)
           and ((FileInfo.Attr and {$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}sysutils.faSymLink)=0) then begin
          if not DeleteDirectory(CurFilename,false) then exit;
        end else begin
{$ifdef windows}
          if (FileInfo.Attr and {$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}SysUtils.faDirectory)<>0 then
            begin
            if not RemoveDir(CurFilename) then Exit;
            end
          else
{$endif}
          if not {$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}SysUtils.DeleteFile(CurFilename) then exit;
        end;
      until CheckedFindNext(FileInfo,DirectoryName)<>0;
    finally
      {$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}SysUtils.FindClose(FileInfo);
    end;
  if (not OnlyChildren) and (not RemoveDir(CurSrcDir)) then exit;
  Result:=true;
end;


class procedure TDirectory.Delete(const aPath: string);
begin
  RequireDirectory(aPath);
  if not RemoveDir(aPath) then
    RaisePathError(aPath,GetLastOSError);
end;



class procedure TDirectory.Delete(const aPath: string; const Recursive: Boolean);
begin
  RequireDirectory(aPath);
  if Recursive then
    begin
    if not DeleteDirectory(aPath,False) then
      RaisePathError(aPath,GetLastOSError);
    end
  else
    TDirectory.Delete(aPath);
end;

class function TDirectory.Exists(const aPath: string; FollowLink: Boolean
  ): Boolean;
begin
  Result:=DirectoryExists(aPath, FollowLink);
end;

class function TDirectory.GetAttributes(const aPath: string; FollowLink: Boolean
  ): TFileAttributes;
begin
  Result:=TFile.GetAttributes(aPath, FollowLink);
end;

class function TDirectory.GetCurrentDirectory: string;
begin
  Result:=GetCurrentDir;
end;

class procedure TDirectory.SetCurrentDirectory(const aPath: string);
begin
  ChDir(aPath);
end;

class function TDirectory.GetLogicalDrives: TStringDynArray;
{$IfDef WINDOWS}
var
  i: Char;
{$EndIf}
begin
  Result:=[];
  {$IfDef WINDOWS}
    for i:='A' to 'Z' do
      if DirectoryExists(i + ':\') then
        Result:=Result + [i + ':\'];
  {$EndIf}
end;

class function TDirectory.GetCreationTime(const aPath: string): TDateTime;
begin
  Result:=TFile.GetCreationTime(aPath);
end;

class function TDirectory.GetCreationTimeUtc(const aPath: string): TDateTime;
begin
  Result:=TFile.GetCreationTimeUtc(aPath);
end;

class function TDirectory.GetLastAccessTime(const aPath: string): TDateTime;
begin
  Result:=TFile.GetLastAccessTime(aPath);
end;

class function TDirectory.GetLastAccessTimeUtc(const aPath: string): TDateTime;
begin
  Result:=TFile.GetLastAccessTimeUtc(aPath);
end;

class function TDirectory.GetLastWriteTime(const aPath: string): TDateTime;
begin
  Result:=TFile.GetLastWriteTime(aPath);
end;

class function TDirectory.GetLastWriteTimeUtc(const aPath: string): TDateTime;
begin
  Result:=TFile.GetLastWriteTimeUtc(aPath);
end;

class procedure TDirectory.SetAttributes(const aPath: string;
  const Attributes: TFileAttributes);
begin
  TFile.SetAttributes(aPath, Attributes);
end;

class procedure TDirectory.SetCreationTime(const aPath: string;
  const CreationTime: TDateTime);
begin
  TFile.SetCreationTime(aPath,CreationTime);
end;

class procedure TDirectory.SetCreationTimeUtc(const aPath: string;
  const CreationTime: TDateTime);
begin
  TFile.SetCreationTimeUtc(aPath,CreationTime);
end;

class procedure TDirectory.SetLastAccessTime(const aPath: string;
  const LastAccessTime: TDateTime);
begin
  TFile.SetLastAccessTime(aPath,LastAccessTime);
end;

class procedure TDirectory.SetLastAccessTimeUtc(const aPath: string;
  const LastAccessTime: TDateTime);
begin
  TFile.SetLastAccessTimeUtc(aPath,LastAccessTime);
end;

class procedure TDirectory.SetLastWriteTime(const aPath: string;
  const LastWriteTime: TDateTime);
begin
  TFile.SetLastWriteTime(aPath,LastWriteTime);
end;

class procedure TDirectory.SetLastWriteTimeUtc(const aPath: string;
  const LastWriteTime: TDateTime);
begin
  TFile.SetLastWriteTimeUtc(aPath,LastWriteTime);
end;

class function TDirectory.GetParent(const aPath: string): string;
begin
  Result:=ExpandFileName(IncludeTrailingPathDelimiter(aPath) + '..');
end;

class function TDirectory.GetDirectoryRoot(const aPath: string): string;
begin
  if Trim(aPath)='' then
    raise EInOutError.Create(SErrEmptyPath);
  Result:=TPath.GetPathRoot(TPath.GetFullPath(aPath));
end;

class function TDirectory.GetDirectoriesEnumerator(const aPath: string
  ): specialize IEnumerable<string>;
begin
  Result:=GetDirectoriesEnumerator(aPath,'*',TSearchOption.soTopDirectoryOnly);
end;

class function TDirectory.GetDirectoriesEnumerator(const aPath: string;
  const aPredicate: TFilterPredicate): specialize IEnumerable<string>;
begin
  Result:=GetDirectoriesEnumerator(aPath,'*',TSearchOption.soTopDirectoryOnly,
    aPredicate);
end;

class function TDirectory.GetDirectoriesEnumerator(const aPath,
  aSearchPattern: string): specialize IEnumerable<string>;
begin
  Result:=GetDirectoriesEnumerator(aPath,aSearchPattern,
    TSearchOption.soTopDirectoryOnly);
end;

class function TDirectory.GetDirectoriesEnumerator(const aPath,
  aSearchPattern: string; const aPredicate: TFilterPredicate
  ): specialize IEnumerable<string>;
begin
  Result:=GetDirectoriesEnumerator(aPath,aSearchPattern,
    TSearchOption.soTopDirectoryOnly,aPredicate);
end;

class function TDirectory.GetDirectoriesEnumerator(const aPath,
  aSearchPattern: string; const aSearchOption: TSearchOption
  ): specialize IEnumerable<string>;
begin
  Result:=TStringArrayEnumerable.Create(
    GetDirectories(aPath,aSearchPattern,aSearchOption));
end;

class function TDirectory.GetDirectoriesEnumerator(const aPath,
  aSearchPattern: string; const aSearchOption: TSearchOption;
  const aPredicate: TFilterPredicate): specialize IEnumerable<string>;
begin
  Result:=TStringArrayEnumerable.Create(
    GetDirectories(aPath,aSearchPattern,aSearchOption,aPredicate));
end;

class function TDirectory.GetDirectoriesEnumerator(const aPath: string;
  const aSearchOption: TSearchOption; const aPredicate: TFilterPredicate
  ): specialize IEnumerable<string>;
begin
  Result:=GetDirectoriesEnumerator(aPath,'*',aSearchOption,aPredicate);
end;

class function TDirectory.GetDirectories(const aPath: string): TStringDynArray;
begin
  Result:=GetDirectories(aPath, '*');
end;

class function TDirectory.GetDirectories(const aPath: string;
  const aPredicate: TFilterPredicateLocal): TStringDynArray;
begin
  Result:=GetDirectories(aPath, '*', aPredicate);
end;

class function TDirectory.GetDirectories(const aPath: string;
  const aPredicate: TFilterPredicateObject): TStringDynArray;
begin
  Result:=GetDirectories(aPath, '*', aPredicate);
end;

class function TDirectory.GetDirectories(const aPath: string;
  const aPredicate: TFilterPredicate): TStringDynArray;
begin
  Result:=GetDirectories(aPath, '*', aPredicate);
end;

class function TDirectory.GetDirectories(const aPath, aSearchPattern: string
  ): TStringDynArray;
begin
  Result:=GetDirectories(aPath, aSearchPattern, TFilterPredicateLocal(nil));
end;

class function TDirectory.GetDirectories(const aPath, aSearchPattern: string;
  const aPredicate: TFilterPredicateLocal): TStringDynArray;
begin
  Result:=GetDirectories(aPath, aSearchPattern, TSearchOption.soTopDirectoryOnly, aPredicate);
end;

class function TDirectory.GetDirectories(const aPath, aSearchPattern: string;
  const aPredicate: TFilterPredicateObject): TStringDynArray;
begin
  Result:=GetDirectories(aPath, aSearchPattern, TSearchOption.soTopDirectoryOnly, aPredicate);
end;

class function TDirectory.GetDirectories(const aPath, aSearchPattern: string;
  const aPredicate: TFilterPredicate): TStringDynArray;
begin
  Result:=GetDirectories(aPath, aSearchPattern, TSearchOption.soTopDirectoryOnly, aPredicate);
end;

class function TDirectory.GetDirectories(const aPath, aSearchPattern: string;
  const aSearchOption: TSearchOption): TStringDynArray;
begin
  Result:=GetDirectories(aPath, aSearchPattern, aSearchOption, TFilterPredicateLocal(nil));
end;

class function TDirectory.GetDirectories(const aPath, aSearchPattern: string;
  const aSearchOption: TSearchOption; const aPredicate: TFilterPredicateLocal
  ): TStringDynArray;
begin
  Result:=GetFilesAndDirectories(aPath, aSearchPattern,
    aSearchOption, TFile.IntegerToFileAttributes(faAnyFile),
    function(const aPath: string; const SearchRec: TSearchRec): Boolean
    begin
      Result :=
        (SearchRec.Attr and {$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}SysUtils.faDirectory <> 0) and
        (SearchRec.Name <> '.') and (SearchRec.Name <> '..');
      if Result and Assigned(aPredicate) then
        Result := aPredicate(aPath, SearchRec);
    end);
end;

class function TDirectory.GetDirectories(const aPath, aSearchPattern: string;
  const aSearchOption: TSearchOption; const aPredicate: TFilterPredicateObject
  ): TStringDynArray;
begin
  Result:=GetDirectories(aPath, aSearchPattern, aSearchOption,
    function(const aPath: string; const SearchRec: TSearchRec): Boolean
    begin
      Result := aPredicate(aPath, SearchRec);
    end);
end;

class function TDirectory.GetDirectories(const aPath, aSearchPattern: string;
  const aSearchOption: TSearchOption; const aPredicate: TFilterPredicate
  ): TStringDynArray;
begin
  Result:=GetDirectories(aPath, aSearchPattern, aSearchOption,
    function(const aPath: string; const SearchRec: TSearchRec): Boolean
    begin
      Result := aPredicate(aPath, SearchRec);
    end);
end;

class function TDirectory.GetDirectories(const aPath: string;
  const aSearchOption: TSearchOption; const aPredicate: TFilterPredicateLocal
  ): TStringDynArray;
begin
  Result:=GetDirectories(aPath, '*', aSearchOption, aPredicate);
end;

class function TDirectory.GetDirectories(const aPath: string;
  const aSearchOption: TSearchOption; const aPredicate: TFilterPredicateObject
  ): TStringDynArray;
begin
  Result:=GetDirectories(aPath, '*', aSearchOption, aPredicate);
end;

class function TDirectory.GetDirectories(const aPath: string;
  const aSearchOption: TSearchOption; const aPredicate: TFilterPredicate
  ): TStringDynArray;
begin
  Result:=GetDirectories(aPath, '*', aSearchOption, aPredicate);
end;

class function TDirectory.GetFiles(const aPath: string): TStringDynArray;
begin
  Result:=GetFiles(aPath, '*');
end;

class function TDirectory.GetFilesEnumerator(const aPath: string
  ): specialize IEnumerable<string>;
begin
  Result:=GetFilesEnumerator(aPath,'*',TSearchOption.soTopDirectoryOnly);
end;

class function TDirectory.GetFilesEnumerator(const aPath: string;
  const aPredicate: TFilterPredicate): specialize IEnumerable<string>;
begin
  Result:=GetFilesEnumerator(aPath,'*',TSearchOption.soTopDirectoryOnly,
    aPredicate);
end;

class function TDirectory.GetFilesEnumerator(const aPath,
  aSearchPattern: string): specialize IEnumerable<string>;
begin
  Result:=GetFilesEnumerator(aPath,aSearchPattern,
    TSearchOption.soTopDirectoryOnly);
end;

class function TDirectory.GetFilesEnumerator(const aPath,
  aSearchPattern: string; const aPredicate: TFilterPredicate
  ): specialize IEnumerable<string>;
begin
  Result:=GetFilesEnumerator(aPath,aSearchPattern,
    TSearchOption.soTopDirectoryOnly,aPredicate);
end;

class function TDirectory.GetFilesEnumerator(const aPath,
  aSearchPattern: string; const aSearchOption: TSearchOption
  ): specialize IEnumerable<string>;
begin
  Result:=TStringArrayEnumerable.Create(
    GetFiles(aPath,aSearchPattern,aSearchOption));
end;

class function TDirectory.GetFilesEnumerator(const aPath,
  aSearchPattern: string; const aSearchOption: TSearchOption;
  const aPredicate: TFilterPredicate): specialize IEnumerable<string>;
begin
  Result:=TStringArrayEnumerable.Create(
    GetFiles(aPath,aSearchPattern,aSearchOption,aPredicate));
end;

class function TDirectory.GetFilesEnumerator(const aPath: string;
  const aSearchOption: TSearchOption; const aPredicate: TFilterPredicate
  ): specialize IEnumerable<string>;
begin
  Result:=GetFilesEnumerator(aPath,'*',aSearchOption,aPredicate);
end;

class function TDirectory.GetFiles(const aPath: string;
  const aPredicate: TFilterPredicateLocal): TStringDynArray;
begin
  Result:=GetFiles(aPath, '*', TSearchOption.soTopDirectoryOnly, aPredicate);
end;

class function TDirectory.GetFiles(const aPath: string;
  const aPredicate: TFilterPredicateObject): TStringDynArray;
begin
  Result:=GetFiles(aPath, '*', TSearchOption.soTopDirectoryOnly, aPredicate);
end;

class function TDirectory.GetFiles(const aPath: string;
  const aPredicate: TFilterPredicate): TStringDynArray;
begin
  Result:=GetFiles(aPath, '*', TSearchOption.soTopDirectoryOnly, aPredicate);
end;

class function TDirectory.GetFiles(const aPath, aSearchPattern: string
  ): TStringDynArray;
begin
  Result:=GetFiles(aPath, aSearchPattern, TSearchOption.soTopDirectoryOnly, TFilterPredicateLocal(nil));
end;

class function TDirectory.GetFiles(const aPath, aSearchPattern: string;
  const aPredicate: TFilterPredicateLocal): TStringDynArray;
begin
  Result:=GetFiles(aPath, aSearchPattern, TSearchOption.soTopDirectoryOnly, aPredicate);
end;

class function TDirectory.GetFiles(const aPath, aSearchPattern: string;
  const aPredicate: TFilterPredicateObject): TStringDynArray;
begin
  Result:=GetFiles(aPath, aSearchPattern, TSearchOption.soTopDirectoryOnly, aPredicate);
end;

class function TDirectory.GetFiles(const aPath, aSearchPattern: string;
  const aPredicate: TFilterPredicate): TStringDynArray;
begin
  Result:=GetFiles(aPath, aSearchPattern, TSearchOption.soTopDirectoryOnly, aPredicate);
end;

class function TDirectory.GetFiles(const aPath, aSearchPattern: string;
  const aSearchOption: TSearchOption): TStringDynArray;
begin
  Result:=GetFiles(aPath, aSearchPattern, aSearchOption, TFilterPredicateLocal(nil));
end;

class function TDirectory.GetFiles(const aPath, aSearchPattern: string;
  const aSearchOption: TSearchOption; const aPredicate: TFilterPredicateLocal
  ): TStringDynArray;
begin
  Result:=GetFilesAndDirectories(aPath, aSearchPattern, aSearchOption,
    TFile.IntegerToFileAttributes(faAnyFile) - [TFileAttribute.faDirectory],
    function(const aPath: string; const SearchRec: TSearchRec): Boolean
    begin
      Result := SearchRec.Attr and {$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}SysUtils.faDirectory = 0;
      if Result and Assigned(aPredicate) then
        Result := aPredicate(aPath, SearchRec);
    end);
end;

class function TDirectory.GetFiles(const aPath, aSearchPattern: string;
  const aSearchOption: TSearchOption; const aPredicate: TFilterPredicateObject
  ): TStringDynArray;
begin
  Result:=GetFiles(aPath, aSearchPattern, aSearchOption,
    function(const aPath: string; const SearchRec: TSearchRec): Boolean
    begin
      Result := aPredicate(aPath, SearchRec);
    end);
end;

class function TDirectory.GetFiles(const aPath, aSearchPattern: string;
  const aSearchOption: TSearchOption; const aPredicate: TFilterPredicate
  ): TStringDynArray;
begin
  Result:=GetFiles(aPath, aSearchPattern, aSearchOption,
    function(const aPath: string; const SearchRec: TSearchRec): Boolean
    begin
      Result := aPredicate(aPath, SearchRec);
    end);
end;

class function TDirectory.GetFiles(const aPath: string;
  const aSearchOption: TSearchOption; const aPredicate: TFilterPredicateLocal
  ): TStringDynArray;
begin
  Result:=GetFiles(aPath, '*', aSearchOption, aPredicate);
end;

class function TDirectory.GetFiles(const aPath: string;
  const aSearchOption: TSearchOption; const aPredicate: TFilterPredicateObject
  ): TStringDynArray;
begin
  Result:=GetFiles(aPath, '*', aSearchOption, aPredicate);
end;

class function TDirectory.GetFiles(const aPath: string;
  const aSearchOption: TSearchOption; const aPredicate: TFilterPredicate
  ): TStringDynArray;
begin
  Result:=GetFiles(aPath, '*', aSearchOption, aPredicate);
end;

class function TDirectory.GetFileSystemEntries(const aPath: string
  ): TStringDynArray;
begin
  Result:=GetFileSystemEntries(aPath, '*');
end;

class function TDirectory.GetFileSystemEntriesEnumerator(const aPath: string
  ): specialize IEnumerable<string>;
begin
  Result:=GetFileSystemEntriesEnumerator(aPath,'*');
end;

class function TDirectory.GetFileSystemEntriesEnumerator(const aPath: string;
  const aPredicate: TFilterPredicate): specialize IEnumerable<string>;
begin
  Result:=TStringArrayEnumerable.Create(
    GetFileSystemEntries(aPath,aPredicate));
end;

class function TDirectory.GetFileSystemEntriesEnumerator(const aPath,
  aSearchPattern: string): specialize IEnumerable<string>;
begin
  Result:=TStringArrayEnumerable.Create(
    GetFileSystemEntries(aPath,aSearchPattern));
end;

class function TDirectory.GetFileSystemEntriesEnumerator(const aPath,
  aSearchPattern: string; const aPredicate: TFilterPredicate
  ): specialize IEnumerable<string>;
begin
  Result:=TStringArrayEnumerable.Create(
    GetFileSystemEntries(aPath,aSearchPattern,aPredicate));
end;

class function TDirectory.GetFileSystemEntriesEnumerator(const aPath: string;
  const aSearchOption: TSearchOption; const aPredicate: TFilterPredicate
  ): specialize IEnumerable<string>;
begin
  Result:=TStringArrayEnumerable.Create(
    GetFileSystemEntries(aPath,aSearchOption,aPredicate));
end;

class function TDirectory.GetFileSystemEntries(const aPath: string;
  const aPredicate: TFilterPredicateLocal): TStringDynArray;
begin
  Result:=GetFileSystemEntries(aPath, '*', aPredicate);
end;

class function TDirectory.GetFileSystemEntries(const aPath: string;
  const aPredicate: TFilterPredicateObject): TStringDynArray;
begin
  Result:=GetFileSystemEntries(aPath, '*', aPredicate);
end;

class function TDirectory.GetFileSystemEntries(const aPath: string;
  const aPredicate: TFilterPredicate): TStringDynArray;
begin
  Result:=GetFileSystemEntries(aPath, '*', aPredicate);
end;

class function TDirectory.GetFileSystemEntries(const aPath, aSearchPattern: string
  ): TStringDynArray;
begin
  Result:=GetFileSystemEntries(aPath, aSearchPattern, TFilterPredicateLocal(nil));
end;

class function TDirectory.GetFileSystemEntries(const aPath,
  aSearchPattern: string; const aPredicate: TFilterPredicateLocal
  ): TStringDynArray;
begin
  Result:=GetFilesAndDirectories(aPath, aSearchPattern, TSearchOption.soTopDirectoryOnly, TFile.IntegerToFileAttributes(faAnyFile), aPredicate);

end;

class function TDirectory.GetFileSystemEntries(const aPath,
  aSearchPattern: string; const aPredicate: TFilterPredicateObject
  ): TStringDynArray;
begin
  Result:=GetFilesAndDirectories(aPath, aSearchPattern,
    TSearchOption.soTopDirectoryOnly, TFile.IntegerToFileAttributes(faAnyFile),
    function(const aPath: string; const SearchRec: TSearchRec): Boolean
    begin
      Result := aPredicate(aPath, SearchRec);
    end);
end;

class function TDirectory.GetFileSystemEntries(const aPath,
  aSearchPattern: string; const aPredicate: TFilterPredicate): TStringDynArray;
begin
  Result:=GetFilesAndDirectories(aPath, aSearchPattern,
    TSearchOption.soTopDirectoryOnly, TFile.IntegerToFileAttributes(faAnyFile),
    function(const aPath: string; const SearchRec: TSearchRec): Boolean
    begin
      Result := aPredicate(aPath, SearchRec);
    end);
end;

class function TDirectory.GetFileSystemEntries(const aPath: string;
  const aSearchOption: TSearchOption; const aPredicate: TFilterPredicateLocal
  ): TStringDynArray;
begin
  Result:=GetFilesAndDirectories(aPath, '*', aSearchOption, TFile.IntegerToFileAttributes(faAnyFile),aPredicate);
end;

class function TDirectory.GetFileSystemEntries(const aPath: string;
  const aSearchOption: TSearchOption; const aPredicate: TFilterPredicateObject
  ): TStringDynArray;
begin
  Result:=GetFilesAndDirectories(aPath, '*', aSearchOption, TFile.IntegerToFileAttributes(faAnyFile),
    function(const aPath: string; const SearchRec: TSearchRec): Boolean
    begin
      Result := aPredicate(aPath, SearchRec);
    end);
end;

class function TDirectory.GetFileSystemEntries(const aPath: string;
  const aSearchOption: TSearchOption; const aPredicate: TFilterPredicate
  ): TStringDynArray;
begin
  Result:=GetFilesAndDirectories(aPath, '*', aSearchOption, TFile.IntegerToFileAttributes(faAnyFile),
    function(const aPath: string; const SearchRec: TSearchRec): Boolean
    begin
      Result := aPredicate(aPath, SearchRec);
    end);
end;

class procedure TDirectory.ForAllEntries(const aPath, aPattern: string; const aBefore, aAfter: TFilterPredicateLocal; aRecursive: Boolean);
var
  Handle: Boolean;
  Continue: Boolean;
  Info: TSearchRec;
  lPath : String;
begin
  Handle:=True;
  lPath:=IncludeTrailingPathDelimiter(aPath);
  if FindFirst(lPath+AllFilesMask,faAnyFile,Info)<>0 then
    exit;
  try
    repeat
      Handle:=TPath.MatchesPattern(Info.Name,aPattern,System.FileNameCaseSensitive);
      if Handle and Assigned(aBefore) then
        Continue:=aBefore(aPath,Info);
      if Continue then
        begin
        if aRecursive and Info.IsDirectory and not Info.IsCurrentOrParentDir then
           ForAllEntries(lPath+Info.Name,aPattern,aBefore,aAfter,aRecursive);
        if Handle and Assigned(aAfter) then
          Continue:=aAfter(lPath,Info);
        end;
    until ({$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}SysUtils.FindNext(Info)<>0) or not Continue;
  finally
    {$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}SysUtils.FindClose(Info);
  end;
end;

class function TDirectory.IsEmpty(const aPath: string): Boolean;
var
  sr: TSearchRec;
begin
  Result:=True;
  if (FindFirst(aPath + AllFilesMask, faAnyFile, sr) = 0) then
    repeat
      Result:=(sr.Name = '.') or (sr.Name = '..');
    until not Result or (FindNext(sr) <> 0);
  {$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}SysUtils.FindClose(sr);
end;

class function TDirectory.IsRelativePath(const aPath: string): Boolean;
begin
  Result:=TPath.IsRelativePath(aPath);
end;

Function SpecialDir(Const Info : TSearchRec) : Boolean;

begin
  Result:=(Info.Attr and {$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}SysUtils.faDirectory <> 0) and (Info.Name='.') or (Info.Name='..');
end;

class procedure TDirectory.Move(const SourceDirName, DestDirName: string);

Var
  lSource,lDest : String;

  function DoCreateDestDir(const aPath: string; const aInfo: TSearchRec): Boolean;
  var
    lPath: string;
  begin
    Result:=True;
    if (Not aInfo.IsDirectory) or aInfo.IsCurrentOrParentDir then
      exit;
    lPath:=lDest;
    if SameFileName(aPath,SourceDirName) then
      lPath:=IncludeTrailingPathDelimiter(lPath+ExtractRelativePath(lSource,aPath));
    lPath:=lPath+aInfo.Name;
    CreateDir(lPath);
  end;

  function DoMoveSrcToDest(const aPath: string; const aInfo: TSearchRec): Boolean;
  var
    lSrc,lDestF: string;
  begin
    Result:=True;
    if aInfo.IsCurrentOrParentDir then
      exit;
    if aInfo.IsDirectory then
      begin
        lSrc:=TPath.Combine(aPath,aInfo.Name);
{$IFDEF WINDOWS}
        FileSetAttr(lSrc,{$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}SysUtils.faNormal);
{$ENDIF}
        RemoveDir(lSrc);
      end
    else
      begin
        lSrc:=TPath.Combine(aPath, aInfo.Name);
        lDestF:=lDest;
        if SameFileName(aPath,SourceDirName) then
          lDestF:=IncludeTrailingPathDelimiter(lDestF+ExtractRelativePath(lSource,aPath));
        lDestF:=lDest+aInfo.Name;
{$IFDEF WINDOWS}
        FileSetAttr(lSrc,{$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}SysUtils.faNormal);
{$ENDIF WINDOWS}
        RenameFile(lSrc,lDestF);
{$IFDEF WINDOWS}
        FileSetAttr(lDestf,aInfo.Attr);
{$ENDIF WINDOWS}
      end;
  end;


begin
  lSource:=IncludeTrailingPathDelimiter(SourceDirName);
  lDest:=IncludeTrailingPathDelimiter(DestDirName);
  ForceDirectories(DestDirName);
  ForAllEntries(lSource,allFilesMask,@DoCreateDestDir,@DoMoveSrcToDest,True);
  RemoveDir(SourceDirName);
end;

end.

