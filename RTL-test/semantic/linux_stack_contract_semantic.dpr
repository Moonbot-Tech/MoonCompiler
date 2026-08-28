program linux_stack_contract_semantic;

{ %TARGET=linux }

{$mode delphiunicode}{$H+}

uses
  mormot.core.fpcx64mm,
  cthreads,
  cwstring,
  fpmonitor,
  SysUtils,
  Classes,
  BaseUnix;

const
  ProductThreadStackSize = 1024 * 1024;

type
  { glibc x86-64 keeps pthread_attr_t opaque and defines it as 56 bytes.
    The probe needs only libc accessors; product code never inspects it. }
  TPthreadAttr = array[0..55] of Byte;
  TPthreadStartRoutine = function(Data: Pointer): Pointer; cdecl;

  TStackSnapshot = record
    Address: Pointer;
    Size: SizeUInt;
    GuardSize: SizeUInt;
  end;

function pthread_self: PtrUInt; cdecl; external 'c';
function pthread_getattr_np(Thread: PtrUInt; Attr: Pointer): LongInt; cdecl;
  external 'c';
function pthread_attr_getstack(Attr: Pointer; StackAddress: PPointer;
  StackSize: PSizeUInt): LongInt; cdecl; external 'c';
function pthread_attr_getguardsize(Attr: Pointer;
  GuardSize: PSizeUInt): LongInt; cdecl; external 'c';
function pthread_attr_destroy(Attr: Pointer): LongInt; cdecl; external 'c';
function pthread_create(Thread: PPtrUInt; Attr: Pointer;
  StartRoutine: TPthreadStartRoutine; Data: Pointer): LongInt; cdecl;
  external 'c';
function pthread_join(Thread: PtrUInt; ReturnValue: PPointer): LongInt; cdecl;
  external 'c';

type
  TProbeThread = class(TThread)
  protected
    procedure Execute; override;
  end;

var
  MainStack: TStackSnapshot;
  ClassStack: TStackSnapshot;
  BeginStack: TStackSnapshot;
  RawStack: TStackSnapshot;

procedure Check(const Condition: Boolean; const MessageText: string);
begin
  If not Condition then
    raise Exception.Create(MessageText);
end;

procedure CaptureStack(out Snapshot: TStackSnapshot);
var
  Attr: TPthreadAttr;
begin
  FillChar(Snapshot, SizeOf(Snapshot), 0);
  Check(pthread_getattr_np(pthread_self, @Attr) = 0,
    'pthread_getattr_np failed');
  try
    Check(pthread_attr_getstack(@Attr, @Snapshot.Address,
      @Snapshot.Size) = 0, 'pthread_attr_getstack failed');
    Check(pthread_attr_getguardsize(@Attr, @Snapshot.GuardSize) = 0,
      'pthread_attr_getguardsize failed');
  finally
    pthread_attr_destroy(@Attr);
  end;
end;

procedure TProbeThread.Execute;
begin
  CaptureStack(ClassStack);
end;

function BeginProbe(Data: Pointer): PtrInt;
begin
  CaptureStack(BeginStack);
  Result := 0;
end;

function RawProbe(Data: Pointer): Pointer; cdecl;
begin
  CaptureStack(RawStack);
  Result := nil;
end;

procedure PrintStack(const Name: string; const Snapshot: TStackSnapshot);
begin
  WriteLn(Name, ': size=', Snapshot.Size, ' guard=', Snapshot.GuardSize);
end;

var
  Limits: TRLimit;
  Worker: TProbeThread;
  ThreadHandle: TThreadID;
  ThreadId: TThreadID;
  RawThread: PtrUInt;
begin
  Check(FpGetRLimit(RLIMIT_STACK, @Limits) = 0, 'getrlimit failed');
  CaptureStack(MainStack);

  Worker := TProbeThread.Create(False);
  try
    Worker.WaitFor;
  finally
    Worker.Free;
  end;

  ThreadHandle := BeginThread(@BeginProbe, nil, ThreadId);
  Check(ThreadHandle <> TThreadID(0), 'BeginThread failed');
  Check(WaitForThreadTerminate(ThreadHandle, 5000) = 0,
    'BeginThread wait failed');
  CloseThread(ThreadHandle);

  Check(pthread_create(@RawThread, nil, @RawProbe, nil) = 0,
    'raw pthread_create failed');
  Check(pthread_join(RawThread, nil) = 0, 'raw pthread_join failed');

  Check(ClassStack.Size = ProductThreadStackSize,
    'TThread stack is not exactly 1 MiB');
  Check(BeginStack.Size = ProductThreadStackSize,
    'BeginThread stack is not exactly 1 MiB');
  Check(ClassStack.GuardSize > 0, 'TThread has no guard page');
  Check(BeginStack.GuardSize > 0, 'BeginThread has no guard page');
  Check(MainStack.Size > 0, 'main stack size is empty');
  Check(RawStack.Size > 0, 'raw pthread stack size is empty');

  WriteLn('rlimit: current=', Limits.rlim_cur, ' max=', Limits.rlim_max);
  PrintStack('main', MainStack);
  PrintStack('TThread', ClassStack);
  PrintStack('BeginThread', BeginStack);
  PrintStack('raw-pthread', RawStack);
  WriteLn('LINUX_STACK_CONTRACT_OK');
end.
