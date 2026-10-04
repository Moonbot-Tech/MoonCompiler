program thread_completion_wakeup_semantic;

{$mode delphi}{$H+}

uses
  {$ifdef UNIX}cthreads,{$endif}
  SysUtils, Classes;

type
  TWorker = class(TThread)
  private
    procedure OnMain;
    procedure TerminatedOnMain(Sender: TObject);
  protected
    procedure Execute; override;
  public
    Callbacks: Integer;
    constructor Create;
  end;

constructor TWorker.Create;
begin
  inherited Create(True);
  OnTerminate := TerminatedOnMain;
end;

procedure TWorker.OnMain;
begin
  If GetCurrentThreadID <> MainThreadID then
    raise Exception.Create('Synchronize callback left the main thread');
  Inc(Callbacks);
end;

procedure TWorker.TerminatedOnMain(Sender: TObject);
begin
  OnMain;
end;

procedure TWorker.Execute;
begin
  Synchronize(OnMain);
  ReturnValue := 42;
end;

var
  Worker: TWorker;
  I: Integer;
begin
  for I := 1 to 32 do begin
    Worker := TWorker.Create;
    try
      Worker.Start;
      If (Worker.WaitFor <> 42) or not Worker.Finished or
         (Worker.Callbacks <> 2) or (Worker.FatalException <> nil) then
        raise Exception.Create('WaitFor lost completion or a synchronized callback');
      If Worker.WaitFor <> 42 then
        raise Exception.Create('repeated WaitFor changed the return value');
    finally
      Worker.Free;
    end;
  end;
  WriteLn('THREAD_COMPLETION_WAKEUP_PASS');
end.
