program finalization_output;
{$IFDEF MSWINDOWS}{$APPTYPE CONSOLE}{$ENDIF}
{$IFDEF FPC}{$mode delphi}{$H+}{$ENDIF}
{ What the finalization of a unit writes to the standard output reaches it
  when the output goes to a file or a pipe, as the gates run the program:
  Delphi 12.2 writes the standard files after the last unit is finalized.
  The verdict is written by the finalization of the unit. One source for
  Delphi 12.2 and MoonCompiler. }
uses
  finalization_output_unit;
begin
end.
