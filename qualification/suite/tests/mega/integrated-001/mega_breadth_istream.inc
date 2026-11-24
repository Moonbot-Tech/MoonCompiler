{ IStream forwards a signed seek and an exact read while observing stream ownership. }

type
  TBreadthAdapterBacking = class(TBreadthSparseStream)
    class var Released: Integer;
    destructor Destroy; override;
  end;

destructor TBreadthAdapterBacking.Destroy;
begin
  Inc(Released);
  inherited;
end;

procedure BreadthExerciseStreamAdapter(Ownership: TStreamOwnership);
const
  Base = 57000000019;
var
  Backing: TBreadthAdapterBacking;
  Adapter, CopyView: IStream;
  Position: UInt64;
  Data: array[0..2] of Byte;
  Counts: record
    ReadCount, Guard: Cardinal;
  end;
  Status: HResult;
begin
  Backing := TBreadthAdapterBacking.Create(OpaqueI(Base));
  try
    Adapter := TStreamAdapter.Create(Backing, Ownership);
    If Ownership = soOwned then
      Backing := nil;
    CopyView := Adapter;
    Adapter := nil;
    Check(TBreadthAdapterBacking.Released = 0, 'breadth-stream-adapter-interface-copy-keeps-backing');

    Position := 0;
    Status := CopyView.Seek(OpaqueI(-3), Ord(soEnd), Position);
    Check((Status = 0) and (Position = Base + 10), 'breadth-stream-adapter-seek-keeps-signed-delta-and-wide-position');
    FillChar(Data, SizeOf(Data), 0);
    Counts.ReadCount := 0;
    Counts.Guard := $DC2A64B7;
    Status := CopyView.Read(@Data[0], SizeOf(Data), @Counts.ReadCount);
    Check((Status = 0) and (Counts.ReadCount = 3) and (Counts.Guard = $DC2A64B7)
      and (Data[0] = $22) and (Data[1] = $11) and (Data[2] = $E7), 'breadth-stream-adapter-reads-exact-bytes-and-count-width');
    Status := CopyView.Read(nil, 1, @Counts.ReadCount);
    Check((Status = HResult($80030009)) and (Counts.Guard = $DC2A64B7), 'breadth-stream-adapter-rejects-missing-read-buffer');
    Status := CopyView.Seek(0, Ord(soCurrent), Position);
    Check((Status = 0) and (Position = Base + 13), 'breadth-stream-adapter-rejected-read-keeps-stream-position');
    CopyView := nil;
    Check(TBreadthAdapterBacking.Released = Ord(Ownership = soOwned), 'breadth-stream-adapter-releases-only-owned-stream');
    Mix(Position);
  finally
    Backing.Free;
  end;
end;

procedure RunBreadthStreamAdapter;
var
  Ownership: TStreamOwnership;
begin
  for Ownership := Low(TStreamOwnership) to High(TStreamOwnership) do begin
    TBreadthAdapterBacking.Released := 0;
    BreadthExerciseStreamAdapter(Ownership);
    Check(TBreadthAdapterBacking.Released = 1, 'breadth-stream-adapter-final-backing-release-is-once');
  end;
end;
