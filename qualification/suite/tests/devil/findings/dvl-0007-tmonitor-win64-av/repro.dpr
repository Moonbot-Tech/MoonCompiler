program mon3;
{$ifdef FPC}
  {$mode delphiunicode}{$H+}
{$endif}
{$APPTYPE CONSOLE}
uses SysUtils, Classes;
var
  Lock: TObject;
  Counter: Int64;
begin
  Lock := TObject.Create;
  Counter := 0;
  TMonitor.Enter(Lock);
  try
    Inc(Counter, 10);
  finally
    TMonitor.Exit(Lock);
  end;
  WriteLn('main-thread counter=', Counter, '   expected 10');
  Lock.Free;
end.
