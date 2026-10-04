{
    Copyright (c) 1998-2002 by Florian Klaempfl and Peter Vreman

    This module provides some basic file/dir handling utils and classes

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program; if not, write to the Free Software
    Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

 ****************************************************************************
}
unit cfileutl;

{$i fpcdefs.inc}

{$define usedircache}

interface

    uses
{$ifdef hasunix}
      Baseunix,unix,
{$endif hasunix}
{$ifdef mswindows}
      Windows,
{$endif mswindows}
{$if defined(go32v2) or defined(watcom)}
      Dos,
{$endif}
{$ifdef macos}
      macutils,
{$endif macos}
{$IFNDEF USE_FAKE_SYSUTILS}
      SysUtils,
{$ELSE}
      fksysutl,
{$ENDIF}
      GlobType,
      CUtils,CClasses,
      Systems;

    type
      TCachedDirectory = class(TObject)
      private
        FName : TPathStr;
        FDirectoryEntries : TFPHashList;
        FCached : Boolean;
        FHasLongNames : Boolean;
        procedure FreeDirectoryEntries;
        function GetItemAttr(const AName: TCmdStr): longint;
        function TryUseCache: boolean;
        procedure ForceUseCache;
        procedure Reload;
      public
        constructor Create(const AName:TPathStr);
        destructor  destroy;override;
        function FileExists(const AName:TCmdStr):boolean;
        function FileExistsCaseAware(const path, fn: TCmdStr; out FoundName: TCmdStr):boolean;
        function DirectoryExists(const AName:TCmdStr):boolean;
        property DirectoryEntries:TFPHashList read FDirectoryEntries;
        property Name:TPathStr read FName;
      end;

      TCachedSearchRec = record
        Name       : TCmdStr;
        Attr       : longint;
        Pattern    : TCmdStr;
        CachedDir  : TCachedDirectory;
        EntryIndex : longint;
      end;

      PCachedDirectoryEntry =  ^TCachedDirectoryEntry;
      TCachedDirectoryEntry = record
        RealName: TCmdStr;
        Attr    : longint;
      end;

      TDirectoryCache = class
      private
        FDirectories : THashSet;
        function GetDirectory(const ADir:TCmdStr):TCachedDirectory;
      public
        constructor Create;
        destructor  destroy;override;
        function FileExists(const AName:TCmdStr):boolean;
        function FileExistsCaseAware(const path, fn: TCmdStr; out FoundName: TCmdStr):boolean;
        function DirectoryExists(const AName:TCmdStr):boolean;
        function FindFirst(const APattern:TCmdStr;var Res:TCachedSearchRec):boolean;
        function FindNext(var Res:TCachedSearchRec):boolean;
        function FindClose(var Res:TCachedSearchRec):boolean;
      end;

      { A ** tree supplies sources, never PPUs left by another build.  A
        directory without sources supplies no units.  Other files (objects,
        libraries, includes) are searched regardless of this setting. }
      TUnitSearch = (usBoth, usSources, usNone);
      TSearchPathItem = class(TCmdStrListItem)
        UnitSearch : TUnitSearch;
      end;

      TSearchPathList = class(TCmdStrList)
      private
        function NewPathSet:THashSet;
        function AddDir(const dir:TCmdStr;addfirst:boolean;present:THashSet):TSearchPathItem;
      public
        procedure AddPath(s:TCmdStr;addfirst:boolean);overload;
        procedure AddLibraryPath(const sysroot: TCmdStr; s:TCmdStr;addfirst:boolean);overload;
        procedure AddList(list:TSearchPathList;addfirst:boolean);
        function  FindFile(const f : TCmdStr;allowcache:boolean;var foundfile:TCmdStr):boolean;
      end;

    function  bstoslash(const s : TCmdStr) : TCmdStr;
    {Gives the absolute path to the current directory}
    function  GetCurrentDir:TCmdStr;
    {Gives the relative path to the current directory,
     with a trailing dir separator. E. g. on unix ./ }
    function CurDirRelPath(systeminfo: tsysteminfo): TCmdStr;
    function  path_absolute(const s : TCmdStr) : boolean;
    Function  PathExists (const F : TCmdStr;allowcache:boolean) : Boolean;
    Function  FileExists (const F : TCmdStr;allowcache:boolean) : Boolean;
    function  FileExistsNonCase(const path,fn:TCmdStr;allowcache:boolean;var foundfile:TCmdStr):boolean;
    Function  RemoveDir(d:TCmdStr):boolean;
    Function  FixPath(const s:TCmdStr;allowdot:boolean):TCmdStr;
    function  FixFileName(const s:TCmdStr):TCmdStr;
    function  TargetFixPath(s:TCmdStr;allowdot:boolean):TCmdStr;
    function  TargetFixFileName(const s:TCmdStr):TCmdStr;
    procedure SplitBinCmd(const s:TCmdStr;var bstr: TCmdStr;var cstr:TCmdStr);
    function  FindFile(const f : TCmdStr; const path : TCmdStr;allowcache:boolean;var foundfile:TCmdStr):boolean;
{    function  FindFilePchar(const f : TCmdStr;path : pchar;allowcache:boolean;var foundfile:TCmdStr):boolean;}
    function  FindFileInExeLocations(const bin:TCmdStr;allowcache:boolean;var foundfile:TCmdStr):boolean;
    function  FindExe(const bin:TCmdStr;allowcache:boolean;var foundfile:TCmdStr):boolean;
    function  GetShortName(const n:TCmdStr):TCmdStr;
    function maybequoted(const s:string):string;
    function maybequoted(const s:ansistring):ansistring;
    function maybequoted_for_script(const s:ansistring; quote_script: tscripttype):ansistring;

    procedure InitFileUtils;
    procedure DoneFileUtils;

    function UnixRequoteWithDoubleQuotes(const QuotedStr: TCmdStr): TCmdStr;
    function RequotedExecuteProcess(const Path: AnsiString; const ComLine: AnsiString; Flags: TExecuteFlags = []): Longint;
    function RequotedExecuteProcess(const Path: AnsiString; const ComLine: array of AnsiString; Flags: TExecuteFlags = []): Longint;
    function Shell(const command:ansistring): longint;

  { hide Sysutils.ExecuteProcess in units using this one after SysUtils}
  const
    ExecuteProcess = 'Do not use' deprecated 'Use cfileutil.RequotedExecuteProcess instead, ExecuteProcess cannot deal with single quotes as used by Unix command lines';

{ * Since native Amiga commands can't handle Unix-style relative paths used by the compiler,
    and some GNU tools, Unix2AmigaPath is needed to handle such situations (KB) * }


{$IFDEF HASAMIGA}
{ * PATHCONV is implemented in the Amiga/MorphOS system unit * }
{$NOTE TODO Amiga: implement PathConv() in System unit, which works with AnsiString}
function Unix2AmigaPath(path: ShortString): ShortString; external name 'PATHCONV';
{$ELSE}
function Unix2AmigaPath(path: String): String;
{$ENDIF}

{$if FPC_FULLVERSION < 20701}
type
  TRawByteSearchRec = TSearchRec;
{$endif}


implementation

    uses
      Comphook,
      Globals;

{$undef AllFilesMaskIsInRTL}

{$if (FPC_VERSION > 2)}
  {$define AllFilesMaskIsInRTL}
{$endif FPC_VERSION}

{$if (FPC_VERSION = 2) and (FPC_RELEASE > 2)}
  {$define AllFilesMaskIsInRTL}
{$endif}

