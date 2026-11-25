{ Extract transfers an executed command to the caller; removal discards unfinished work. }

type
  TBreadthOwnedCommand = class
    Member: Cardinal;
    Ticket: Int64;
    class var Destroyed: Cardinal;
    constructor Create(ID: Cardinal; Value: Int64);
    destructor Destroy; override;
  end;

constructor TBreadthOwnedCommand.Create(ID: Cardinal; Value: Int64);
begin
  inherited Create;
  Member := ID;
  Ticket := Value;
end;

destructor TBreadthOwnedCommand.Destroy;
begin
  Destroyed := Destroyed or (Cardinal(1) shl Member);
  inherited Destroy;
end;

procedure RunBreadthOwnedCommandQueue;
var
  Pending: TObjectQueue<TBreadthOwnedCommand>;
  Started: TBreadthOwnedCommand;
begin
  TBreadthOwnedCommand.Destroyed := 0;
  Pending := TObjectQueue<TBreadthOwnedCommand>.Create(True);
  Started := nil;
  try
    Pending.Capacity := 3;
    Pending.Enqueue(TBreadthOwnedCommand.Create(0, OpaqueI(11)));
    Pending.Enqueue(TBreadthOwnedCommand.Create(1, OpaqueI(-820000000003)));
    Pending.Enqueue(TBreadthOwnedCommand.Create(2, OpaqueI(23)));
    Pending.Dequeue;
    Check((Pending.Count = 2) and (TBreadthOwnedCommand.Destroyed = $01),
      'breadth-object-queue-dequeue-destroys-only-removed-head');
    Pending.Enqueue(TBreadthOwnedCommand.Create(3, OpaqueI(37)));
    Started := Pending.Extract;
    Check((Started <> nil) and (Started.Ticket = -820000000003) and (Pending.Count = 2)
      and (TBreadthOwnedCommand.Destroyed = $01), 'breadth-object-queue-extract-transfers-oldest-without-destroying-it');
    Pending.Clear;
    Check((Pending.Count = 0) and (TBreadthOwnedCommand.Destroyed = $0D),
      'breadth-object-queue-clear-destroys-only-still-owned-commands');
    Mix(UInt64(Started.Ticket));
  finally
    FreeAndNil(Pending);
    FreeAndNil(Started);
  end;
  Check(TBreadthOwnedCommand.Destroyed = $0F, 'breadth-object-queue-extracted-command-is-freed-by-caller');
end;

procedure RunBreadthOwnedCommandStack;
var
  Undo: TObjectStack<TBreadthOwnedCommand>;
  Latest: TBreadthOwnedCommand;
begin
  TBreadthOwnedCommand.Destroyed := 0;
  Undo := TObjectStack<TBreadthOwnedCommand>.Create(True);
  Latest := nil;
  try
    Undo.Push(TBreadthOwnedCommand.Create(0, OpaqueI(17)));
    Undo.Push(TBreadthOwnedCommand.Create(1, OpaqueI(29)));
    Undo.Push(TBreadthOwnedCommand.Create(2, OpaqueI(530000000019)));
    Latest := Undo.Extract;
    Check((Latest <> nil) and (Latest.Ticket = 530000000019) and (Undo.Count = 2)
      and (TBreadthOwnedCommand.Destroyed = 0), 'breadth-object-stack-extract-transfers-most-recent-command');
    Undo.Pop;
    Check((Undo.Count = 1) and (TBreadthOwnedCommand.Destroyed = $02),
      'breadth-object-stack-pop-destroys-next-command');
    FreeAndNil(Undo);
    Check((TBreadthOwnedCommand.Destroyed = $03) and (Latest.Ticket = 530000000019),
      'breadth-object-stack-destruction-keeps-transferred-command-alive');
    Mix(UInt64(Latest.Ticket));
  finally
    FreeAndNil(Undo);
    FreeAndNil(Latest);
  end;
  Check(TBreadthOwnedCommand.Destroyed = $07, 'breadth-object-stack-extracted-command-is-freed-by-caller');
end;
