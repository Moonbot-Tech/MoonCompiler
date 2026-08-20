program dvl_stress_010_inline_managed_finally;
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
var
  Trail: AnsiString;

procedure Add0(C: AnsiChar);
begin
  Trail := Trail + C;
end;

procedure Add1(C: AnsiChar);
begin
  Trail := Trail + C;
end;

procedure Add2(C: AnsiChar);
begin
  Trail := Trail + C;
end;

procedure Frame;
begin
  try
    WriteLn('body');
  finally
    Add0('a');
    Add1('b');
    Add2('c');
  end;
end;

begin
  Frame;
  WriteLn(Length(Trail));
end.
