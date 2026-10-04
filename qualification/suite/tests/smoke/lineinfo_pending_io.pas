program lineinfo_pending_io;
{$IFDEF FPC}{$mode delphi}{$H+}{$ENDIF}
{ The line information of a backtrace (lnfodwrf, compiled with -gl) does
  not depend on an I/O error the program left pending: the routine and its
  line are found, and the error stays pending for the program. Before, the
  pending error made the open of the executable look failed, and that
  failure was remembered for the rest of the run. MoonCompiler only: the
  backtraces are the RTL's. }
uses
  SysUtils;

procedure First;
begin
end;

procedure Second;
begin
end;

var
  Missing: TextFile;
  S, Fails: string;
begin
  AssignFile(Missing, 'lineinfo_pending_io.no-such-file');
  {$I-}
  Reset(Missing);
  {$I+}
  S := BackTraceStrFunc(CodePointer(@First));
  If Pos(' line ', S) = 0 then
    Fails := Fails + ' pending[' + Trim(S) + ']';
  If IOResult <> 2 then
    Fails := Fails + ' pending-error-lost';
  S := BackTraceStrFunc(CodePointer(@Second));
  If Pos(' line ', S) = 0 then
    Fails := Fails + ' after[' + Trim(S) + ']';
  If Fails = '' then
    Writeln('LINEINFO_PENDING_IO_OK')
  else
    Writeln('LINEINFO_PENDING_IO_FAIL', Fails);
end.
