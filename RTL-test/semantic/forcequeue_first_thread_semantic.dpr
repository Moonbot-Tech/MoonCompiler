program forcequeue_first_thread_semantic;
{$APPTYPE CONSOLE}
uses
  {$ifdef UNIX}cthreads,{$endif}
  System.SysUtils, System.Classes;
type
  TReceiver = class
    procedure Receive;
  end;
var
  Receiver: TReceiver;
  Calls: Integer;
procedure TReceiver.Receive;
begin
  If GetCurrentThreadID <> MainThreadID then
    raise Exception.Create('Wrong delivery thread');
  Inc(Calls);
end;
begin
  Receiver := TReceiver.Create;
  try
    TThread.ForceQueue(nil, Receiver.Receive);
    TThread.ForceQueue(nil, procedure begin Inc(Calls, 10); end);
    If Calls <> 0 then
      raise Exception.Create('ForceQueue ran before pumping');
    TThread.Queue(nil, Receiver.Receive);
    If Calls <> 1 then
      raise Exception.Create('Queue must execute on main thread immediately');
    If not CheckSynchronize or (Calls <> 12) then
      raise Exception.Create('Queued work was not drained');
    TThread.ForceQueue(nil, Receiver.Receive);
    TThread.RemoveQueuedEvents(nil, Receiver.Receive);
    CheckSynchronize;
    If Calls <> 12 then
      raise Exception.Create('Removed work executed');
  finally
    Receiver.Free;
  end;
  WriteLn('FORCEQUEUE_FIRST_THREAD_PASS');
end.
