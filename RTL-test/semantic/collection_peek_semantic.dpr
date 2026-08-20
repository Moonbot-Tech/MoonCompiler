program collection_peek_semantic;

{$mode delphi}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  cwstring,
  {$endif UNIX}
  SysUtils,
  Generics.Collections;

type
  ITracked = interface
    ['{63709495-0F32-4151-84BB-8EF185318E30}']
    function Value: Integer;
  end;

  TTracked = class(TInterfacedObject, ITracked)
  private
    FValue: Integer;
  public
    constructor Create(AValue: Integer);
    destructor Destroy; override;
    function Value: Integer;
  end;

  TManagedValue = record
    Text: UnicodeString;
    Bytes: TBytes;
    Item: ITracked;
  end;

var
  Destroyed: Integer;

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    raise Exception.Create(MessageText);
end;

constructor TTracked.Create(AValue: Integer);
begin
  inherited Create;
  FValue := AValue;
end;

destructor TTracked.Destroy;
begin
  Inc(Destroyed);
  inherited Destroy;
end;

function TTracked.Value: Integer;
begin
  Result := FValue;
end;

procedure TestIntegerOrderAndEmptyBoundaries;
var
  Raised: Boolean;
  Value: Integer;
  Queue: TQueue<Integer>;
  Stack: TStack<Integer>;
begin
  Queue := TQueue<Integer>.Create;
  Stack := TStack<Integer>.Create;
  try
    Queue.Enqueue(10);
    Queue.Enqueue(20);
    Stack.Push(10);
    Stack.Push(20);
    Check((Queue.Peek = 10) and (Queue.Count = 2),
      'queue Peek is non-destructive FIFO head');
    Check((Stack.Peek = 20) and (Stack.Count = 2),
      'stack Peek is non-destructive LIFO head');
    Check((Queue.Dequeue = 10) and (Queue.Peek = 20),
      'queue Peek after nonzero-low removal');
    Check((Stack.Pop = 20) and (Stack.Peek = 10),
      'stack Peek after Pop');
    Queue.Clear;
    Stack.Clear;

    Raised := False;
    try
      Value := Queue.Peek;
    except
      on EArgumentOutOfRangeException do
        Raised := True;
    end;
    Check(Raised, 'queue empty Peek exception');
    Raised := False;
    try
      Value := Stack.Peek;
    except
      on EArgumentOutOfRangeException do
        Raised := True;
    end;
    Check(Raised, 'stack empty Peek exception');
  finally
    Stack.Free;
    Queue.Free;
  end;
end;

procedure TestManagedLifetimeAndCopySemantics;
var
  QueueItem, QueueRead, StackItem, StackRead: TManagedValue;
  Queue: TQueue<TManagedValue>;
  Stack: TStack<TManagedValue>;
begin
  Destroyed := 0;
  QueueItem.Text := 'queue-shared';
  QueueItem.Bytes := TBytes.Create(1, 2, 3);
  QueueItem.Item := TTracked.Create(11);
  StackItem.Text := 'stack-shared';
  StackItem.Bytes := TBytes.Create(4, 5, 6);
  StackItem.Item := TTracked.Create(22);
  Queue := TQueue<TManagedValue>.Create;
  Stack := TStack<TManagedValue>.Create;
  try
    Queue.Enqueue(QueueItem);
    Stack.Push(StackItem);
    QueueItem := Default(TManagedValue);
    StackItem := Default(TManagedValue);
    Check(Destroyed = 0, 'collections retain managed records');

    QueueRead := Queue.Peek;
    StackRead := Stack.Peek;
    Check((QueueRead.Text = 'queue-shared') and
      (QueueRead.Bytes[1] = 2) and (QueueRead.Item.Value = 11),
      'queue managed Peek value');
    Check((StackRead.Text = 'stack-shared') and
      (StackRead.Bytes[1] = 5) and (StackRead.Item.Value = 22),
      'stack managed Peek value');
    QueueRead.Text[1] := 'Q';
    StackRead.Text[1] := 'S';
    QueueRead.Bytes[1] := 9;
    StackRead.Bytes[1] := 8;
    QueueItem := Queue.Peek;
    StackItem := Stack.Peek;
    Check(QueueItem.Text = 'queue-shared', 'queue Peek string COW');
    Check(StackItem.Text = 'stack-shared', 'stack Peek string COW');
    Check(QueueItem.Bytes[1] = 9, 'queue Peek dynamic array sharing');
    Check(StackItem.Bytes[1] = 8, 'stack Peek dynamic array sharing');
    QueueItem := Default(TManagedValue);
    StackItem := Default(TManagedValue);
    QueueRead := Default(TManagedValue);
    StackRead := Default(TManagedValue);
    Check(Destroyed = 0, 'Peek temporaries release only copied owners');
    Queue.Clear;
    Check(Destroyed = 1, 'queue Clear releases retained interface once');
    Stack.Clear;
    Check(Destroyed = 2, 'stack Clear releases retained interface once');
  finally
    QueueRead := Default(TManagedValue);
    StackRead := Default(TManagedValue);
    Stack.Free;
    Queue.Free;
  end;
  Check(Destroyed = 2, 'Peek managed lifetime exact');
end;

begin
  try
    TestIntegerOrderAndEmptyBoundaries;
    TestManagedLifetimeAndCopySemantics;
    WriteLn('COLLECTION_PEEK_SEMANTIC_PASS');
  except
    on E: Exception do
    begin
      WriteLn(ErrOutput, E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
