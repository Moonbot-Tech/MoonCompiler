program method_value_implicit_finalization;
{$IFDEF MSWINDOWS}{$APPTYPE CONSOLE}{$ENDIF}
{$IFDEF FPC}{$mode delphi}{$H+}{$ENDIF}
uses method_value_implicit_finalization_unit;
begin
  If Last <> 3 then
    Halt(1);
  Write('METHOD_VALUE_');
end.
