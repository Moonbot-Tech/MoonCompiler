{$ifdef BREADTH_HAS_PRODUCT_IO}
{ A producer gives up managed payloads after posting, while the consumer
  reads a complete copy that outlives both the producer and the queue. }

type
  TBreadthWorkPacket = record
    Ticket: Int64;
    Text: UnicodeString;
    Owner: IBreadthTaggedOwner;
  end;

  TBreadthWorkQueue = TThreadedQueue<TBreadthWorkPacket>;
  TBreadthWorkProducer = class(TThread)
  public
    Queue: TBreadthWorkQueue;
    Outcome: TWaitResult;
    PublishedSize: NativeInt;
    procedure Execute; override;
  end;

procedure TBreadthWorkProducer.Execute;
var
  Packet: TBreadthWorkPacket;
begin
  Packet.Ticket := OpaqueI(-96000000013);
  Packet.Text := 'peer' + #0 + #$03BB;
  Packet.Owner := TBreadthTaggedOwner.Create;
  Outcome := Queue.PushItem(Packet, PublishedSize);
  Packet.Text[1] := 'R';
  Packet.Owner := nil;
end;

procedure BreadthReceiveWorkPackets;
var
  Queue: TBreadthWorkQueue;
  Producer: TBreadthWorkProducer;
  Initial, First, Second: TBreadthWorkPacket;
  PushedSize, FirstSize, SecondSize: NativeInt;
begin
  Queue := TBreadthWorkQueue.Create(1, 2000, 2000);
  try
    Initial.Ticket := OpaqueI(73000000019);
    Initial.Text := 'head';
    Initial.Owner := TBreadthTaggedOwner.Create;
    Check((Queue.PushItem(Initial, PushedSize) = wrSignaled) and (PushedSize = 1),
      'breadth-threaded-queue-publishes-initial-item-to-capacity-one');
    Initial.Text[1] := 'B';
    Initial.Owner := nil;
    Producer := TBreadthWorkProducer.Create(True);
    try
      Producer.Queue := Queue;
      Producer.Start;
      Check((Queue.PopItem(FirstSize, First) = wrSignaled) and (FirstSize = 0),
        'breadth-threaded-queue-pops-first-to-make-room');
      Check((Queue.PopItem(SecondSize, Second) = wrSignaled) and (SecondSize = 0),
        'breadth-threaded-queue-receives-producer-data');
      Producer.WaitFor;
      Check((Producer.Outcome = wrSignaled) and (Producer.PublishedSize = 1) and (Producer.FatalException = nil),
        'breadth-threaded-queue-reports-producer-publication');
      Check((Queue.QueueSize = 0) and (Queue.TotalItemsPushed = 2) and (Queue.TotalItemsPopped = 2),
        'breadth-threaded-queue-conserves-both-transfers');
    finally
      Producer.Free;
    end;
  finally
    Queue.Free;
  end;
  Check((First.Ticket = 73000000019) and (First.Text = 'head') and (First.Owner <> nil)
    and (First.Owner.Tag = 74000000051), 'breadth-threaded-queue-first-managed-snapshot-survives-source-edit');
  Check((Second.Ticket = -96000000013) and (Second.Text = 'peer' + #0 + #$03BB) and (Second.Owner <> nil)
    and (Second.Owner.Tag = 74000000051) and (Second.Owner <> First.Owner),
    'breadth-threaded-queue-peer-managed-payload-survives-producer-and-queue');
  Mix(UInt64(First.Ticket) xor UInt64(Second.Ticket));
end;

procedure RunBreadthThreadedWork;
begin
  TBreadthTaggedOwner.Destroyed := 0;
  BreadthReceiveWorkPackets;
  Check(TBreadthTaggedOwner.Destroyed = 2, 'breadth-threaded-queue-releases-both-payload-owners-once');
end;

{$endif}
