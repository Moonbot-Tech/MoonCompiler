{$if defined(BREADTH_HAS_PRODUCT_IO) and defined(HAS_ANON)}
{ A parallel export visits each wide ticket id once and publishes every managed row before returning. }

procedure BreadthCheckBatchErrors(Pool: TThreadPool);
var
  Cancelled, Invalid, Exported: ITask;
  CancelWork, ParseWork, ExportWork: TProc;
  Receipts: string;
  Count, I: Integer;
  Error: Exception;
  GotCancel, GotSchema: Boolean;
begin
  CancelWork := procedure begin raise EAbort.Create('fetch cancelled'); end;
  ParseWork := procedure begin raise EConvertError.Create('invalid export schema'); end;
  ExportWork := procedure begin Receipts := 'exported ' + #$03BB + #0 + ' confirmed'; end;
  Cancelled := TTask.Run(CancelWork, Pool);
  Invalid := TTask.Run(ParseWork, Pool);
  Exported := TTask.Run(ExportWork, Pool);
  Count := 0;
  GotCancel := False;
  GotSchema := False;
  try
    TTask.WaitForAll([Cancelled, Invalid, Exported]);
  except
    on E: EAggregateException do begin
      Count := E.Count;
      for I := 0 to Count - 1 do begin
        Error := E.InnerExceptions[I];
        GotCancel := GotCancel or ((Error is EAbort) and (Error.Message = 'fetch cancelled'));
        GotSchema := GotSchema or ((Error is EConvertError) and (Error.Message = 'invalid export schema'));
      end;
    end;
  end;
  Check((Count = 2) and GotCancel and GotSchema, 'breadth-job-batch-aggregates-both-original-errors');
  Check((Cancelled.Status = TTaskStatus.Exception) and (Invalid.Status = TTaskStatus.Exception),
    'breadth-job-batch-exposes-failed-states');
  Check((Exported.Status = TTaskStatus.Completed) and (Receipts = 'exported ' + #$03BB + #0 + ' confirmed'),
    'breadth-job-batch-joins-successful-export-before-reporting-sibling-errors');
  Mix(UInt64(Count * 100 + Length(Receipts)));
end;

type
  TBreadthFutureReceipt = record
    ID: Int64;
    Title: UnicodeString;
    Limits: TArray<Integer>;
  end;

procedure BreadthCheckFutureReceipt(Pool: TThreadPool);
const
  Expected: UnicodeString = 'export' + #$03BB + #0 + #$D83D#$DE80;
var
  Future: IFuture<TBreadthFutureReceipt>;
  Build: TFunc<TBreadthFutureReceipt>;
  Current, Saved: TBreadthFutureReceipt;
  Title: UnicodeString;
  Runs: Integer;
begin
  Runs := 0;
  Title := Expected;
  Build :=
    function: TBreadthFutureReceipt
    begin
      Inc(Runs);
      Result.ID := OpaqueI(-9007199254740989);
      Result.Title := Title;
      Result.Limits := [17, -23, 42];
    end;
  Future := TTask.Future<TBreadthFutureReceipt>(Build, Pool);
  Current := Future.Value;
  Saved := Future.Value;
  Check((Runs = 1) and (Future.Status = TTaskStatus.Completed), 'breadth-future-receipt-repeated-value-runs-producer-once');
  Check((Current.ID = -9007199254740989) and (Current.Title = Expected) and (Length(Current.Limits) = 3),
    'breadth-future-receipt-delivers-wide-id-and-managed-data');

  SetLength(Current.Limits, 1);
  Current.Limits[0] := -5;
  Current.Title := '';
  Future := nil;
  Build := nil;
  Title := '';
  Check((Saved.ID = -9007199254740989) and (Saved.Title = Expected),
    'breadth-future-receipt-copy-survives-task-and-producer-release');
  Check((Length(Saved.Limits) = 3) and (Saved.Limits[0] = 17) and (Saved.Limits[1] = -23) and (Saved.Limits[2] = 42),
    'breadth-future-receipt-edit-detaches-the-first-result-array');
  Mix(UInt64(Saved.ID) xor UInt64(Length(Saved.Title) * 100 + Length(Saved.Limits)));
end;

procedure BreadthCheckParallelTicketExport(Pool: TThreadPool);
const
  First = Int64(5000000008);
  Expected: array[0..5] of string = ('5000000008', '5000000009', '5000000010',
    '5000000011', '5000000012', '5000000013');
var
  Visits: array[0..5] of Integer;
  Rows: array[0..5] of string;
  Unexpected, Slot: Integer;
  Start: Int64;
  LabelPrefix: string;
  Produce: TProc<Int64>;
  Status: TParallel.TLoopResult;
  Complete: Boolean;
begin
  FillChar(Visits, SizeOf(Visits), 0);
  Unexpected := 0;
  Start := OpaqueI(First);
  LabelPrefix := #$03BB + #0;
  Produce :=
    procedure(Id: Int64)
    var
      Ordinal: Integer;
    begin
      If (Id < Start) or (Id > Start + High(Rows)) then begin
        TInterlocked.Increment(Unexpected);
        Exit;
      end;
      Ordinal := Integer(Id - Start);
      If TInterlocked.Increment(Visits[Ordinal]) = 1 then
        Rows[Ordinal] := LabelPrefix + IntToStr(Id);
    end;
  Status := TParallel.&For(Start, Start + High(Rows), Produce, Pool);
  Check(Status.Completed and (Unexpected = 0), 'breadth-parallel-export-completes-full-64-bit-range');
  Complete := True;
  for Slot := Low(Rows) to High(Rows) do
    Complete := Complete and (Visits[Slot] = 1) and (Rows[Slot] = LabelPrefix + Expected[Slot]);
  Check(Complete, 'breadth-parallel-export-publishes-each-managed-row-exactly-once');
  Mix(UInt64(Length(Rows[High(Rows)])));
end;

procedure RunBreadthPooledExports;
var
  Pool: TThreadPool;
begin
  Pool := TThreadPool.Create;
  try
    Pool.SetMinWorkerThreads(2);
    Pool.SetMaxWorkerThreads(2);
    BreadthCheckParallelTicketExport(Pool);
    BreadthCheckBatchErrors(Pool);
    BreadthCheckFutureReceipt(Pool);
  finally
    Pool.Free;
  end;
end;
{$ifend}
