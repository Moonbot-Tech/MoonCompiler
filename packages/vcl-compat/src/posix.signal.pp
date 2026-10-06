{ Linux x86-64 public C ABI declarations. See doc/PLATFORM_API.md. }
unit Posix.Signal;
{$mode delphi}{$H+}{$packrecords c}
{$if not (defined(LINUX) and defined(CPUX86_64))}{$fatal This binding requires Linux x86-64}{$endif}
interface
uses ctypes, BaseUnix, Posix.SysTypes;
type
  sigset_t = record Bits: array[0..15] of culong; end;
  Psigset_t = ^sigset_t;
  TSignalHandler = procedure(Signal: cint); cdecl;
  sigaction_t = record
    sa_handler: TSignalHandler;
    sa_mask: sigset_t;
    sa_flags: cint;
    sa_restorer: Pointer;
  end;
  Psigaction_t = ^sigaction_t;
const
  SIG_BLOCK = 0;
  SIG_UNBLOCK = 1;
  SIG_SETMASK = 2;
  SA_RESTART = $10000000;
  SIGINT = BaseUnix.SIGINT;
  SIGTERM = BaseUnix.SIGTERM;
  SIGKILL = BaseUnix.SIGKILL;
  SIGPIPE = BaseUnix.SIGPIPE;
  SIGUSR1 = BaseUnix.SIGUSR1;
  SIGUSR2 = BaseUnix.SIGUSR2;
  SIGHUP = BaseUnix.SIGHUP;
  SIGCHLD = BaseUnix.SIGCHLD;
function sigemptyset(Set_: Psigset_t): cint; cdecl; external 'c';
function sigfillset(Set_: Psigset_t): cint; cdecl; external 'c';
function sigaddset(Set_: Psigset_t; Signal: cint): cint; cdecl; external 'c';
function sigdelset(Set_: Psigset_t; Signal: cint): cint; cdecl; external 'c';
function sigismember(Set_: Psigset_t; Signal: cint): cint; cdecl; external 'c';
function sigaction(Signal: cint; Action, OldAction: Psigaction_t): cint; cdecl; external 'c';
function pthread_sigmask(How: cint; NewSet, OldSet: Psigset_t): cint; cdecl; external 'c';
function sigpending(Set_: Psigset_t): cint; cdecl; external 'c';
function kill(PID: pid_t; Signal: cint): cint; cdecl; external 'c';
implementation

end.
