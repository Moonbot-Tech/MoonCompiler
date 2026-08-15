program rtlobjpas_core_deferred;

{$mode objfpc}{$H+}
uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  cwstring,
  {$endif UNIX}
  consoletestrunner,
  tests.rtti in 'packages/rtl-objpas/tests/tests.rtti.pas',
  tests.rtti.util in 'packages/rtl-objpas/tests/tests.rtti.util.pas',
  tests.rtti.types in 'packages/rtl-objpas/tests/tests.rtti.types.pas',
  tests.rtti.attrtypes in 'packages/rtl-objpas/tests/tests.rtti.attrtypes.pas',
  utcfpmonitor in 'packages/rtl-objpas/tests/utcfpmonitor.pas',
  tests.rtti.attrtypes2 in
    'packages/rtl-objpas/tests/tests.rtti.attrtypes2.pp';

var
  Application: TTestRunner;

begin
  DefaultFormat := fPlain;
  DefaultRunAllTests := True;
  Application := TTestRunner.Create(nil);
  try
    Application.Initialize;
    Application.Title := 'Moon RTL-ObjPas deferred RTTI differential';
    Application.Run;
  finally
    Application.Free;
  end;
  if ExitCode = 0 then
    WriteLn('RTLOBJPAS_CORE_DEFERRED_PASS');
end.
