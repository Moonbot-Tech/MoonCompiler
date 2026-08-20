program dvl_reject_attribute_ctor_parameter;
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
    constructor Create; overload;
    constructor Create(const V: string); overload;
  end;

constructor MarkAttribute.Create;
begin
  inherited Create;
end;

constructor MarkAttribute.Create(const V: string);
begin
  inherited Create;
end;

procedure Touch([Mark] const V: Integer);
begin
end;

begin
  Touch(1);
  WriteLn('ok');
end.
