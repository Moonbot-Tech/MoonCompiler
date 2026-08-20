program collections_codegen;

{$mode delphi}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  cwstring,
  {$endif UNIX}
  SysUtils,
  Generics.Collections;

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create('COLLECTIONS_CODEGEN_FAIL: '+AMessage);
end;

function SumList(AList: TList<Integer>): Int64; noinline;
var
  Value: Integer;
begin
  Result:=0;
  for Value in AList do
    Inc(Result,Value);
end;

function SumQueue(AQueue: TQueue<Integer>): Int64; noinline;
var
  Value: Integer;
begin
  Result:=0;
  for Value in AQueue do
    Inc(Result,Value);
end;

function SumStack(AStack: TStack<Integer>): Int64; noinline;
var
  Value: Integer;
begin
  Result:=0;
  for Value in AStack do
    Inc(Result,Value);
end;

var
  I: Integer;
  List: TList<Integer>;
  Queue: TQueue<Integer>;
  Stack: TStack<Integer>;
begin
  List:=TList<Integer>.Create;
  Queue:=TQueue<Integer>.Create;
  Stack:=TStack<Integer>.Create;
  try
    for I:=1 to 100 do
      begin
      List.Add(I);
      Queue.Enqueue(I);
      Stack.Push(I);
      end;
    Check(SumList(List)=5050,'list sum');
    Check(SumQueue(Queue)=5050,'queue sum');
    Check(SumStack(Stack)=5050,'stack sum');
  finally
    Stack.Free;
    Queue.Free;
    List.Free;
  end;
  WriteLn('COLLECTIONS_CODEGEN_PASS');
end.
