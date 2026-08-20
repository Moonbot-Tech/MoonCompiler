program dvl_reject_abstract_class_instantiated;
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
    procedure Touch; virtual; abstract;
  end;

var
  Held: TBase;
begin
  { a warning, not an error: the call would fail, the construction may not }
  Held := TBase.Create;
  Held.Free;
  WriteLn('done');
end.
