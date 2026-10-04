{ %OPT=-O3 }
program tforunrolllatephase1;

{$mode delphi}
{$inline on}

var
  Trail: QWord;

procedure Sink(const Value: Integer); noinline;
begin
  Trail:=Trail*10+QWord(Value);
end;

procedure Plain;
var
  Index: Integer;
begin
  for Index:=1 to 3 do
    Sink(Index);
end;

procedure WriteOnlyFinally;
var
  Index: Integer;
begin
  try
    for Index:=1 to 3 do
      Sink(Index);
  finally
    Index:=9;
  end;
end;

procedure WriteBeforeReadFinally;
var
  Index: Integer;
begin
  try
    for Index:=1 to 3 do
      Sink(Index);
  finally
    Index:=9;
    Sink(Index);
  end;
end;

procedure InlineLimit(const Limit: Integer); inline;
var
  Index: Integer;
begin
  for Index:=1 to Limit do
    Sink(Index);
end;

procedure UseInlineLimit;
begin
  InlineLimit(3);
end;

procedure TripleNested;
var
  I, J, K: Integer;
begin
  for I:=1 to 2 do
    for J:=1 to 2 do
      for K:=1 to 2 do
        Sink(K);
end;

procedure ArrayIteration;
const
  Values: array[1..3] of Integer=(1,2,3);
var
  Value: Integer;
begin
  for Value in Values do
    Sink(Value);
end;

type
  TUnpacked=array[1..3] of 0..7;
  TPacked=bitpacked array[1..3] of 0..7;

procedure PackArray;
var
  Source: TUnpacked;
  PackedValues: TPacked;
begin
  Source[1]:=1;
  Source[2]:=2;
  Source[3]:=3;
  Pack(Source,1,PackedValues);
  Sink(PackedValues[1]);
  Sink(PackedValues[2]);
  Sink(PackedValues[3]);
end;

type
  TRange=(rangeZero,rangeOne,rangeTwo);

procedure EnumIteration;
var
  Value: TRange;
begin
  for Value in TRange do
    Sink(Ord(Value));
end;

procedure LexicalOptimizerState;
var
  Index: Integer;
begin
  for Index:=1 to 3 do
    Sink(Index);
  {$optimization size}
end;
{$optimization default}

procedure Check(const Expected: QWord; const Code: Integer);
begin
  if Trail<>Expected then
    Halt(Code);
  Trail:=0;
end;

begin
  Trail:=0;
  Plain;
  Check(123,1);
  WriteOnlyFinally;
  Check(123,2);
  WriteBeforeReadFinally;
  Check(1239,3);
  UseInlineLimit;
  Check(123,4);
  TripleNested;
  Check(12121212,5);
  ArrayIteration;
  Check(123,6);
  PackArray;
  Check(123,7);
  EnumIteration;
  Check(12,8);
  LexicalOptimizerState;
  Check(123,9);
end.
