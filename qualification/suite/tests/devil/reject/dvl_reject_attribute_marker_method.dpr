program dvl_reject_attribute_marker_method;
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
  MarkAttribute = class(TCustomAttribute)
  end;

type
  TBox = class
  public
    [Mark]
    procedure Touch;
  end;

procedure TBox.Touch;
begin
end;

begin
  WriteLn('ok');
end.
