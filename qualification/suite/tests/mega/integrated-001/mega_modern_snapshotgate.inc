{$ifdef BREADTH_HAS_PRODUCT_IO}
{ A pending snapshot publisher must leave a live reader's version intact. }

type
  TBreadthSnapshotProbe = class(TThread)
    Gate: TLightweightMREW;
    Snapshot, Observed: Int64;
    RejectedWrite, SharedRead: Boolean;
    procedure Execute; override;
  end;

procedure TBreadthSnapshotProbe.Execute;
begin
  RejectedWrite := not Gate.TryBeginWrite;
  If not RejectedWrite then
    Gate.EndWrite;
  SharedRead := Gate.TryBeginRead;
  If SharedRead then begin
    try
      Observed := Snapshot;
    finally
      Gate.EndRead;
    end;
  end;
end;

procedure RunBreadthSnapshotGate;
var
  Probe: TBreadthSnapshotProbe;
  Published: Boolean;
  Payload: Int64;
begin
  Probe := TBreadthSnapshotProbe.Create(True);
  try
    Probe.Snapshot := OpaqueI(810000000079);
    Probe.Gate.BeginRead;
    try
      Probe.Start;
      Probe.WaitFor;
    finally
      Probe.Gate.EndRead;
    end;
    Check(Probe.RejectedWrite and Probe.SharedRead and (Probe.Observed = 810000000079),
      'breadth-rw-gate-excludes-publisher-while-allowing-overlapping-read');

    Published := Probe.Gate.TryBeginWrite;
    If Published then begin
      try
        Probe.Snapshot := OpaqueI(-730000000037);
      finally
        Probe.Gate.EndWrite;
      end;
    end;
    Probe.Gate.BeginRead;
    try
      Payload := Probe.Snapshot;
    finally
      Probe.Gate.EndRead;
    end;
    Check(Published and (Payload = -730000000037), 'breadth-rw-gate-publishes-snapshot-after-last-reader-releases');
    Mix(UInt64(Payload));
  finally
    Probe.Free;
  end;
end;
{$endif}
