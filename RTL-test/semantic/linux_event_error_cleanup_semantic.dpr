program linux_event_error_cleanup_semantic;
{ %TARGET=linux }
{$mode delphiunicode}{$H+}
uses mormot.core.fpcx64mm, cthreads, cwstring, System.SysUtils, Posix.Pthread;
type
  { Linux x86-64 cthreads event descriptor. This test deliberately injects an
    invalid clock ID after normal creation; the pthread records come from the
    independently C-ABI-tested platform bindings, not invented byte offsets. }
  TEventState = record
    Cond: pthread_cond_t;
    Attr: pthread_condattr_t;
    Clock: LongInt;
    Mutex: pthread_mutex_t;
    Waiters: LongInt;
    IsSet,ManualReset,Destroying: Boolean;
  end;
  PEventState=^TEventState;
var E: PEventState; SavedClock: LongInt; Locked: Integer;
procedure Check(OK: Boolean; const Name: string);
begin
  if not OK then raise Exception.Create('EVENT_ERROR_CLEANUP: '+Name);
end;
begin
  E:=PEventState(BasicEventCreate(nil,False,False,''));
  Check(E<>nil,'creation');
  SavedClock:=E^.Clock;
  Check((E^.Waiters=0) and not E^.IsSet,'descriptor layout control');
  E^.Clock:=High(LongInt);
  Check(BasicEventWaitFor(1,E)=3,'injected clock failure');
  Check(E^.Waiters=0,'failed wait unregisters');
  Locked:=pthread_mutex_trylock(@E^.Mutex);
  Check(Locked=0,'failed wait unlocks');
  pthread_mutex_unlock(@E^.Mutex);
  E^.Clock:=SavedClock;
  BasicEventSetEvent(E);
  Check(BasicEventWaitFor(1,E)=0,'event reusable after failure');
  BasicEventDestroy(E);
  WriteLn('LINUX_EVENT_ERROR_CLEANUP_PASS');
end.
