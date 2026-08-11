{ %target=linux }
{%skiptarget=$nothread }
program tmonitorfinalize;

{$mode objfpc}

uses
{$ifdef unix}
  cthreads,
{$endif}
  umonitorfinalize,
  fpmonitor;

begin
  TouchMonitor;
end.
