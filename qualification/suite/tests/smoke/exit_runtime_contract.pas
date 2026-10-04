program exit_runtime_contract;
{$IFDEF FPC}{$mode delphi}{$ENDIF}
{$IFDEF MSWINDOWS}{$APPTYPE CONSOLE}{$ENDIF}
{$IFDEF UNIX}uses cthreads;{$ENDIF}
{$IFDEF MSWINDOWS}
procedure Delay(Milliseconds: LongWord); stdcall; external 'kernel32.dll' name 'Sleep';
{$ELSE}
procedure Delay(Microseconds: LongWord); cdecl; external 'c' name 'usleep';
{$ENDIF}
var
  Id: TThreadID;
  Missing: File;

procedure OnExit;
var
  Code: Integer;
begin
  ExitProc := nil;
  Code := IOResult;
  WriteLn('PENDING_IO=', Code);
  If Code <> 2 then Halt(92);
end;

function Worker(P: Pointer): Integer;
begin
  Write('WORKER_BUFFER');
  Halt(0);
end;

begin
  If ParamStr(1) = 'pending' then begin
    ExitProc := @OnExit;
    AssignFile(Missing, 'exit_runtime_contract.missing');
    {$I-}Reset(Missing, 1);{$I+}
  end else If ParamStr(1) = 'runerror' then
    RunError(77)
  {$IFDEF FPC}
  else If ParamStr(1) = 'runerror-stderr' then begin
    WriteErrorsToStdErr := True;
    RunError(77);
  end
  {$ENDIF}
  else If ParamStr(1) = 'thread' then begin
    Write('MAIN_BUFFER');
    If BeginThread(nil, 1 shl 20, @Worker, nil, 0, Id) = 0 then Halt(93);
    while True do Delay(1000);
  end else
    Write('MAIN_BUFFER');
end.
