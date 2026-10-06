{ Linux x86-64 public C ABI declarations. See doc/PLATFORM_API.md. }
unit Posix.SysStat;
{$mode delphi}{$H+}{$packrecords c}
{$if not (defined(LINUX) and defined(CPUX86_64))}{$fatal This binding requires Linux x86-64}{$endif}
interface
uses ctypes, BaseUnix, Posix.SysTypes, Posix.Time;
type
  _stat = record
    st_dev: dev_t;
    st_ino: ino_t;
    st_nlink: nlink_t;
    st_mode: mode_t;
    st_uid: uid_t;
    st_gid: gid_t;
    __pad0: cint;
    st_rdev: dev_t;
    st_size: off_t;
    st_blksize, st_blocks: clong;
    st_atim, st_mtim, st_ctim: timespec;
    __reserved: array[0..2] of clong;
  end;
  stat_t = _stat;
  Pstat = ^_stat;
const
  S_IFMT = BaseUnix.S_IFMT;
  S_IFREG = BaseUnix.S_IFREG;
  S_IFDIR = BaseUnix.S_IFDIR;
  S_IFLNK = BaseUnix.S_IFLNK;
  S_IRUSR = BaseUnix.S_IRUSR;
  S_IWUSR = BaseUnix.S_IWUSR;
  S_IXUSR = BaseUnix.S_IXUSR;
  S_IRGRP = BaseUnix.S_IRGRP;
  S_IWGRP = BaseUnix.S_IWGRP;
  S_IXGRP = BaseUnix.S_IXGRP;
  S_IROTH = BaseUnix.S_IROTH;
  S_IWOTH = BaseUnix.S_IWOTH;
  S_IXOTH = BaseUnix.S_IXOTH;
function stat(Path: PAnsiChar; Buffer: Pstat): cint; cdecl; external 'c';
function fstat(FD: cint; Buffer: Pstat): cint; cdecl; external 'c';
function lstat(Path: PAnsiChar; Buffer: Pstat): cint; cdecl; external 'c';
function mkdir(Path: PAnsiChar; Mode: mode_t): cint; cdecl; external 'c';
function chmod(Path: PAnsiChar; Mode: mode_t): cint; cdecl; external 'c';
function fchmod(FD: cint; Mode: mode_t): cint; cdecl; external 'c';
function umask(Mode: mode_t): mode_t; cdecl; external 'c';
implementation

end.
