program dvl_reject_inherited_in_class_method;
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
  TBase = class
    class function Ask: Integer; virtual;
  end;
  TLeaf = class(TBase)
    class function Ask: Integer; override;
  end;

class function TBase.Ask: Integer;
begin
  Result := 1;
end;

class function TLeaf.Ask: Integer;
begin
  Result := inherited Ask + 1;
end;

begin
  WriteLn(TLeaf.Ask);
end.
