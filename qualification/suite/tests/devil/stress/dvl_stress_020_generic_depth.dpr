program dvl_stress_020_generic_depth;
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
  TBox<T> = record
    Value: T;
  end;

var
  B: TBox<TBox<TBox<TBox<TBox<TBox<Integer>>>>>>;
begin
  WriteLn(SizeOf(B));
end.
