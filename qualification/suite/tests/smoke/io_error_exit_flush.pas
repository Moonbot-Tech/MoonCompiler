program io_error_exit_flush;
{$IFDEF MSWINDOWS}{$APPTYPE CONSOLE}{$ENDIF}
{$IFDEF FPC}{$mode delphi}{$H+}{$ENDIF}
{ An I/O error left pending at the exit does not keep the standard files
  from being written: the finalization of the unit writes the verdict and
  then leaves an error pending (Reset of a file that does not exist, with
  I/O checks off), and the verdict reaches the output in a file, as in
  Delphi 12.2, whose System closes the standard files after the last unit
  is finalized. On FPC, force buffering even when Output is a pipe, so the
  final exit flush is the operation that must write the verdict. One source
  for Delphi 12.2 and MoonCompiler. }
uses
  io_error_exit_flush_unit;
begin
  {$IFDEF FPC} SetTextAutoFlush(Output, False); {$ENDIF}
end.
