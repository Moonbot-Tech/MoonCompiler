program marker_directive;

{ The reverse direction: a Delphi-mode program using an unleashed unit. }
{$mode delphi}

uses
  unleashed_unit;

begin
  WriteLn('unit=', UnitMode);
{$ifdef FPC_UNLEASHED}
  WriteLn('program=unleashed');
{$endif}
{$ifdef FPC_DELPHI}
  WriteLn('program=delphi');
{$endif}
end.
