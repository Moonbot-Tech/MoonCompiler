program monitor_finalize;

{$mode delphi}

uses
  cthreads,
  monitor_finalize_unit,
  fpmonitor;

begin
  TouchMonitor;
  WriteLn('MONITOR_FINALIZE_OK');
end.
