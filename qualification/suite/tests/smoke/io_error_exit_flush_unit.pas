unit io_error_exit_flush_unit;
{$IFDEF FPC}{$mode delphi}{$H+}{$ENDIF}
{ The finalization of this unit writes the verdict of
  tests/smoke/io_error_exit_flush.pas and leaves an I/O error pending. }

interface

implementation

var
  Missing: TextFile;

initialization

finalization
  WriteLn('IO_ERROR_EXIT_FLUSH_OK');
  AssignFile(Missing, 'io_error_exit_flush.no-such-file');
  {$I-}
  Reset(Missing);
  {$I+}
end.
