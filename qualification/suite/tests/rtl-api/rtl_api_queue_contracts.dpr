program rtl_api_queue_contracts;

{$APPTYPE CONSOLE}

{$ifdef FPC}
  {$mode delphiunicode}
  {$modeswitch inlinevars}
{$endif}

uses
  SysUtils,
  Generics.Collections;

procedure Check(ACondition: Boolean; const AName: string);
begin
  if not ACondition then
    begin
      WriteLn('FAIL ',AName);
      Halt(1);
    end;
end;

procedure CheckIntegers;
var
  Queue: TQueue<Integer>;
  Base: TEnumerable<Integer>;
  Values: TArray<Integer>;
begin
  Queue:=TQueue<Integer>.Create;
  try
    Values:=Queue.ToArray;
    Check(Length(Values)=0,'integer-empty');

    Queue.Enqueue(11);
    Queue.Enqueue(22);
    Queue.Enqueue(33);
    Values:=Queue.ToArray;
    Check((Length(Values)=3) and (Values[0]=11) and (Values[1]=22) and
      (Values[2]=33),'integer-steady');

    Check(Queue.Dequeue=11,'integer-dequeue');
    Base:=Queue;
    Values:=Base.ToArray;
    Check((Length(Values)=2) and (Values[0]=22) and (Values[1]=33),
      'integer-base-dispatch');

    Queue.Enqueue(44);
    Queue.Enqueue(55);
    Values:=Queue.ToArray;
    Check((Length(Values)=4) and (Values[0]=22) and (Values[1]=33) and
      (Values[2]=44) and (Values[3]=55),'integer-after-reuse');

    Queue.TrimExcess;
    Values:=Queue.ToArray;
    Check((Length(Values)=4) and (Values[0]=22) and (Values[3]=55),
      'integer-trimmed');
  finally
    Queue.Free;
  end;
end;

procedure CheckStrings;
var
  Queue: TQueue<string>;
  Values: TArray<string>;
begin
  Queue:=TQueue<string>.Create;
  try
    Queue.Enqueue('alpha');
    Queue.Enqueue('bravo');
    Queue.Enqueue('charlie');
    Check(Queue.Dequeue='alpha','string-dequeue');
    Values:=Queue.ToArray;
    Check((Length(Values)=2) and (Values[0]='bravo') and
      (Values[1]='charlie'),'string-logical-range');
    Queue.Clear;
    Values:=Queue.ToArray;
    Check(Length(Values)=0,'string-cleared');
  finally
    Queue.Free;
  end;
end;

begin
  CheckIntegers;
  CheckStrings;
  WriteLn('RTL_API_QUEUE_CONTRACTS_OK');
end.
