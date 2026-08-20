program dvl_reject_attribute_on_class_var;
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
  public
    Tag: Integer;
    constructor Create(ATag: Integer);
  end;

constructor MarkAttribute.Create(ATag: Integer);
begin
  inherited Create;
  Tag := ATag;
end;

type
  TBox = class
  public
    [Mark(1)]
    class var Shared: Integer;
  end;

begin
  TBox.Shared := 7;
  WriteLn(TBox.Shared);
end.
