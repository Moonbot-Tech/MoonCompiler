program attr;
{$ifdef FPC}{$mode delphiunicode}{$H+}{$modeswitch INLINEVARS}{$endif}
{$APPTYPE CONSOLE}
uses
{$ifdef FPC}
  mormot.core.fpcx64mm,
{$endif}
  SysUtils;

type
  MarkAttribute = class(TCustomAttribute)
  end;

begin
  var [Mark] Slot: Integer;
  Slot := 1;
  WriteLn(Slot);
end.
