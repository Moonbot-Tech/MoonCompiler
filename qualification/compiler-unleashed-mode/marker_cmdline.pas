program marker_cmdline;

{ No $MODE directive: the mode comes from -Munleashed on the command line.
  The unit compiled first switches to Delphi mode for itself only. }

uses
  delphi_unit;

begin
  WriteLn('unit=', UnitMode);
{$ifdef FPC_UNLEASHED}
  WriteLn('program=unleashed');
{$endif}
{$ifdef FPC_DELPHI}
  WriteLn('program=delphi');
{$endif}
{$ifdef FPC_OBJFPC}
  WriteLn('program=objfpc');
{$endif}
end.
