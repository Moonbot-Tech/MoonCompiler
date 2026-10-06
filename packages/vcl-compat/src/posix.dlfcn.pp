{ Linux x86-64 public C ABI declarations. See doc/PLATFORM_API.md. }
unit Posix.Dlfcn;
{$mode delphi}{$H+}{$packrecords c}
{$if not (defined(LINUX) and defined(CPUX86_64))}{$fatal This binding requires Linux x86-64}{$endif}
interface
uses ctypes;
const
  RTLD_LAZY = 1;
  RTLD_NOW = 2;
  RTLD_NOLOAD = 4;
  RTLD_GLOBAL = $100;
  RTLD_LOCAL = 0;
  RTLD_NODELETE = $1000;
  RTLD_DEFAULT = Pointer(0);
  RTLD_NEXT = Pointer(-1);
function dlopen(Name: PAnsiChar; Flags: cint): Pointer; cdecl; external 'c';
function dlsym(Handle: Pointer; Name: PAnsiChar): Pointer; cdecl; external 'c';
function dlclose(Handle: Pointer): cint; cdecl; external 'c';
function dlerror: PAnsiChar; cdecl; external 'c';
implementation

end.
