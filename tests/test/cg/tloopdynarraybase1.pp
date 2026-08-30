program tloopdynarraybase1;

{$mode delphi}
{$Q-}
{$R-}

type
  TIntArray = array of Int64;
  TStringArray = array of AnsiString;
  PInt64 = ^Int64;
  TPointerArray = array of PInt64;
  TItem = record
    Left, Right: Int64;
  end;
  TItemArray = array of TItem;

var
  GScalar, GSingle, GChecked, GWritten, GReassigned, GOther,
    GCall, GByRef, GNested, GCapA, GCapB, GCapC: TIntArray;
  GRecords: TItemArray;
  GStrings: TStringArray;
  GPointers: TPointerArray;
  GPointerValues: array[0..127] of Int64;
threadvar
  GThread: TIntArray;

procedure CheckEqual(Actual, Expected: Int64; const Name: AnsiString);
begin
  if Actual<>Expected then
    begin
      WriteLn('FAIL:',Name,':',Actual,':',Expected);
      Halt(1);
    end;
end;

function ScalarRead: Int64; noinline;
var
  Values: TIntArray;
  I: LongInt;
begin
  Values:=GScalar;
  Result:=0;
  for I:=0 to 63 do
    Result:=Result+Values[I*2]+Values[I*2+1];
end;

function RecordRead: Int64; noinline;
var
  Values: TItemArray;
  I: LongInt;
begin
  Values:=GRecords;
  Result:=0;
  for I:=0 to 63 do
    Result:=Result+Values[I*2].Left+Values[I*2+1].Right;
end;

function ManagedRead: Int64; noinline;
var
  Values: TStringArray;
  I: LongInt;
begin
  Values:=GStrings;
  Result:=0;
  for I:=0 to 63 do
    Result:=Result+Length(Values[I*2])+Length(Values[I*2+1]);
end;

function PointerRead: Int64; noinline;
var
  Values: TPointerArray;
  I: LongInt;
begin
  Values:=GPointers;
  Result:=0;
  for I:=0 to 63 do
    Result:=Result+Values[I*2]^+Values[I*2+1]^;
end;

function LocalRead: Int64; noinline;
var
  Values: TIntArray;
  I: LongInt;
begin
  SetLength(Values,64);
  for I:=0 to 63 do
    Values[I]:=I*7+5;
  Result:=0;
  for I:=0 to 31 do
    Result:=Result+Values[I*2]+Values[I*2+1];
end;

function PressureCap: Int64; noinline;
var
  A, B, C: TIntArray;
  I: LongInt;
begin
  A:=GCapA;
  B:=GCapB;
  C:=GCapC;
  Result:=0;
  for I:=0 to 63 do
    Result:=Result+
      A[I*2]+A[I*2+1]+
      B[I*2]+B[I*2+1]+
      C[I*2]+C[I*2+1];
end;

function ValueParamRead(Values: TIntArray): Int64; noinline;
var
  I: LongInt;
begin
  Result:=0;
  for I:=0 to 63 do
    Result:=Result+Values[I*2]+Values[I*2+1];
end;

function GlobalRead: Int64; noinline;
var
  I: LongInt;
begin
  Result:=0;
  for I:=0 to 63 do
    Result:=Result+GScalar[I*2]+GScalar[I*2+1];
end;

function SingleRead: Int64; noinline;
var
  Values: TIntArray;
  I: LongInt;
begin
  Values:=GSingle;
  Result:=0;
  for I:=0 to 63 do
    Result:=Result+Values[I*2];
end;

{$push}
{$Q+}
{$R+}
function CheckedRead: Int64; noinline;
var
  Values: TIntArray;
  I: LongInt;
begin
  Values:=GChecked;
  Result:=0;
  for I:=0 to 63 do
    Result:=Result+Values[I*2]+Values[I*2+1];
end;
{$pop}

function WrittenArray: Int64; noinline;
var
  Values: TIntArray;
  I: LongInt;
begin
  Values:=GWritten;
  Result:=0;
  for I:=0 to 63 do
    begin
      Values[I*2]:=Values[I*2]+(I and 1);
      Result:=Result+Values[I*2];
    end;
end;

function ReassignedArray: Int64; noinline;
var
  Values: TIntArray;
  I: LongInt;
