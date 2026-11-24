{ FIFO wrap and growth with managed records and an independently retained snapshot. }

type
  TBreadthQueuePacket = record
    Code: Int64;
    LabelText: AnsiString;
    Owner: IInterface;
  end;
  TBreadthQueue = TQueue<TBreadthQueuePacket>;
  TBreadthQueueSnapshot = TArray<TBreadthQueuePacket>;

procedure BreadthEnqueuePacket(Queue: TBreadthQueue; Code: Int64);
var
  Item: TBreadthQueuePacket;
begin
  Item.Code := Code;
  Item.LabelText := AnsiString('job-' + IntToStr(Code));
  Item.Owner := TIntersectionOwner.Create;
  Queue.Enqueue(Item);
end;

procedure BreadthCollectQueueSnapshot(out Snapshot: TBreadthQueueSnapshot);
var
  Queue: TBreadthQueue;
  Item: TBreadthQueuePacket;
begin
  Queue := TBreadthQueue.Create;
  try
    Queue.Capacity := 4;
    BreadthEnqueuePacket(Queue, OpaqueI(19));
    BreadthEnqueuePacket(Queue, OpaqueI(-204));
    BreadthEnqueuePacket(Queue, OpaqueI(3000000521));
    BreadthEnqueuePacket(Queue, OpaqueI(666));
    Item := Queue.Dequeue;
    Check((Item.Code = 19) and (Item.LabelText = 'job-19') and (Item.Owner <> nil),
      'breadth-queue-dequeue-first-managed-record');
    Item := Queue.Dequeue;
    Check((Item.Code = -204) and (Item.LabelText = 'job--204') and (Item.Owner <> nil),
      'breadth-queue-dequeue-second-managed-record');
    BreadthEnqueuePacket(Queue, OpaqueI(73));
    BreadthEnqueuePacket(Queue, OpaqueI(-88));
    BreadthEnqueuePacket(Queue, OpaqueI(55));
    Check(Queue.Count = 5, 'breadth-queue-wrapped-growth-retains-active-count');
    Item := Queue.Peek;
    Check((Item.Code = 3000000521) and (Item.LabelText = 'job-3000000521') and (Item.Owner <> nil),
      'breadth-queue-peek-after-wrapped-growth');
    Snapshot := Queue.ToArray;
    Queue.Clear;
    Check(Queue.Count = 0, 'breadth-queue-clear-leaves-snapshot');
  finally
    Queue.Free;
  end;
end;

procedure RunBreadthManagedQueue;
const
  Codes: array[0..4] of Int64 = (3000000521, 666, 73, -88, 55);
  Labels: array[0..4] of AnsiString = ('job-3000000521', 'job-666', 'job-73', 'job--88', 'job-55');
var
  Snapshot: TBreadthQueueSnapshot;
  I: Integer;
begin
  TIntersectionOwner.Destroyed := 0;
  BreadthCollectQueueSnapshot(Snapshot);
  Check((Length(Snapshot) = 5) and (TIntersectionOwner.Destroyed = 2), 'breadth-queue-snapshot-owns-five-packets');
  for I := 0 to High(Codes) do begin
    If I > High(Snapshot) then
      Break;
    Check((Snapshot[I].Code = Codes[I]) and (Snapshot[I].LabelText = Labels[I])
      and (Snapshot[I].Owner <> nil), 'breadth-queue-snapshot-matches-fifo-order');
    Mix(UInt64(Snapshot[I].Code));
  end;
  Snapshot := nil;
  Check(TIntersectionOwner.Destroyed = 7, 'breadth-queue-snapshot-releases-last-owners');
end;
