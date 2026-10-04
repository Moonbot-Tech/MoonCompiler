program unhandled_exit_code;
{$IFDEF MSWINDOWS}{$APPTYPE CONSOLE}{$ENDIF}
{$IFDEF FPC}{$mode delphi}{$H+}{$ENDIF}
{ An exception that nobody handles ends the program with exit code 1 and
  its message on the standard error, as with Delphi 12.2's SysUtils: raised
  in the main block (mode "main") or in a thread of BeginThread (mode
  "thread"). Mode "pending" raises in the main block while an I/O error is
  left pending: the report is still the exception's own and the code 1
  (Delphi 12.2 itself loses both there, so this mode is MoonCompiler's
  only). The gates expect exit code 1 and the marker of the mode in the
  output. One source for Delphi 12.2 and MoonCompiler. }
uses
  SysUtils;

var
  Missing: TextFile;
  Id: TThreadID;

function Worker(P: Pointer): Integer;
begin
  raise Exception.Create('UNHANDLED_EXIT_CODE_THREAD');
end;

begin
  If ParamStr(1) = 'main' then
    raise Exception.Create('UNHANDLED_EXIT_CODE_MAIN')
  else If ParamStr(1) = 'pending' then begin
    AssignFile(Missing, 'unhandled_exit_code.no-such-file');
    {$I-}
    Reset(Missing);
    {$I+}
    raise Exception.Create('UNHANDLED_EXIT_CODE_PENDING');
  end else If ParamStr(1) = 'thread' then begin
    { an explicit stack size: with 0, the default in Delphi, BeginThread on
      Linux creates no thread (rtl/unix/cthreads.pp, a defect of its own) }
    BeginThread(nil, 1 shl 20, @Worker, nil, 0, Id);
    Sleep(10000);
  end;
  Writeln('UNHANDLED_EXIT_CODE_NO_MODE');
end.