{$if (FPC_VERSION = 2) and (FPC_RELEASE = 2) and (FPC_PATCH > 0)}
  {$define AllFilesMaskIsInRTL}
{$endif}

{$ifndef AllFilesMaskIsInRTL}
  {$if defined(go32v2) or defined(watcom)}
  const
    AllFilesMask = '*.*';
  {$else}
  const
    AllFilesMask = '*';
  {$endif not (go32v2 or watcom)}
{$endif not AllFilesMaskIsInRTL}
    var
      DirCache : TDirectoryCache;


{$IFNDEF HASAMIGA}
{ Stub function for Unix2Amiga Path conversion functionality, only available in
  Amiga/MorphOS RTL. I'm open for better solutions. (KB) }
function Unix2AmigaPath(path: String): String;
begin
  Unix2AmigaPath:=path;
end;
{$ENDIF}



{****************************************************************************
                           TCachedDirectory
****************************************************************************}

    constructor TCachedDirectory.create(const AName:TPathStr);
      begin
        inherited create;
        FName:=AName;
        FDirectoryEntries:=TFPHashList.Create;
        FCached:=False;
      end;


    destructor TCachedDirectory.destroy;
      begin
        FreeDirectoryEntries;
        FDirectoryEntries.Free;
        FDirectoryEntries := nil;
        inherited destroy;
      end;


    function TCachedDirectory.TryUseCache:boolean;
      begin
        Result:=not FHasLongNames;
        if FCached then
          exit;
        if not current_settings.disabledircache then
          begin
            ForceUseCache;
            Result:=not FHasLongNames;
          end
        else
          Result:=False;
      end;


    procedure TCachedDirectory.ForceUseCache;
      begin
        if not FCached then
          begin
            FCached:=True;
            Reload;
          end;
      end;


    procedure TCachedDirectory.FreeDirectoryEntries;
      var
        i: Integer;
      begin
        if not(tf_files_case_aware in source_info.flags) then
          exit;
        for i := 0 to DirectoryEntries.Count-1 do
          dispose(PCachedDirectoryEntry(DirectoryEntries[i]));
      end;


    function TCachedDirectory.GetItemAttr(const AName: TCmdStr): longint;
      var
        entry: PCachedDirectoryEntry;
      begin
        if not(tf_files_case_sensitive in source_info.flags) then
          if (tf_files_case_aware in source_info.flags) then
            begin
              entry:=PCachedDirectoryEntry(DirectoryEntries.Find(Lower(AName)));
              if assigned(entry) then
                Result:=entry^.Attr
              else
                Result:=0;
            end
          else
            Result:=PtrUInt(DirectoryEntries.Find(Lower(AName)))
        else
          Result:=PtrUInt(DirectoryEntries.Find(AName));
      end;


    procedure TCachedDirectory.Reload;
      var
        dir   : TRawByteSearchRec;
        entry : PCachedDirectoryEntry;
      begin
        FreeDirectoryEntries;
        DirectoryEntries.Clear;
        FHasLongNames:=False;
        if findfirst(IncludeTrailingPathDelimiter(Name)+AllFilesMask,faAnyFile or faDirectory,dir) = 0 then
          begin
            repeat
              if ((dir.attr and faDirectory)<>faDirectory) or
                 ((dir.Name<>'.') and
                  (dir.Name<>'..')) then
                begin
                  { Force Archive bit so the attribute always has a value. This is needed
                    to be able to see the difference in the directoryentries lookup if a file
                    exists or not }
                  Dir.Attr:=Dir.Attr or faArchive;
                  { A truncated key can also collide with a shorter name.
                    Such a directory uses OS lookup; enumeration stays cached. }
                  FHasLongNames:=FHasLongNames or (Length(Dir.Name)>255);
                  if not(tf_files_case_sensitive in source_info.flags) then
                    if (tf_files_case_aware in source_info.flags) then
                      begin
                        new(entry);
                        entry^.RealName:=Dir.Name;
                        entry^.Attr:=Dir.Attr;
                        DirectoryEntries.Add(Lower(Dir.Name),entry)
                      end
                    else
                      DirectoryEntries.Add(Lower(Dir.Name),Pointer(Ptrint(Dir.Attr)))
                  else
                    DirectoryEntries.Add(Dir.Name,Pointer(Ptrint(Dir.Attr)));
                end;
            until findnext(dir) <> 0;
            findclose(dir);
          end;
      end;


    function TCachedDirectory.FileExists(const AName:TCmdStr):boolean;
      var
        Attr : Longint;
      begin
        if (Length(AName)>255) or not TryUseCache then
          begin
            { prepend directory name again }
            result:=cfileutl.FileExists(Name+AName,false);
            exit;
          end;
        Attr:=GetItemAttr(AName);
        if Attr<>0 then
          Result:=((Attr and faDirectory)=0)
        else
          Result:=false;
      end;


    function TCachedDirectory.FileExistsCaseAware(const path, fn: TCmdStr; out FoundName: TCmdStr):boolean;
      var
        entry : PCachedDirectoryEntry;
      begin
        if (tf_files_case_aware in source_info.flags) then
          begin
            { The short-key entry cache remains cheap for ordinary names.
              Long UTF-8 names use the same OS lookup as disabled caching. }
            if (Length(ExtractFileName(fn))>255) or not TryUseCache then
              begin
                Result:=FileExistsNonCase(path,fn,false,FoundName);
                exit;
              end;
            entry:=PCachedDirectoryEntry(DirectoryEntries.Find(Lower(ExtractFileName(fn))));
            if assigned(entry) and
               (entry^.Attr<>0) and
               ((entry^.Attr and faDirectory) = 0) then
              begin
                 FoundName:=ExtractFilePath(path+fn)+entry^.RealName;
                 Result:=true
              end
            else
              Result:=false;
          end
        else
          { should not be called in this case, use plain FileExists }
          Result:=False;
      end;


    function TCachedDirectory.DirectoryExists(const AName:TCmdStr):boolean;
      var
        Attr : Longint;
      begin
        if (Length(AName)>255) or not TryUseCache then
          begin
            Result:=PathExists(Name+AName,false);
            exit;
          end;
        Attr:=GetItemAttr(AName);
        if Attr<>0 then
          Result:=((Attr and faDirectory)=faDirectory)
        else
          Result:=false;
      end;


{****************************************************************************
                           TDirectoryCache
****************************************************************************}

    constructor TDirectoryCache.create;
      begin
        inherited create;
        FDirectories:=THashSet.Create(64,true,true);
      end;


    destructor TDirectoryCache.destroy;
      begin
        FDirectories.Free;
        FDirectories := nil;
        inherited destroy;
      end;


    function TDirectoryCache.GetDirectory(const ADir:TCmdStr):TCachedDirectory;
      var
        DirName   : TCmdStr;
        Entry     : PHashSetItem;
      begin
        if ADir='' then
          DirName:='.'+source_info.DirSep
        else
          DirName:=ADir;
        Entry:=FDirectories.FindOrAdd(pointer(DirName),Length(DirName));
        if not assigned(Entry^.Data) then
          Entry^.Data:=TCachedDirectory.Create(DirName);
        Result:=TCachedDirectory(Entry^.Data);
      end;


    function TDirectoryCache.FileExists(const AName:TCmdStr):boolean;
      var
        CachedDir : TCachedDirectory;
      begin
        Result:=false;
        CachedDir:=GetDirectory(ExtractFilePath(AName));
        if assigned(CachedDir) then
          Result:=CachedDir.FileExists(ExtractFileName(AName));
      end;


    function TDirectoryCache.FileExistsCaseAware(const path, fn: TCmdStr; out FoundName: TCmdStr):boolean;
      var
        CachedDir : TCachedDirectory;
      begin
        Result:=false;
        CachedDir:=GetDirectory(ExtractFilePath(path+fn));
        if assigned(CachedDir) then
          Result:=CachedDir.FileExistsCaseAware(path,fn,FoundName);
      end;


    function TDirectoryCache.DirectoryExists(const AName:TCmdStr):boolean;
      var
        CachedDir : TCachedDirectory;
      begin
        Result:=false;
        CachedDir:=GetDirectory(ExtractFilePath(AName));
        if assigned(CachedDir) then
          Result:=CachedDir.DirectoryExists(ExtractFileName(AName));
      end;


    function TDirectoryCache.FindFirst(const APattern:TCmdStr;var Res:TCachedSearchRec):boolean;
      begin
        Res.Pattern:=ExtractFileName(APattern);
        Res.CachedDir:=GetDirectory(ExtractFilePath(APattern));
        Res.CachedDir.ForceUseCache;
        Res.EntryIndex:=0;
        if assigned(Res.CachedDir) then
          Result:=FindNext(Res)
        else
          Result:=false;
      end;


    function TDirectoryCache.FindNext(var Res:TCachedSearchRec):boolean;
      var
        entry: PCachedDirectoryEntry;
      begin
        if Res.EntryIndex<Res.CachedDir.DirectoryEntries.Count then
          begin
            if (tf_files_case_aware in source_info.flags) then
              begin
                entry:=Res.CachedDir.DirectoryEntries[Res.EntryIndex];
                Res.Name:=entry^.RealName;
                Res.Attr:=entry^.Attr;
              end
            else
              begin
                Res.Name:=Res.CachedDir.DirectoryEntries.NameOfIndex(Res.EntryIndex);
                Res.Attr:=PtrUInt(Res.CachedDir.DirectoryEntries[Res.EntryIndex]);
              end;
            inc(Res.EntryIndex);
            Result:=true;
          end
        else
          Result:=false;
      end;


    function TDirectoryCache.FindClose(var Res:TCachedSearchRec):boolean;
      begin
        { nothing todo }
        result:=true;
      end;


{****************************************************************************
                                   Utils
****************************************************************************}

    function bstoslash(const s : TCmdStr) : TCmdStr;
    {
      return TCmdStr s with all \ changed into /
    }
      var
         i : sizeint;
      begin
        bstoslash:=s;
        for i:=1 to length(s) do
         if s[i]='\' then
          bstoslash[i]:='/';
      end;


   {Gives the absolute path to the current directory}
     var
       CachedCurrentDir : TCmdStr;
   function GetCurrentDir:TCmdStr;
     begin
       if CachedCurrentDir='' then
         begin
           GetDir(0,CachedCurrentDir);
           CachedCurrentDir:=FixPath(CachedCurrentDir,false);
         end;
       result:=CachedCurrentDir;
     end;

   {Gives the relative path to the current directory,
    with a trailing dir separator. E. g. on unix ./ }
   function CurDirRelPath(systeminfo: tsysteminfo): TCmdStr;

   begin
     if systeminfo.system <> system_powerpc_macosclassic then
       CurDirRelPath:= '.'+systeminfo.DirSep
     else
       CurDirRelPath:= ':'
   end;


   function path_absolute(const s : TCmdStr) : boolean;
   {
     is path s an absolute path?
   }
     begin
        result:=false;
{$if defined(unix)}
        if (length(s)>0) and (s[1] in AllowDirectorySeparators) then
          result:=true;
{$elseif defined(hasamiga)}
        (* An Amiga path is absolute, if it has a volume/device name in it (contains ":"),
           otherwise it's always a relative path, no matter if it starts with a directory
           separator or not. (KB) *)
        if (length(s)>0) and (Pos(':',s) <> 0) then
          result:=true;
{$elseif defined(macos)}
        if IsMacFullPath(s) then
          result:=true;
{$elseif defined(netware)}
        if (Pos (DriveSeparator, S) <> 0) or
                ((Length (S) > 0) and (S [1] in AllowDirectorySeparators)) then
          result:=true;
{$elseif defined(win32) or defined(win64) or defined(go32v2) or defined(os2) or defined(watcom)}
        if ((length(s)>0) and (s[1] in AllowDirectorySeparators)) or
(* The following check for non-empty AllowDriveSeparators assumes that all
   other platforms supporting drives and not handled as exceptions above
   should work with DOS-like paths, i.e. use absolute paths with one letter
   for drive followed by path separator *)
           ((length(s)>2) and (s[2] in AllowDriveSeparators) and (s[3] in AllowDirectorySeparators)) then
          result:=true;
{$else}
        if ((length(s)>0) and (s[1] in AllowDirectorySeparators)) or
(* The following check for non-empty AllowDriveSeparators assumes that all
   other platforms supporting drives and not handled as exceptions above
   should work with DOS-like paths, i.e. use absolute paths with one letter
   for drive followed by path separator *)
           ((AllowDriveSeparators <> []) and (length(s)>2) and (s[2] in AllowDriveSeparators) and (s[3] in AllowDirectorySeparators)) then
          result:=true;
{$endif unix}
     end;

    Function FileExists ( Const F : TCmdStr;allowcache:boolean) : Boolean;
      begin
{$ifdef usedircache}
        if allowcache then
          Result:=DirCache.FileExists(F)
        else
{$endif usedircache}
          Result:=SysUtils.FileExists(F);
        if do_checkverbosity(V_Tried) then
         begin
           if Result then
             do_comment(V_Tried,'Searching file '+F+'... found')
           else
             do_comment(V_Tried,'Searching file '+F+'... not found');
         end;
      end;


    function FileExistsNonCase(const path,fn:TCmdStr;allowcache:boolean;var foundfile:TCmdStr):boolean;
      var
        fn2 : TCmdStr;
      begin
        result:=false;
        if tf_files_case_sensitive in source_info.flags then
          begin
            {
              Search order for case sensitive systems:
               1. NormalCase
               2. lowercase
               3. UPPERCASE
            }
            FoundFile:=path+fn;
            If (ftNone in AllowedFilenameTransFormations) and FileExists(FoundFile,allowcache) then
             begin
               result:=true;
               exit;
             end;
            if (ftLowerCase in AllowedFilenameTransFormations) then
              begin
                fn2:=Lower(fn);
                if (fn2<>fn) then
                  begin
                    FoundFile:=path+fn2;
                    If FileExists(FoundFile,allowcache) then
                     begin
                       result:=true;
                       exit;
                     end;
                  end;
              end;
            if (ftUpperCase in AllowedFilenameTransFormations)  then
              begin
                fn2:=Upper(fn);
                if (fn2<>fn) then
                  begin
                  FoundFile:=path+fn2;
                  If FileExists(FoundFile,allowcache) then
                    begin
                      result:=true;
                      exit;
                    end;
                  end;
              end;
          end
        else
          if tf_files_case_aware in source_info.flags then
            begin
              {
                Search order for case aware systems:
                 1. NormalCase
              }
{$ifdef usedircache}
              if allowcache then
                begin
                  result:=DirCache.FileExistsCaseAware(path,fn,fn2);
                  if result then
                    begin
                      FoundFile:=fn2;
                      exit;
                    end;
                end
              else
{$endif usedircache}
                begin
                  FoundFile:=path+fn;
                  If FileExists(FoundFile,allowcache) then
                    begin
                      { don't know the real name in this case }
                      result:=true;
                      exit;
                   end;
                end;
           end
        else
          begin
            { None case sensitive only lowercase }
            FoundFile:=path+Lower(fn);
            If FileExists(FoundFile,allowcache) then
             begin
               result:=true;
               exit;
             end;
          end;
        { Set foundfile to something useful }
        FoundFile:=fn;
      end;


    Function PathExists (const F : TCmdStr;allowcache:boolean) : Boolean;
      Var
        i: longint;
        hs : TCmdStr;
      begin
        if F = '' then
          begin
            result := true;
            exit;
          end;
        hs := ExpandFileName(F);
        I := Pos (DriveSeparator, hs);
        if (hs [Length (hs)] = DirectorySeparator) and
           (((I = 0) and (Length (hs) > 1)) or (I <> Length (hs) - 1)) then
          Delete (hs, Length (hs), 1);
{$ifdef usedircache}
        if allowcache then
          Result:=DirCache.DirectoryExists(hs)
        else
{$endif usedircache}
          Result:=SysUtils.DirectoryExists(hs);
      end;


    Function RemoveDir(d:TCmdStr):boolean;
      begin
        if d[length(d)]=source_info.DirSep then
         Delete(d,length(d),1);
        {$push}{$I-}
         rmdir(d);
        {$pop}
        RemoveDir:=(ioresult=0);
      end;


    Function _FixPath(const s:TCmdStr;allowdot:boolean;const info:tsysteminfo;const drivesep:string):TCmdStr;
      var
        i, L : sizeint;
      begin
        Result := s;
        L := Length(Result);
        if L=0 then
          exit;
        { Fix separator }
        for i:=1 to L do
          if (Result[i] in ['/','\']) and (Result[i]<>info.DirSep) then
            Result[i]:=info.DirSep;
        { Remove . or ./ }
        if (not allowdot) and (Result[1]='.') and ((L=1) or (L=2) and (Result[2]=info.DirSep)) then
          exit('');
        { Fix ending / }
        if (Result[L]<>info.DirSep) and (Result[L]<>drivesep) then
          Result:=Result+info.DirSep;
        { return }
        if not ((tf_files_case_aware in info.flags) or
           (tf_files_case_sensitive in info.flags)) then
          Result := lower(Result);
      end;


    Function FixPath(const s:TCmdStr;allowdot:boolean):TCmdStr;
      begin
        Result:=_FixPath(s,allowdot,source_info,DriveSeparator);
      end;


  {Actually the version in macutils.pp could be used,
   but that would not work for crosscompiling, so this is a slightly modified
   version of it.}
  function TranslatePathToMac (const path: TCmdStr; mpw: Boolean): TCmdStr;

    function GetVolumeIdentifier: TCmdStr;

    begin
      GetVolumeIdentifier := '{Boot}'
      (*
      if mpw then
        GetVolumeIdentifier := '{Boot}'
      else
        GetVolumeIdentifier := macosBootVolumeName;
      *)
    end;

    var
      slashPos, oldpos, newpos, oldlen, maxpos: Longint;

  begin
    oldpos := 1;
    slashPos := Pos('/', path);
    TranslatePathToMac:='';
    if (slashPos <> 0) then   {its a unix path}
      begin
        if slashPos = 1 then
          begin      {its a full path}
            oldpos := 2;
            TranslatePathToMac := GetVolumeIdentifier;
          end
        else     {its a partial path}
          TranslatePathToMac := ':';
      end
    else
      begin
        slashPos := Pos('\', path);
        if (slashPos <> 0) then   {its a dos path}
          begin
            if slashPos = 1 then
              begin      {its a full path, without drive letter}
                oldpos := 2;
                TranslatePathToMac := GetVolumeIdentifier;
              end
            else if (Length(path) >= 2) and (path[2] = ':') then {its a full path, with drive letter}
              begin
                oldpos := 4;
                TranslatePathToMac := GetVolumeIdentifier;
              end
            else     {its a partial path}
              TranslatePathToMac := ':';
          end;
      end;

    if (slashPos <> 0) then   {its a unix or dos path}
      begin
        {Translate "/../" to "::" , "/./" to ":" and "/" to ":" }
        newpos := Length(TranslatePathToMac);
        oldlen := Length(path);
        SetLength(TranslatePathToMac, newpos + oldlen);  {It will be no longer than what is already}
                                                                        {prepended plus length of path.}
        maxpos := Length(TranslatePathToMac);          {Get real maxpos, can be short if String is ShortString}

        {There is never a slash in the beginning, because either it was an absolute path, and then the}
        {drive and slash was removed, or it was a relative path without a preceding slash.}
        while oldpos <= oldlen do
          begin
            {Check if special dirs, ./ or ../ }
            if path[oldPos] = '.' then
              if (oldpos + 1 <= oldlen) and (path[oldPos + 1] = '.') then
                begin
                  if (oldpos + 2 > oldlen) or (path[oldPos + 2] in ['/', '\']) then
                    begin
                      {It is "../" or ".."  translates to ":" }
                      if newPos = maxPos then
                        begin {Shouldn't actually happen, but..}
                          Exit('');
                        end;
                      newPos := newPos + 1;
                      TranslatePathToMac[newPos] := ':';
                      oldPos := oldPos + 3;
                      continue;  {Start over again}
                    end;
                end
              else if (oldpos + 1 > oldlen) or (path[oldPos + 1] in ['/', '\']) then
                begin
                  {It is "./" or "."  ignore it }
                  oldPos := oldPos + 2;
                  continue;  {Start over again}
                end;

            {Collect file or dir name}
            while (oldpos <= oldlen) and not (path[oldPos] in ['/', '\']) do
              begin
                if newPos = maxPos then
                  begin {Shouldn't actually happen, but..}
                    Exit('');
                  end;
                newPos := newPos + 1;
                TranslatePathToMac[newPos] := path[oldPos];
                oldPos := oldPos + 1;
              end;

            {When we come here there is either a slash or we are at the end.}
            if (oldpos <= oldlen) then
              begin
                if newPos = maxPos then
                  begin {Shouldn't actually happen, but..}
                    Exit('');
                  end;
                newPos := newPos + 1;
                TranslatePathToMac[newPos] := ':';
                oldPos := oldPos + 1;
              end;
          end;

        SetLength(TranslatePathToMac, newpos);
      end
    else if (path = '.') then
      TranslatePathToMac := ':'
    else if (path = '..') then
      TranslatePathToMac := '::'
    else
      TranslatePathToMac := path;  {its a mac path}
  end;


   function _FixFileName(const s:TCmdStr; const info:tsysteminfo):TCmdStr;
     var
       i      : sizeint;
     begin
       if info.system = system_powerpc_macosclassic then
         Result:=TranslatePathToMac(s, true)
       else
        begin
          if (tf_files_case_aware in info.flags) or
             (tf_files_case_sensitive in info.flags) then
            Result:=s
          else
            Result:=Lower(s);
          for i:=1 to length(s) do
           case s[i] of
             '/','\' :
               if s[i]<>info.dirsep then
                 Result[i]:=info.dirsep;
           end;
        end;
     end;


   function FixFileName(const s:TCmdStr):TCmdStr;
     begin
       result:=_FixFileName(s,source_info);
     end;


   Function TargetFixPath(s:TCmdStr;allowdot:boolean):TCmdStr;
     begin
       result:=_FixPath(s,allowdot,target_info,':');
     end;


   function TargetFixFileName(const s:TCmdStr):TCmdStr;
     begin
       result:=_FixFileName(s,target_info);
     end;


   procedure SplitBinCmd(const s:TCmdStr;var bstr:TCmdStr;var cstr:TCmdStr);
     var
       i : longint;
     begin
       i:=pos(' ',s);
       if i>0 then
        begin
          bstr:=Copy(s,1,i-1);
          cstr:=Copy(s,i+1,length(s)-i);
        end
       else
        begin
          bstr:=s;
          cstr:='';
        end;
     end;


    { The name under which the file system knows a directory: two entries of
      a search path are the same directory when their keys are equal. }
    function PathKey(const path:TCmdStr):TCmdStr;
      begin
        result:=ExpandFileName(path);
        If not (tf_files_case_sensitive in source_info.flags) then
          result:=lower(result);
      end;


    { The keys of the directories in the list, so that adding a directory
      does not compare it with every one already there: a tree of thousands
      of directories would otherwise cost millions of comparisons each time
      it is added to a list. }
    function TSearchPathList.NewPathSet:THashSet;
      var
        hp : TCmdStrListItem;
        key : TCmdStr;
      begin
        result:=THashSet.Create(Count,true,false);
        hp:=TCmdStrListItem(First);
        while assigned(hp) do
          begin
            key:=PathKey(hp.Str);
            result.FindOrAdd(pointer(key),length(key));
            hp:=TCmdStrListItem(hp.Next);
          end;
      end;


    { dir in front of the list (moved there when it is in the list) or at its
      end (left where it is when it is in the list); the new entry, nil when
      the directory stayed where it was }
    function TSearchPathList.AddDir(const dir:TCmdStr;addfirst:boolean;present:THashSet):TSearchPathItem;
      var
        key : TCmdStr;
        known : boolean;
        previous : TCmdStrListItem;
      begin
        result:=nil;
        key:=PathKey(dir);
        present.FindOrAdd(pointer(key),length(key),known);
        if addfirst then
          begin
            if known then
              begin
                previous:=TCmdStrListItem(First);
                while PathKey(previous.Str)<>key do
                  previous:=TCmdStrListItem(previous.Next);
                TLinkedList(Self).Remove(previous);
                previous.Free;
              end;
            result:=TSearchPathItem.Create(dir);
            InsertItem(result);
          end
        else if not known then
          begin
            result:=TSearchPathItem.Create(dir);
            ConcatItem(result);
          end;
      end;


    { the name of a unit source or a compiled unit, without a directory part }
    function IsUnitFileName(const fn:TCmdStr):boolean;
      var
        ext : TCmdStr;
      begin
        if ExtractFilePath(fn)<>'' then
          exit(false);
        ext:=lower(ExtractFileExt(fn));
        result:=(ext=pasext) or (ext=sourceext) or (ext=pext) or (ext=target_info.unitext);
      end;


    procedure TSearchPathList.AddPath(s:TCmdStr;addfirst:boolean);
      begin
        AddLibraryPath('',s,AddFirst);
      end;


   procedure TSearchPathList.AddLibraryPath(const sysroot: TCmdStr; s:TCmdStr;addfirst:boolean);

     type
       TDirList = array of TCmdStr;
       { a directory on disk: two paths name the same directory exactly when
         both fields are equal }
       TDirIdentity = record
         volume,
         index : qword;
       end;

     var
       staridx,
       i,j      : longint;
       prefix,
       suffix,
       CurrentDir,
       currPath : TCmdStr;
       subdirfound : boolean;
{$ifdef usedircache}
       dir      : TCachedSearchRec;
{$else usedircache}
       dir      : TSearchRec;
{$endif usedircache}
       present  : THashSet;
       { recursive ** support }
       recdirs,
       chain,
       unitmap_names,
       unitmap_dirs : TDirList;
       recsearch : array of TUnitSearch;
       recdircount,
       chaincount,
       unitmap_count,
       ri, di : longint;
       item : TSearchPathItem;

       procedure WarnNonExistingPath(const path : TCmdStr);
       begin
         if do_checkverbosity(V_Tried) then
           do_comment(V_Tried,'Path "'+path+'" not found');
       end;

       function PathSet:THashSet;
       begin
         if not assigned(present) then
           present:=NewPathSet;
         result:=present;
       end;

       procedure AddCurrPath;
       begin
         AddDir(currPath,addfirst,PathSet);
       end;

       function InList(const path:TCmdStr):boolean;
       var
         key : TCmdStr;
       begin
         key:=PathKey(path);
         result:=assigned(PathSet.Find(pointer(key),length(key)));
       end;

       { The directory a path leads to, links followed; false when the file
         system does not tell. }
       function GetDirIdentity(const dir: TCmdStr; out id: TDirIdentity): boolean;
{$if defined(hasunix)}
       var
         info : baseunix.stat;
       begin
         result:=fpstat(dir,info)=0;
         id.volume:=info.st_dev;
         id.index:=info.st_ino;
       end;
{$elseif defined(mswindows)}
       var
         handle : THandle;
         info : BY_HANDLE_FILE_INFORMATION;
       begin
         result:=false;
         id.volume:=0;
         id.index:=0;
         handle:=CreateFileW(PWideChar(UnicodeString(dir)),0,
           FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE,nil,OPEN_EXISTING,
           FILE_FLAG_BACKUP_SEMANTICS,0);
         if handle=INVALID_HANDLE_VALUE then
           exit;
         if GetFileInformationByHandle(handle,@info) then
           begin
             id.volume:=info.dwVolumeSerialNumber;
             id.index:=(qword(info.nFileIndexHigh) shl 32) or info.nFileIndexLow;
             { a file system without file indices reports zero for every file }
             result:=id.index<>0;
           end;
         CloseHandle(handle);
       end;
{$else}
       begin
         id.volume:=0;
         id.index:=0;
         result:=false;
       end;
{$endif}

       { A directory link to a directory of the chain being walked would walk
         that tree again inside itself, as deep as the OS allows a path. }
       function LinksBackIntoChain(const link: TCmdStr): boolean;
       var
         target,
         id : TDirIdentity;
         k : longint;
       begin
         result:=false;
         if not GetDirIdentity(link,target) then
           exit;
         for k:=0 to chaincount-1 do
           if GetDirIdentity(chain[k],id) and
              (id.volume=target.volume) and (id.index=target.index) then
             exit(true);
       end;

       { Appends dir to the ** tree and warns about each of its unit sources
         whose name an earlier directory of the tree holds: the earlier one is
         the one the compiler finds. }
       procedure AddRecursiveDir(const dir: TCmdStr; const sources: TDirList; sourcecount: longint;
         search: TUnitSearch);
       var
         si,
         umi : longint;
         uname : TCmdStr;
         known : boolean;
       begin
         if recdircount>=Length(recdirs) then
           begin
             SetLength(recdirs,recdircount*2+16);
             SetLength(recsearch,Length(recdirs));
           end;
         recdirs[recdircount]:=dir;
         recsearch[recdircount]:=search;
         Inc(recdircount);
         for si:=0 to sourcecount-1 do
           begin
             uname:=lower(ChangeFileExt(sources[si],''));
             known:=false;
             for umi:=0 to unitmap_count-1 do
               if unitmap_names[umi]=uname then
                 begin
                   do_comment(V_Warning,
                     'Duplicate unit "'+sources[si]+'" found in "'+
                     unitmap_dirs[umi]+'" and "'+dir+'" under recursive search');
                   known:=true;
                   break;
                 end;
             if not known then
               begin
                 if unitmap_count>=Length(unitmap_names) then
                   begin
                     SetLength(unitmap_names,unitmap_count+256);
                     SetLength(unitmap_dirs,unitmap_count+256);
                   end;
                 unitmap_names[unitmap_count]:=uname;
                 unitmap_dirs[unitmap_count]:=dir;
                 Inc(unitmap_count);
               end;
           end;
       end;

       { dir and, depth first, every directory below it: a directory comes
         before its subdirectories, and they follow in sorted order, so the
         order is the same on every OS and for a path from any source.  Only
         two kinds of directories stay out.  A hidden one (the name starts
         with a dot: version control, IDE and tool state; a shell's ** does
         not enter it either) is not entered.  A directory that holds
         compiled units and no unit source is build output
         (units/<target>/<profile>, lib/<cpu>-<os>, ...): a PPU found there
         instead of its source was compiled with other options and would be
         linked silently, so the directory is not added, and the walk goes
         on below it.  A directory without any unit file is added as usNone.
         A directory link is followed unless it leads back into the chain
         being walked. }
       procedure CollectRecursiveDirs(const dir: TCmdStr);
       var
         rdir : TSearchRec;
         children,
         sources : TDirList;
         childcount,
         sourcecount,
         ci, cj : longint;
         hascompiled,
         hasothersource : boolean;
         ext,
         tmp : TCmdStr;
       begin
         children:=nil;
         sources:=nil;
         childcount:=0;
         sourcecount:=0;
         hascompiled:=false;
         hasothersource:=false;
         if chaincount>=Length(chain) then
           SetLength(chain,chaincount+16);
         chain[chaincount]:=dir;
         Inc(chaincount);
{$push}{$warn symbol_platform off}
         if FindFirst(dir+AllFilesMask,faAnyFile or faSymLink,rdir)=0 then
           begin
             repeat
               if (rdir.attr and faDirectory)<>0 then
                 begin
                   { '.' and '..' start with a dot as well }
                   if (rdir.name[1]<>'.') and
                      (((rdir.attr and faSymLink)=0) or
                       not LinksBackIntoChain(dir+rdir.name)) then
                     begin
                       if childcount>=Length(children) then
                         SetLength(children,childcount+32);
                       children[childcount]:=rdir.name;
                       Inc(childcount);
                     end;
                 end
               else
                 begin
                   ext:=lower(ExtractFileExt(rdir.name));
                   if (ext=pasext) or (ext=sourceext) then
                     begin
                       if sourcecount>=Length(sources) then
                         SetLength(sources,sourcecount+32);
                       sources[sourcecount]:=rdir.name;
                       Inc(sourcecount);
                     end
                   else if ext=pext then
                     hasothersource:=true
                   else if ext=target_info.unitext then
                     hascompiled:=true;
                 end;
             until FindNext(rdir)<>0;
             SysUtils.FindClose(rdir);
           end;
{$pop}
         if (sourcecount>0) or hasothersource then
           AddRecursiveDir(dir,sources,sourcecount,usSources)
         else if not hascompiled then
           AddRecursiveDir(dir,sources,sourcecount,usNone);
         { Sort children alphabetically for deterministic order }
         for ci:=0 to childcount-2 do
           for cj:=ci+1 to childcount-1 do
             if children[cj]<children[ci] then
               begin
                 tmp:=children[ci];
                 children[ci]:=children[cj];
                 children[cj]:=tmp;
               end;
         for ci:=0 to childcount-1 do
           CollectRecursiveDirs(dir+children[ci]+DirectorySeparator);
         Dec(chaincount);
       end;

     begin
       if s='' then
        exit;
     { Support default macro's }
       DefaultReplacements(s);
{$warnings off}
       if PathSeparator <> ';' then
        for i:=1 to length(s) do
         if s[i]=PathSeparator then
          s[i]:=';';
{$warnings on}
     { get current dir }
       CurrentDir:=GetCurrentDir;
       present:=nil;
       try
       repeat
         { get currpath }
         if addfirst then
          begin
            j:=length(s);
            while (j>0) and (s[j]<>';') do
             dec(j);
            currPath:= TrimSpace(Copy(s,j+1,length(s)-j));
            if j=0 then
             s:=''
            else
             System.Delete(s,j,length(s)-j+1);
          end
         else
          begin
            j:=Pos(';',s);
            if j=0 then
             j:=length(s)+1;
            currPath:= TrimSpace(Copy(s,1,j-1));
            System.Delete(s,1,j);
          end;

         { fix pathname }
         DePascalQuote(currPath);
         { GNU LD convention: if library search path starts with '=', it's relative to the
           sysroot; otherwise, interpret it as a regular path }
         if (length(currPath) >0) and (currPath[1]='=') then
           currPath:=sysroot+FixPath(copy(currPath,2,length(currPath)-1),false);
         if currPath='' then
           currPath:= CurDirRelPath(source_info)
         else
          begin
            currPath:=FixPath(ExpandFileName(currpath),false);
            if (not forcefullpaths) and
               (CurrentDir<>'') and (Copy(currPath,1,length(CurrentDir))=CurrentDir) then
             begin
{$ifdef hasamiga}
               currPath:= CurrentDir+Copy(currPath,length(CurrentDir)+1,length(currPath));
{$else}
               currPath:= CurDirRelPath(source_info)+Copy(currPath,length(CurrentDir)+1,length(currPath));
{$endif}
             end;
          end;
         { Recursive search: -Fu<dir>/** adds the directory and all
           subdirectories (any depth) except hidden ones and build output,
           see CollectRecursiveDirs.  Duplicate unit names across the tree
           produce a warning. }
         staridx:=pos('**',currpath);
         if (staridx>1) and
            (currpath[staridx-1] in ['/','\']) and
            ((staridx+1=length(currpath)) or
             ((staridx+2=length(currpath)) and (currpath[staridx+2] in ['/','\']))) then
          begin
            prefix:=Copy(currpath,1,staridx-1); { base dir with trailing sep }
            if PathExists(prefix,true) then
              begin
                recdircount:=0;
                chaincount:=0;
                unitmap_count:=0;
                CollectRecursiveDirs(prefix);
                { in the order of the tree: a path added first goes to the
                  front one directory at a time, so from the last one back }
                for ri:=0 to recdircount-1 do
                  begin
                    if addfirst then
                      di:=recdircount-1-ri
                    else
                      di:=ri;
                    item:=AddDir(recdirs[di],addfirst,PathSet);
                    if assigned(item) then
                      item.UnitSearch:=recsearch[di];
                  end;
              end
            else
              WarnNonExistingPath(prefix);
          end
         else
          begin
         { Single-level wildcard: -Fu<dir>/* }
         staridx:=pos('*',currpath);
         if staridx>0 then
          begin
            prefix:=ExtractFilePath(Copy(currpath,1,staridx));
            suffix:=Copy(currpath,staridx+1,length(currpath));
            subdirfound:=false;
{$ifdef usedircache}
            if DirCache.FindFirst(Prefix+AllFilesMask,dir) then
              begin
                repeat
                  if (dir.attr and faDirectory)<>0 then
                    begin
                      subdirfound:=true;
                      currpath:=prefix+dir.name+suffix;
                      if (suffix='') or PathExists(currpath,true) then
                        begin
                          if not InList(currPath) then
                            AddCurrPath;
                        end;
                    end;
                until not DirCache.FindNext(dir);
              end;
            DirCache.FindClose(dir);
{$else usedircache}
            if findfirst(prefix+AllFilesMask,faDirectory,dir) = 0 then
              begin
                repeat
                  if (dir.name<>'.') and
                      (dir.name<>'..') and
                      ((dir.attr and faDirectory)<>0) then
                    begin
                      subdirfound:=true;
                      currpath:=prefix+dir.name+suffix;
                      if (suffix='') or PathExists(currpath,false) then
                        begin
                          if not InList(currPath) then
                            AddCurrPath;
                        end;
                    end;
                until findnext(dir) <> 0;
                FindClose(dir);
              end;
{$endif usedircache}
            if not subdirfound then
              WarnNonExistingPath(currpath);
          end
         else
          begin
            if PathExists(currpath,true) then
             AddCurrPath
            else
             WarnNonExistingPath(currpath);
          end;
          end; { else of ** check }
       until (s='');
       finally
         present.Free;
       end;
     end;


   procedure TSearchPathList.AddList(list:TSearchPathList;addfirst:boolean);
     var
       hp : TCmdStrListItem;
       item : TSearchPathItem;
       present : THashSet;

       procedure AddItem(hp:TCmdStrListItem);
         begin
           item:=AddDir(hp.Str,addfirst,present);
           if assigned(item) and (hp is TSearchPathItem) then
             item.UnitSearch:=TSearchPathItem(hp).UnitSearch;
         end;

     begin
       if list.empty then
        exit;
       present:=NewPathSet;
       try
         { in front, in the order of list: from its last entry back }
         if addfirst then
          begin
            hp:=TCmdStrListItem(list.last);
            while assigned(hp) do
             begin
               AddItem(hp);
               hp:=TCmdStrListItem(hp.previous);
             end;
          end
         else
          begin
            hp:=TCmdStrListItem(list.first);
            while assigned(hp) do
             begin
               AddItem(hp);
               hp:=TCmdStrListItem(hp.next);
             end;
          end;
       finally
         present.Free;
       end;
     end;


   function TSearchPathList.FindFile(const f :TCmdStr;allowcache:boolean;var foundfile:TCmdStr):boolean;
     Var
       p : TCmdStrListItem;
       unitfile, compiledunit : boolean;
     begin
       FindFile:=false;
       unitfile:=IsUnitFileName(f);
       compiledunit:=unitfile and (lower(ExtractFileExt(f))=target_info.unitext);
       p:=TCmdStrListItem(first);
       while assigned(p) do
        begin
          if not (unitfile and (p is TSearchPathItem) and
                  ((TSearchPathItem(p).UnitSearch=usNone) or
                   (compiledunit and (TSearchPathItem(p).UnitSearch=usSources)))) then
            begin
              result:=FileExistsNonCase(p.Str,f,allowcache,FoundFile);
              if result then
                exit;
            end;
          p:=TCmdStrListItem(p.next);
        end;
       { Return original filename if not found }
       FoundFile:=f;
     end;


   function FindFile(const f : TCmdStr; const path : TCmdStr;allowcache:boolean;var foundfile:TCmdStr):boolean;
     Var
       StartPos, EndPos, L: LongInt;
     begin
       Result:=False;

       if (path_absolute(f)) then
         begin
           Result:=FileExistsNonCase('',f, allowcache, foundfile);
           if Result then
             Exit;
         end;

       StartPos := 1;
       L := Length(Path);
       repeat
         EndPos := StartPos;
         while (EndPos <= L) and ((Path[EndPos] <> PathSeparator) and (Path[EndPos] <> ';')) do
           Inc(EndPos);
         Result := FileExistsNonCase(FixPath(Copy(Path, StartPos, EndPos-StartPos), False), f, allowcache, FoundFile);
         if Result then
           Exit;
         StartPos := EndPos + 1;
       until StartPos > L;
       FoundFile:=f;
     end;

{
   function FindFilePchar(const f : TCmdStr;path : pchar;allowcache:boolean;var foundfile:TCmdStr):boolean;
      Var
        singlepathstring : TCmdStr;
        startpc,pc : pchar;
     begin
       FindFilePchar:=false;
       if Assigned (Path) then
        begin
          pc:=path;
          repeat
             startpc:=pc;
             while (pc^<>PathSeparator) and (pc^<>';') and (pc^<>#0) do
              inc(pc);
             SetLength(singlepathstring, pc-startpc);
             move(startpc^,singlepathstring[1],pc-startpc);
             singlepathstring:=FixPath(ExpandFileName(singlepathstring),false);
             result:=FileExistsNonCase(singlepathstring,f,allowcache,FoundFile);
             if result then
               exit;
             if (pc^=#0) then
               break;
             inc(pc);
          until false;
        end;
       foundfile:=f;
     end;
}

  function  FindFileInExeLocations(const bin:TCmdStr;allowcache:boolean;var foundfile:TCmdStr):boolean;
    var
      Path : TCmdStr;
      found : boolean;
    begin
       found:=FindFile(FixFileName(bin),exepath,allowcache,foundfile);
      if not found then
       begin
{$ifdef macos}
         Path:=GetEnvironmentVariable('Commands');
{$else}
         Path:=GetEnvironmentVariable('PATH');
{$endif}
         found:=FindFile(FixFileName(bin),Path,allowcache,foundfile);
       end;
      FindFileInExeLocations:=found;
    end;


   function  FindExe(const bin:TCmdStr;allowcache:boolean;var foundfile:TCmdStr):boolean;
     var
       b : TCmdStr;
     begin
       { change extension only on platforms that use an exe extension, otherwise on OpenBSD
         'ld.bfd' gets converted to 'ld' }
       if source_info.exeext<>'' then
         b:=ChangeFileExt(bin,source_info.exeext)
       else
         b:=bin;
       FindExe:=FindFileInExeLocations(b,allowcache,foundfile);
     end;


    function GetShortName(const n:TCmdStr):TCmdStr;
{$ifdef win32}
      var
        hs,hs2 : TCmdStr;
        i : longint;
{$endif}
{$if defined(go32v2) or defined(watcom)}
      var
        hs : shortstring;
{$endif}
      begin
        GetShortName:=n;
{$ifdef win32}
        hs:=n+#0;
        hs2:='';
        { may become longer in case of e.g. ".a" -> "a~1" or so }
        setlength(hs2,length(hs)*2);
        i:=Windows.GetShortPathName(@hs[1],@hs2[1],length(hs)*2);
        if (i>0) and (i<=length(hs)*2) then
          begin
            setlength(hs2,strlen(@hs2[1]));
            GetShortName:=hs2;
          end;
{$endif}
{$if defined(go32v2) or defined(watcom)}
        hs:=n;
        if Dos.GetShortName(hs) then
         GetShortName:=hs;
{$endif}
      end;


    function maybequoted(const s:string):string;
    const
      FORBIDDEN_CHARS_DOS = ['!', '@', '#', '$', '%', '^', '&', '*', '(', ')',
                         '{', '}', '''', '`', '~'];
      FORBIDDEN_CHARS_OTHER = ['!', '@', '#', '$', '%', '^', '&', '*', '(', ')',
                         '{', '}', '''', ':', '\', '`', '~'];
    var
      forbidden_chars: set of char;
      i  : integer;
      quote_script: tscripttype;
      quote_char: ansichar;
      quoted : boolean;
    begin
      if not(cs_link_on_target in current_settings.globalswitches) then
        quote_script:=source_info.script
      else
        quote_script:=target_info.script;
      if quote_script=script_dos then
        forbidden_chars:=FORBIDDEN_CHARS_DOS
      else
        begin
          forbidden_chars:=FORBIDDEN_CHARS_OTHER;
          if quote_script=script_unix then
            include(forbidden_chars,'"');
        end;
      if quote_script=script_unix then
        quote_char:=''''
      else
        quote_char:='"';

      quoted:=false;
      result:=quote_char;
      for i:=1 to length(s) do
       begin
         if s[i]=quote_char then
           begin
             quoted:=true;
             result:=result+'\'+quote_char;
           end
         else case s[i] of
           '\':
             begin
               if quote_script=script_unix then
                 begin
                   result:=result+'\\';
                   quoted:=true
                 end
               else
                 result:=result+'\';
             end;
           ' ',
           #128..#255 :
             begin
               quoted:=true;
               result:=result+s[i];
             end;
           else begin
             if s[i] in forbidden_chars then
               quoted:=True;
             result:=result+s[i];
           end;
         end;
       end;
      if quoted then
        result:=result+quote_char
      else
        result:=s;
    end;


    function maybequoted_for_script(const s:ansistring; quote_script: tscripttype):ansistring;
      const
        FORBIDDEN_CHARS_DOS = ['!', '@', '#', '$', '%', '^', '&', '*', '(', ')',
                           '{', '}', '''', '`', '~'];
        FORBIDDEN_CHARS_OTHER = ['!', '@', '#', '$', '%', '^', '&', '*', '(', ')',
                           '{', '}', '''', ':', '\', '`', '~'];
      var
        forbidden_chars: set of char;
        i  : integer;
        quote_char: ansichar;
        quoted : boolean;
      begin
        if quote_script=script_dos then
          forbidden_chars:=FORBIDDEN_CHARS_DOS
        else
          begin
            forbidden_chars:=FORBIDDEN_CHARS_OTHER;
            if quote_script=script_unix then
              include(forbidden_chars,'"');
          end;
        if quote_script=script_unix then
          quote_char:=''''
        else
          quote_char:='"';

        quoted:=false;
        result:=quote_char;
        for i:=1 to length(s) do
         begin
           if s[i]=quote_char then
             begin
               quoted:=true;
               result:=result+'\'+quote_char;
             end
           else case s[i] of
             '\':
               begin
                 if quote_script=script_unix then
                   begin
                     result:=result+'\\';
                     quoted:=true
                   end
                 else
                   result:=result+'\';
               end;
             ' ',
             #128..#255 :
               begin
                 quoted:=true;
                 result:=result+s[i];
               end;
             else begin
               if s[i] in forbidden_chars then
                 quoted:=True;
               result:=result+s[i];
             end;
           end;
         end;
        if quoted then
          result:=result+quote_char
        else
          result:=s;
      end;


    function maybequoted(const s:ansistring):ansistring;
      var
        quote_script: tscripttype;
      begin
        if not(cs_link_on_target in current_settings.globalswitches) then
          quote_script:=source_info.script
        else
          quote_script:=target_info.script;
        result:=maybequoted_for_script(s,quote_script);
      end;


    { requotes a string that was quoted for Unix for passing to ExecuteProcess,
      because it only supports Windows-style quoting; this routine assumes that
      everything that has to be quoted for Windows, was also quoted (but
      differently for Unix) -- which is the case }
    function UnixRequoteWithDoubleQuotes(const QuotedStr: TCmdStr): TCmdStr;
      var
        i: longint;
        temp: TCmdStr;
        inquotes: boolean;
      begin
        if QuotedStr='' then
          begin
            result:='';
            exit;
          end;
        inquotes:=false;
        result:='';
        i:=1;
        temp:='';
        while i<=length(QuotedStr) do
          begin
            case QuotedStr[i] of
              '''':
                begin
                  if not(inquotes) then
                    begin
                      inquotes:=true;
                      temp:=''
                    end
                  else
                    begin
                      { requote for Windows }
                      result:=result+maybequoted_for_script(temp,script_dos);
                      inquotes:=false;
                    end;
                end;
              '\':
                begin
                  if inquotes then
                    temp:=temp+QuotedStr[i+1]
                  else
                    result:=result+QuotedStr[i+1];
                  inc(i);
                end;
              else
                begin
                  if inquotes then
                    temp:=temp+QuotedStr[i]
                  else
                    result:=result+QuotedStr[i];
                end;
            end;
            inc(i);
          end;
      end;


    function RequotedExecuteProcess(const Path: AnsiString; const ComLine: AnsiString; Flags: TExecuteFlags): Longint;
      var
        quote_script: tscripttype;
      begin

        if do_checkverbosity(V_Executable) then
          do_comment(V_Executable,'Executing "'+Path+'" with command line "'+
            ComLine+'"');
        if (cs_link_on_target in current_settings.globalswitches) then
          quote_script:=target_info.script
        else
          quote_script:=source_info.script;
        if quote_script=script_unix then
          result:=sysutils.ExecuteProcess(Path,UnixRequoteWithDoubleQuotes(ComLine),Flags)
        else
          result:=sysutils.ExecuteProcess(Path,ComLine,Flags)
      end;


    function RequotedExecuteProcess(const Path: AnsiString; const ComLine: array of AnsiString; Flags: TExecuteFlags): Longint;
      var
        i : longint;
        st : string;
      begin
        if do_checkverbosity(V_Executable) then
          begin
            if high(ComLine)=0 then
              st:=''
            else
              st:=ComLine[1];
            for i:=2 to high(ComLine) do
              st:=st+' '+ComLine[i];
            do_comment(V_Executable,'Executing "'+Path+'" with command line "'+
              st+'"');
          end;
        result:=sysutils.ExecuteProcess(Path,ComLine,Flags);
      end;


    function Shell(const command:ansistring): longint;
      { This is already defined in the linux.ppu for linux, need for the *
        expansion under linux }
{$ifdef hasunix}
      begin
        do_comment(V_Executable,'Executing "'+Command+'" with fpSystem call');
        result := Unix.fpsystem(command);
      end;
{$else hasunix}
  {$ifdef hasamiga}
      begin
        do_comment(V_Executable,'Executing "'+Command+'" using RequotedExecuteProcess');
        result := RequotedExecuteProcess('',command);
      end;
  {$else hasamiga}
      var
        comspec : string;
      begin
        comspec:=GetEnvironmentVariable('COMSPEC');
        do_comment(V_Executable,'Executing "'+Command+'" using comspec "'
            +ComSpec+'"');
        result := RequotedExecuteProcess(comspec,' /C '+command);
      end;
   {$endif hasamiga}
{$endif hasunix}



{****************************************************************************
                           Init / Done
****************************************************************************}

    procedure InitFileUtils;
      begin
        CachedCurrentDir:='';
        DirCache:=TDirectoryCache.Create;
      end;


    procedure DoneFileUtils;
      begin
        DirCache.Free;
        DirCache := nil;
      end;

end.
