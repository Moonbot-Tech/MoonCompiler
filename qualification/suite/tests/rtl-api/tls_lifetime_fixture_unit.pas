unit tls_lifetime_fixture_unit;
{$mode objfpc}
interface
type
  TObserver = procedure(Event: LongInt); cdecl;
procedure Configure(Observer: TObserver); cdecl;
function Touch: LongInt; cdecl;
procedure Detach; cdecl;
implementation
var
  Notify: TObserver;
  OriginalManager: TUnicodeStringManager;
  Calls: LongInt;
threadvar
  Visits: LongInt;

procedure FinishThread;
begin
  if Assigned(OriginalManager.ThreadFiniProc) then
    OriginalManager.ThreadFiniProc;
  Notify(1);
end;

procedure Configure(Observer: TObserver); cdecl;
var
  Manager: TUnicodeStringManager;
begin
  Notify:=Observer;
  GetUnicodeStringManager(OriginalManager);
  Manager:=OriginalManager;
  Manager.ThreadFiniProc:=@FinishThread;
  SetUnicodeStringManager(Manager);
end;

function Touch: LongInt; cdecl;
begin
  Inc(Visits);
  Inc(Calls);
  Result:=Calls*1000+Visits;
end;

procedure Detach; cdecl;
begin
  DoneThread;
end;

finalization
  if Assigned(Notify) then
    begin
      SetUnicodeStringManager(OriginalManager);
      Notify(2);
    end;
end.
