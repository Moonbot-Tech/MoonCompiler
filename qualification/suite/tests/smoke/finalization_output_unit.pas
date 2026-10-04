unit finalization_output_unit;
{$IFDEF FPC}{$mode delphi}{$H+}{$ENDIF}
{ The finalization of this unit writes the verdict of
  tests/smoke/finalization_output.pas. }

interface

implementation

initialization

finalization
  WriteLn('FINALIZATION_OUTPUT_OK');
end.
