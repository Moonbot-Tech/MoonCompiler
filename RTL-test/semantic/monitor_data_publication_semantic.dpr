program monitor_data_publication_semantic;

{$mode delphiunicode}{$H+}

uses
  {$ifdef UNIX}cthreads,{$endif}
  SysUtils, Classes, SyncObjs;

const ObjectCount = 128;
type
  TWorker = class(TThread)
  protected
    procedure Execute; override;
  end;
var
  Objects: array[0..ObjectCount - 1] of TObject;
  Counters: array[0..ObjectCount - 1] of Integer;
  StartEvent: TEvent;
  Previous, Wrapped: TMonitorManager;
  Enters, Exits: Integer;

procedure WrappedEnter(const Obj: TObject);
begin
  Inc(Enters);
  Previous.DoEnter(Obj);
end;

procedure WrappedExit(const Obj: TObject);
begin
  Inc(Exits);
  Previous.DoExit(Obj);
end;

procedure TWorker.Execute;
var I, J: Integer;
begin
  if StartEvent.WaitFor(5000) <> wrSignaled then
    raise Exception.Create('start timeout');
  for I := 0 to High(Objects) do
    for J := 1 to 100 do
    begin
      TMonitor.Enter(Objects[I]);
      Inc(Counters[I]);
      TMonitor.Exit(Objects[I]);
    end;
end;

var
  Workers: array[0..3] of TWorker;
  I: Integer;
  Obj: TObject;
begin
  Previous := GetMonitorManager;
  Wrapped := Previous;
  Wrapped.DoEnter := WrappedEnter;
  Wrapped.DoExit := WrappedExit;
  SetMonitorManager(Wrapped);
  Obj := TObject.Create;
  try
    TMonitor.Enter(Obj);
    TMonitor.Enter(Obj);
    TMonitor.Exit(Obj);
    TMonitor.Exit(Obj);
    if (Enters <> 2) or (Exits <> 2) then Halt(1);
  finally
    Obj.Free;
    SetMonitorManager(Previous);
  end;
  StartEvent := TEvent.Create(nil, True, False, '');
  for I := 0 to High(Objects) do Objects[I] := TObject.Create;
  for I := 0 to High(Workers) do Workers[I] := TWorker.Create(False);
  StartEvent.SetEvent;
  for I := 0 to High(Workers) do
  begin
    Workers[I].WaitFor;
    if Workers[I].FatalException <> nil then Halt(2);
    Workers[I].Free;
  end;
  for I := 0 to High(Objects) do
  begin
    if Counters[I] <> 400 then Halt(3);
    Objects[I].Free;
  end;
  StartEvent.Free;
  WriteLn('MONITOR_DATA_PUBLICATION_OK');
end.
