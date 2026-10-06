{ Linux x86-64 public C ABI declarations. See doc/PLATFORM_API.md. }
unit Posix.SysMman;
{$mode delphi}{$H+}{$packrecords c}
{$if not (defined(LINUX) and defined(CPUX86_64))}{$fatal This binding requires Linux x86-64}{$endif}
interface
uses ctypes, BaseUnix, Posix.SysTypes;
const
  PROT_NONE = BaseUnix.PROT_NONE;
  PROT_READ = BaseUnix.PROT_READ;
  PROT_WRITE = BaseUnix.PROT_WRITE;
  PROT_EXEC = BaseUnix.PROT_EXEC;
  MAP_SHARED = BaseUnix.MAP_SHARED;
  MAP_PRIVATE = BaseUnix.MAP_PRIVATE;
  MAP_FIXED = BaseUnix.MAP_FIXED;
  MAP_ANONYMOUS = BaseUnix.MAP_ANONYMOUS;
  MS_ASYNC = 1;
  MS_SYNC = 4;
  MS_INVALIDATE = 2;
  MAP_ANON = MAP_ANONYMOUS;
  MAP_FAILED = Pointer(-1);
function mmap(Address: Pointer; Length: size_t; Protection, Flags, FD: cint; Offset: off_t): Pointer; cdecl; external 'c';
function munmap(Address: Pointer; Length: size_t): cint; cdecl; external 'c';
function mprotect(Address: Pointer; Length: size_t; Protection: cint): cint; cdecl; external 'c';
function msync(Address: Pointer; Length: size_t; Flags: cint): cint; cdecl; external 'c';
function mlock(Address: Pointer; Length: size_t): cint; cdecl; external 'c';
function munlock(Address: Pointer; Length: size_t): cint; cdecl; external 'c';
function shm_open(Name: PAnsiChar; Flags: cint; Mode: mode_t): cint; cdecl; external 'c';
function shm_unlink(Name: PAnsiChar): cint; cdecl; external 'c';
implementation

end.
