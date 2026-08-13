program medium_single;

{$mode delphi}{$H+}
{$APPTYPE CONSOLE}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  {$endif UNIX}
  SysUtils;

var
  P: Pointer;
begin
  GetMem(P, 100500);
  FillChar(P^, 100500, $5a);
  FreeMem(P);
  WriteLn('PASS');
end.
