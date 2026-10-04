program thread_waitfor_twice_semantic;

{$mode delphi}{$H+}

{ TThread.WaitFor called again on a thread that was already waited for.
  Delphi answers at once; the Unix RTL used to call pthread_join a second
  time, which - with the pthread id already reused by a thread created in
  between, as glibc does - waited for that stranger instead.  Oracle: the
  second WaitFor returns the same value in far less time than the stranger
  needs to finish. }

uses
  {$ifdef UNIX}cthreads,{$endif}
  SysUtils, Classes;

type
  TQuick = class(TThread)
  protected
    procedure Execute; override;
  end;

  TSlow = class(TThread)
  protected
    procedure Execute; override;
  end;

procedure TQuick.Execute;
begin
  ReturnValue := 42;
end;

procedure TSlow.Execute;
begin
  Sleep(1500);
  ReturnValue := 7;
end;

var
  Failures: Integer;

procedure Check(Cond: Boolean; const Msg: string);
begin
  If not Cond then begin
    Inc(Failures);
    WriteLn('FAIL ', Msg);
  end;
end;

var
  Quick: TQuick;
  Slow: TSlow;
  First, Second: Integer;
  Started: Int64;
  Elapsed: Int64;
  Iteration: Integer;
begin
  Failures := 0;
  { several rounds: the id reuse that makes the old code hang is likely,
    not guaranteed, on any one round }
  for Iteration := 1 to 3 do begin
    Quick := TQuick.Create(True);
    Quick.FreeOnTerminate := False;
    Quick.Start;
    First := Quick.WaitFor;
    Check(First = 42, 'first WaitFor returns the thread result');
    Check(Quick.Finished, 'Finished after WaitFor');
    Slow := TSlow.Create(True);
    Slow.FreeOnTerminate := False;
    Slow.Start;
    Started := GetTickCount64;
    Second := Quick.WaitFor;
    Elapsed := Abs(GetTickCount64 - Started);
    Check(Second = First, 'second WaitFor returns the same result: ' + IntToStr(Second));
    Check(Elapsed < 500, 'second WaitFor does not wait for a thread created since: ' + IntToStr(Elapsed) + ' ms');
    Check(Slow.WaitFor = 7, 'the other thread is unaffected');
    Check(Slow.WaitFor = 7, 'and answers again');
    FreeAndNil(Quick);
    FreeAndNil(Slow);
  end;
  If Failures <> 0 then
    Halt(1);
  WriteLn('THREAD_WAITFOR_TWICE_PASS');
end.
