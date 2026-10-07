{ Linux x86-64 public C ABI declarations. See doc/PLATFORM_API.md. }
unit Posix.Stdio;
{$mode delphi}{$H+}
{$if not (defined(LINUX) and defined(CPUX86_64))}{$fatal This binding requires Linux x86-64}{$endif}
interface
uses ctypes;

{ Delphi's Pascal name keeps System.Rename available to text/typed files. }
function __rename(OldPath, NewPath: PAnsiChar): cint; cdecl; external 'c' name 'rename';
function remove(Path: PAnsiChar): cint; cdecl; external 'c';
procedure perror(MessageText: PAnsiChar); cdecl; external 'c';

implementation
end.