begin
  Values:=GReassigned;
  Result:=0;
  for I:=0 to 7 do
    begin
      if I=3 then
        Values:=GOther;
      Result:=Result+Values[I*2]+Values[I*2+1];
    end;
end;

procedure TouchGlobal; noinline;
begin
  Inc(GCall[0]);
end;

function CallClobber: Int64; noinline;
var
  Values: TIntArray;
  I: LongInt;
begin
  Values:=GCall;
  Result:=0;
  for I:=0 to 7 do
    begin
      TouchGlobal;
      Result:=Result+Values[I*2]+Values[I*2+1];
    end;
end;

procedure TouchByRef(var Values: TIntArray); noinline;
begin
  Inc(Values[0]);
end;

function ByRefClobber: Int64; noinline;
var
  Values: TIntArray;
  I: LongInt;
begin
  Values:=GByRef;
  Result:=0;
  for I:=0 to 7 do
    begin
      TouchByRef(Values);
      Result:=Result+Values[I*2]+Values[I*2+1];
    end;
end;

function NestedSplit: Int64; noinline;
var
  Values: TIntArray;
  A, I: LongInt;
begin
  Values:=GNested;
  Result:=0;
  for A:=0 to 3 do
    begin
      Result:=Result+Values[A*32+1];
      for I:=0 to 15 do
        Result:=Result+Values[A*32+I*2];
    end;
end;

function ConstRefRead(constref Values: TIntArray): Int64; noinline;
var
  I: LongInt;
begin
  Result:=0;
  for I:=0 to 63 do
    Result:=Result+Values[I*2]+Values[I*2+1];
end;

function ThreadRead: Int64; noinline;
var
  I: LongInt;
begin
  Result:=0;
  for I:=0 to 63 do
    Result:=Result+GThread[I*2]+GThread[I*2+1];
end;

procedure InitializeData;
var
  I: LongInt;
begin
  SetLength(GScalar,128);
  SetLength(GSingle,128);
  SetLength(GChecked,128);
  SetLength(GWritten,128);
  SetLength(GRecords,128);
  SetLength(GStrings,128);
  SetLength(GPointers,128);
  SetLength(GNested,128);
  SetLength(GThread,128);
  SetLength(GCapA,128);
  SetLength(GCapB,128);
  SetLength(GCapC,128);
  for I:=0 to 127 do
    begin
      GScalar[I]:=I*3+1;
      GChecked[I]:=I*3+1;
      GRecords[I].Left:=I+10;
      GRecords[I].Right:=I*2+3;
      GStrings[I]:=AnsiString(StringOfChar('a',(I mod 7)+1));
      GPointerValues[I]:=I*5-7;
      GPointers[I]:=@GPointerValues[I];
      GNested[I]:=I;
      GThread[I]:=I+2;
      GCapA[I]:=I;
      GCapB[I]:=I*2;
      GCapC[I]:=I*3;
    end;
  for I:=0 to 127 do
    begin
      GSingle[I]:=I+1;
      GWritten[I]:=I;
    end;
  SetLength(GReassigned,16);
  SetLength(GOther,16);
  SetLength(GCall,16);
  SetLength(GByRef,16);
  for I:=0 to 15 do
    begin
      GReassigned[I]:=I+10;
      GOther[I]:=I+100;
      GCall[I]:=I;
      GByRef[I]:=I;
    end;
end;

begin
  InitializeData;
  CheckEqual(ScalarRead,24512,'scalar');
  CheckEqual(RecordRead,13056,'record');
  CheckEqual(ManagedRead,507,'managed');
  CheckEqual(PointerRead,39744,'pointer');
  CheckEqual(LocalRead,14432,'local');
  CheckEqual(PressureCap,48768,'pressure-cap');
  CheckEqual(ValueParamRead(GScalar),24512,'value-param');
  CheckEqual(GlobalRead,24512,'global');
  CheckEqual(SingleRead,4096,'single');
  CheckEqual(CheckedRead,24512,'checked');
  CheckEqual(WrittenArray,4064,'written');
  CheckEqual(ReassignedArray,1180,'reassigned');
  CheckEqual(CallClobber,121,'call');
  CheckEqual(ByRefClobber,121,'byref');
  CheckEqual(NestedSplit,4228,'nested');
  CheckEqual(ConstRefRead(GScalar),24512,'constref');
  CheckEqual(ThreadRead,8384,'thread');
  WriteLn('LOOP-BASE:PASS');
end.
