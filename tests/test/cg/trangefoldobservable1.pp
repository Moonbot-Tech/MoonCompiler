program trangefoldobservable1;

{$mode delphi}
{$R+}

uses
  SysUtils;

var
  Values: array[0..0] of Byte;
  IntValues: array[0..0] of Integer;
  UIntValues: array[0..0] of Cardinal;
  Int64Values: array[0..0] of Int64;
  QWordValues: array[0..0] of QWord;
  UX: Cardinal;
  X64: Int64;
  UX64: QWord;
  Index,Calls,X: Integer;
  B,Raised: Boolean;

function NextByte: Byte; noinline;
begin
  Inc(Calls);
  Result:=17;
end;

function MinLow(I: Integer): Integer; noinline;
begin
  if IntValues[I]<Low(Integer) then
    Result:=IntValues[I]
  else
    Result:=Low(Integer);
end;

function MinLowReversed(I: Integer): Integer; noinline;
begin
  if Low(Integer)>IntValues[I] then
    Result:=IntValues[I]
  else
    Result:=Low(Integer);
end;

function MaxHigh(I: Integer): Integer; noinline;
begin
  if IntValues[I]>High(Integer) then
    Result:=IntValues[I]
  else
    Result:=High(Integer);
end;

function MaxHighReversed(I: Integer): Integer; noinline;
begin
  if High(Integer)<IntValues[I] then
    Result:=IntValues[I]
  else
    Result:=High(Integer);
end;

function MinTwenty(I: Integer): Integer; noinline;
begin
  if IntValues[I]<20 then
    Result:=IntValues[I]
  else
    Result:=20;
end;

function MaxTen(I: Integer): Integer; noinline;
begin
  if IntValues[I]>10 then
    Result:=IntValues[I]
  else
    Result:=10;
end;

{ the other operand types of the same fold: every one of them can drop the
  element together with its range check }
function MinZeroUnsigned(I: Integer): Cardinal; noinline;
begin
  if UIntValues[I]<0 then
    Result:=UIntValues[I]
  else
    Result:=0;
end;

function MaxHighUnsigned(I: Integer): Cardinal; noinline;
begin
  if High(Cardinal)<UIntValues[I] then
    Result:=UIntValues[I]
  else
    Result:=High(Cardinal);
end;

function MinLowInt64(I: Integer): Int64; noinline;
begin
  if Int64Values[I]<Low(Int64) then
    Result:=Int64Values[I]
  else
    Result:=Low(Int64);
end;

function MaxHighQWord(I: Integer): QWord; noinline;
begin
  if QWordValues[I]>High(QWord) then
    Result:=QWordValues[I]
  else
    Result:=High(QWord);
end;

{ the update form: the element is the target and an operand }
procedure UpdateMin(I,Candidate: Integer); noinline;
begin
  if Candidate<IntValues[I] then
    IntValues[I]:=Candidate;
end;

function PureMin(A,B: Integer): Integer; noinline;
begin
  if A<B then
    Result:=A
  else
    Result:=B;
end;

function PureMax(A,B: Integer): Integer; noinline;
begin
  if A>B then
    Result:=A
  else
    Result:=B;
end;

procedure ExpectRange(Code: Integer);
begin
  if not Raised then
    Halt(Code);
end;

begin
  Index:=1;
  Raised:=False;
  try B:=Values[Index]<300; except on ERangeError do Raised:=True; end;
  ExpectRange(1);
  Raised:=False;
  try B:=-1<Values[Index]; except on ERangeError do Raised:=True; end;
  ExpectRange(2);
  Raised:=False;
  try B:=Values[Index]>=-1; except on ERangeError do Raised:=True; end;
  ExpectRange(3);
  Raised:=False;
  try B:=300>Values[Index]; except on ERangeError do Raised:=True; end;
  ExpectRange(4);

  Calls:=0;
  if not (NextByte<300) or (Calls<>1) then Halt(5);
  Calls:=0;
  if not (-1<NextByte) or (Calls<>1) then Halt(6);

  Raised:=False;
  try X:=MinLow(Index); except on ERangeError do Raised:=True; end;
  ExpectRange(7);
  Raised:=False;
  try X:=MinLowReversed(Index); except on ERangeError do Raised:=True; end;
  ExpectRange(8);
  Raised:=False;
  try X:=MaxHigh(Index); except on ERangeError do Raised:=True; end;
  ExpectRange(9);
  Raised:=False;
  try X:=MaxHighReversed(Index); except on ERangeError do Raised:=True; end;
  ExpectRange(10);
  Raised:=False;
  try X:=MinTwenty(Index); except on ERangeError do Raised:=True; end;
  ExpectRange(15);
  Raised:=False;
  try X:=MaxTen(Index); except on ERangeError do Raised:=True; end;
  ExpectRange(16);

  Raised:=False;
  try UX:=MinZeroUnsigned(Index); except on ERangeError do Raised:=True; end;
  ExpectRange(17);
  Raised:=False;
  try UX:=MaxHighUnsigned(Index); except on ERangeError do Raised:=True; end;
  ExpectRange(18);
  Raised:=False;
  try X64:=MinLowInt64(Index); except on ERangeError do Raised:=True; end;
  ExpectRange(19);
  Raised:=False;
  try UX64:=MaxHighQWord(Index); except on ERangeError do Raised:=True; end;
  ExpectRange(20);
  Raised:=False;
  try UpdateMin(Index,-5); except on ERangeError do Raised:=True; end;
  ExpectRange(21);

  UIntValues[0]:=17;
  Int64Values[0]:=17;
  QWordValues[0]:=17;
  if (MinZeroUnsigned(0)<>0) or (MaxHighUnsigned(0)<>High(Cardinal)) then
    Halt(22);
  if (MinLowInt64(0)<>Low(Int64)) or (MaxHighQWord(0)<>High(QWord)) then
    Halt(23);
  IntValues[0]:=40;
  UpdateMin(0,50);
  if IntValues[0]<>40 then
    Halt(24);
  UpdateMin(0,-5);
  if IntValues[0]<>-5 then
    Halt(25);

  IntValues[0]:=17;
  if (MinLow(0)<>Low(Integer)) or (MinLowReversed(0)<>Low(Integer)) then
    Halt(11);
  if (MaxHigh(0)<>High(Integer)) or (MaxHighReversed(0)<>High(Integer)) then
    Halt(12);
  if (MinTwenty(0)<>17) or (MaxTen(0)<>17) then
    Halt(13);
  if (PureMin(17,20)<>17) or (PureMax(17,10)<>17) then
    Halt(14);
end.
