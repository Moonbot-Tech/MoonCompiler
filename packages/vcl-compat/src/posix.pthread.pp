{ Linux x86-64 public C ABI declarations. See doc/PLATFORM_API.md. }
unit Posix.Pthread;
{$mode delphi}{$H+}{$packrecords c}
{$if not (defined(LINUX) and defined(CPUX86_64))}{$fatal This binding requires Linux x86-64}{$endif}
interface
uses ctypes, Posix.SysTypes, Posix.Time;
type
  pthread_t = Posix.SysTypes.pthread_t;
  Ppthread_t = ^pthread_t;
  pthread_attr_t = record Storage: array[0..6] of culong; end;
  pthread_mutex_t = record Storage: array[0..4] of culong; end;
  pthread_cond_t = record Storage: array[0..5] of cuint64; end;
  pthread_mutexattr_t = record Storage: cint; end;
  pthread_condattr_t = record Storage: cint; end;
  Ppthread_attr_t = ^pthread_attr_t;
  Ppthread_mutex_t = ^pthread_mutex_t;
  Ppthread_cond_t = ^pthread_cond_t;
  Ppthread_mutexattr_t = ^pthread_mutexattr_t;
  Ppthread_condattr_t = ^pthread_condattr_t;
  TThreadStart = function(Context: Pointer): Pointer; cdecl;
const
  PTHREAD_MUTEX_NORMAL = 0;
  PTHREAD_MUTEX_RECURSIVE = 1;
  PTHREAD_MUTEX_ERRORCHECK = 2;
function pthread_self: pthread_t; cdecl; external 'c';
function pthread_equal(Left, Right: pthread_t): cint; cdecl; external 'c';
function pthread_create(Thread: Ppthread_t; Attributes: Ppthread_attr_t; Start: TThreadStart; Context: Pointer): cint; cdecl; external 'c';
function pthread_join(Thread: pthread_t; Result: PPointer): cint; cdecl; external 'c';
function pthread_detach(Thread: pthread_t): cint; cdecl; external 'c';
function pthread_attr_init(Attributes: Ppthread_attr_t): cint; cdecl; external 'c';
function pthread_attr_destroy(Attributes: Ppthread_attr_t): cint; cdecl; external 'c';
function pthread_attr_setstacksize(Attributes: Ppthread_attr_t; Size: size_t): cint; cdecl; external 'c';
function pthread_mutex_init(Mutex: Ppthread_mutex_t; Attributes: Ppthread_mutexattr_t): cint; cdecl; external 'c';
function pthread_mutex_destroy(Mutex: Ppthread_mutex_t): cint; cdecl; external 'c';
function pthread_mutex_lock(Mutex: Ppthread_mutex_t): cint; cdecl; external 'c';
function pthread_mutex_trylock(Mutex: Ppthread_mutex_t): cint; cdecl; external 'c';
function pthread_mutex_unlock(Mutex: Ppthread_mutex_t): cint; cdecl; external 'c';
function pthread_mutexattr_init(Attributes: Ppthread_mutexattr_t): cint; cdecl; external 'c';
function pthread_mutexattr_settype(Attributes: Ppthread_mutexattr_t; Kind: cint): cint; cdecl; external 'c';
function pthread_mutexattr_destroy(Attributes: Ppthread_mutexattr_t): cint; cdecl; external 'c';
function pthread_cond_init(Cond: Ppthread_cond_t; Attributes: Ppthread_condattr_t): cint; cdecl; external 'c';
function pthread_cond_destroy(Cond: Ppthread_cond_t): cint; cdecl; external 'c';
function pthread_cond_wait(Cond: Ppthread_cond_t; Mutex: Ppthread_mutex_t): cint; cdecl; external 'c';
function pthread_cond_timedwait(Cond: Ppthread_cond_t; Mutex: Ppthread_mutex_t; Deadline: Ptimespec): cint; cdecl; external 'c';
function pthread_cond_signal(Cond: Ppthread_cond_t): cint; cdecl; external 'c';
function pthread_cond_broadcast(Cond: Ppthread_cond_t): cint; cdecl; external 'c';
implementation

end.
