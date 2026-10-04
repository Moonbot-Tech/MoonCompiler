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

type
  TMarket = class
  public
    Found: Boolean;
  end;

  TMarketData = class
  public
    Objects: TObjectList<TMarket>;
    constructor Create;
    destructor Destroy; override;
  end;

constructor TMarketData.Create;
begin
  inherited Create;
  Objects:=TObjectList<TMarket>.Create(True);
end;

destructor TMarketData.Destroy;
begin
  Objects.Free;
  inherited Destroy;
end;

function CountAfterEmptyLoop(EmptyMarkets: TList<TMarket>;
  Data: TMarketData): Integer; noinline;
var
  M, X: TMarket;
begin
  Result:=0;
  for M in EmptyMarkets do
    M.Found:=False;
  for X in Data.Objects do
    Inc(Result);
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
  EmptyMarkets: TList<TMarket>;
  Data: TMarketData;
begin
  List:=TList<Integer>.Create;
  Queue:=TQueue<Integer>.Create;
  Stack:=TStack<Integer>.Create;
  EmptyMarkets:=TList<TMarket>.Create;
  Data:=TMarketData.Create;
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
    Data.Objects.Add(TMarket.Create);
    Data.Objects.Add(TMarket.Create);
    Check(CountAfterEmptyLoop(EmptyMarkets,Data)=2,
      'non-empty loop after empty loop');
  finally
    Data.Free;
    EmptyMarkets.Free;
    Stack.Free;
    Queue.Free;
    List.Free;
  end;
  WriteLn('COLLECTIONS_CODEGEN_PASS');
end.
