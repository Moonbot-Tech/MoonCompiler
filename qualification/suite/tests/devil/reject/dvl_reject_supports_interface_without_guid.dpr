program dvl_reject_supports_interface_without_guid;
{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch anonymousfunctions}
  {$modeswitch functionreferences}
  {$modeswitch INLINEVARS}
{$endif}
{$APPTYPE CONSOLE}
{$Q-}{$R-}
uses
{$ifdef FPC}
  mormot.core.fpcx64mm,
  {$ifdef UNIX}cthreads,{$endif}
{$endif}
  SysUtils;
type
  IPlain = interface
    procedure Touch;
  end;
  TThing = class(TInterfacedObject, IPlain)
    procedure Touch;
  end;

procedure TThing.Touch;
begin
end;

var
  Held: IPlain;
begin
  WriteLn(Supports(TThing.Create, IPlain, Held));
end.
