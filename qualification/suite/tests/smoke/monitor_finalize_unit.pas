unit monitor_finalize_unit;

{$mode delphi}

interface

procedure TouchMonitor;

implementation

var
  LockObject: TObject;

procedure TouchMonitor;
begin
  TMonitor.Enter(LockObject);
  TMonitor.Exit(LockObject);
end;

initialization
  LockObject := TObject.Create;

finalization
  LockObject.Free;
  LockObject := nil;

end.
