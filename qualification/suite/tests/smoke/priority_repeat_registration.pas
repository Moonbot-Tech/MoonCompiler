program priority_repeat_registration;
{$mode delphi}
uses cthreads, Classes, SysUtils;

{ The registry has no public registration API. Calling the actual RTL entry
  isolates its repeat path without depending on pthread TLS destructor order. }
procedure RegisterCurrent; external name 'CTHREADS_$$_REGISTERPRIORITYTHREAD';
procedure BeginCount; cdecl; external name 'begin_count';
function EndCount: Cardinal; cdecl; external name 'end_count';
function LibcAlloc(Size: SizeUInt): Pointer; cdecl; external 'c' name 'malloc';
procedure LibcFree(P: Pointer); cdecl; external 'c' name 'free';

function CountRegistration: Cardinal;
begin
  BeginCount;
  RegisterCurrent;
  RegisterCurrent;
  Result:=EndCount;
end;

type
  TWorker=class(TThread)
    AllocationCount: Cardinal;
    procedure Execute; override;
  end;

procedure TWorker.Execute;
begin
  AllocationCount:=CountRegistration;
end;

var Worker: TWorker; P: Pointer; Control: Cardinal;
begin
  BeginCount;
  P:=LibcAlloc(17);
  Control:=EndCount;
  LibcFree(P);
  if Control<>1 then Halt(1);
  Worker:=TWorker.Create(True);
  try
    Worker.Start;
    Worker.WaitFor;
    if Worker.AllocationCount<>0 then Halt(2);
    if CountRegistration<>0 then Halt(3);
  finally Worker.Free end;
  WriteLn('PRIORITY_REGISTRATION_NO_ALLOC_OK');
end.
