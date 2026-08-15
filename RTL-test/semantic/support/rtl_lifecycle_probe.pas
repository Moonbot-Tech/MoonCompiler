unit rtl_lifecycle_probe;

{$mode delphi}{$H+}

interface

function InitializationPassed: Boolean;

implementation

uses
  Classes,
  {$ifdef WINDOWS}
  fpwinmonitor;
  {$else WINDOWS}
  fpmonitor;
  {$endif WINDOWS}

var
  Critical: TRTLCriticalSection;
  MonitorObject: TObject;
  Initialized: Boolean;

function InitializationPassed: Boolean;
begin
  Result := Initialized;
end;

initialization
  InitCriticalSection(Critical);
  EnterCriticalSection(Critical);
  LeaveCriticalSection(Critical);
  MonitorObject := TObject.Create;
  TMonitor.Enter(MonitorObject);
  TMonitor.Exit(MonitorObject);
  Initialized := True;

finalization
  TMonitor.Enter(MonitorObject);
  TMonitor.Exit(MonitorObject);
  MonitorObject.Free;
  DoneCriticalSection(Critical);

end.
