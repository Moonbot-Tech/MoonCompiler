program tcallobligation1;

{$mode delphiunicode}
{$R+}{$Q+}{$S-}

uses
  SysUtils;

var
  Fixed: array[0..255] of Byte;
  Smaller: array[0..127] of Byte;
  Dynamic: array of Byte;
  Text: UnicodeString;
  ConvertedLength: SizeInt;

type
  TTenToTwenty = 10..20;

procedure Fail(Code: LongInt);
begin
  Halt(Code);
end;

function PureCheckedLeaf(X,Y: QWord): QWord; noinline;
begin
  Result:=(X xor Y) and $ffff;
end;

function ProvenNarrow(X: QWord): Byte; noinline;
begin
  Result:=X and 255;
end;

function ProvenIndex(X: QWord): Byte; noinline;
begin
  Result:=Fixed[X and 255];
end;

function ProvenWideIndex(X: QWord): QWord; noinline;
begin
  Result:=Fixed[X and 255];
end;

function FloatingAdd(X,Y: Double): Double; noinline;
begin
  Result:=X+Y;
end;

function FloatingMultiply(X,Y: Double): Double; noinline;
begin
  Result:=X*Y;
end;

function FullByteIndex(X: Byte): Byte; noinline;
begin
  Result:=Fixed[X];
end;

function CheckedAdd(X: QWord): QWord; noinline;
begin
  Result:=X+1;
end;

function CheckedNarrow(X: QWord): Byte; noinline;
begin
  Result:=X;
end;

function CheckedIndex(X: QWord): Byte; noinline;
begin
  Result:=Fixed[X];
end;

function CheckedByteIndex(X: Byte): Byte; noinline;
begin
  Result:=Smaller[X];
end;

function CheckedDynamicIndex(X: QWord): Byte; noinline;
begin
  Result:=Dynamic[X];
end;

function CheckedStringIndex(X: QWord): WideChar; noinline;
begin
  Result:=Text[X];
end;

function CheckedSubrange(X: Byte): TTenToTwenty; noinline;
begin
  Result:=X;
end;

function CheckedNegate(X: Int64): Int64; noinline;
begin
  Result:=-X;
end;

function CheckedAbs(X: Int64): Int64; noinline;
begin
  Result:=Abs(X);
end;

function AddOne(X: LongInt): LongInt; inline;
begin
  Result:=X+1;
end;

function FoldedCheckedCall: LongInt; noinline;
begin
  Result:=AddOne(40);
end;

function SumFive(A,B,C,D,E: LongInt): LongInt; inline;
begin
  Result:=A+B+C+D+E;
end;

function FoldedFiveArgCall: LongInt; noinline;
begin
  Result:=SumFive(1,2,3,4,5);
end;

function CalledLeaf(X: QWord): QWord; noinline;
begin
  { These frame witnesses must do work after the call to exclude tail calls. }
  Result:=PureCheckedLeaf(X,17) xor 1;
end;

function InlineCallsLeaf(X: QWord): QWord; inline;
begin
  Result:=PureCheckedLeaf(X,23);
end;

function ExpandedRealCall(X: QWord): QWord; noinline;
begin
  Result:=InlineCallsLeaf(X) xor 1;
end;

function ConvertShortString(const Value: ShortString): RawByteString; noinline;
begin
  Result:=Value;
  ConvertedLength:=Length(Result);
end;

{$S+}
function StackCheckedLeaf(X: QWord): QWord; noinline;
begin
  Result:=X xor 17;
end;
{$S-}

procedure ExpectOverflow;
var
  Caught: Boolean;
begin
  Caught:=False;
  try
    CheckedAdd(High(QWord));
  except
    on E: EIntOverflow do
      Caught:=True;
  end;
  if not Caught then
    Fail(10);
end;

procedure ExpectRangeErrors;
var
  Caught: Boolean;
begin
  Caught:=False;
  try
    CheckedNarrow(256);
  except
    on E: ERangeError do
      Caught:=True;
  end;
  if not Caught then
    Fail(11);

  Caught:=False;
  try
    CheckedIndex(256);
  except
    on E: ERangeError do
      Caught:=True;
  end;
  if not Caught then
    Fail(12);

  Caught:=False;
  try
    CheckedByteIndex(200);
  except
    on E: ERangeError do
      Caught:=True;
  end;
  if not Caught then
    Fail(18);

  Caught:=False;
  try
    CheckedDynamicIndex(1);
  except
    on E: ERangeError do
      Caught:=True;
  end;
  if not Caught then
    Fail(13);

  Caught:=False;
  try
    CheckedStringIndex(2);
  except
    on E: ERangeError do
      Caught:=True;
  end;
  if not Caught then
    Fail(14);

  Caught:=False;
  try
    CheckedSubrange(21);
  except
    on E: ERangeError do
      Caught:=True;
  end;
  if not Caught then
    Fail(15);
end;

procedure ExpectUnaryOverflow;
var
  Caught: Boolean;
begin
  Caught:=False;
  try
    CheckedNegate(Low(Int64));
  except
    on E: EIntOverflow do
      Caught:=True;
  end;
  if not Caught then
    Fail(16);

  Caught:=False;
  try
    CheckedAbs(Low(Int64));
  except
    on E: EIntOverflow do
      Caught:=True;
  end;
  if not Caught then
    Fail(17);
end;

begin
  SetLength(Dynamic,1);
  Dynamic[0]:=91;
  Text:='Z';
  Fixed[255]:=73;
  Smaller[127]:=37;
  if PureCheckedLeaf(47,19)<>60 then
    Fail(1);
  if ProvenNarrow(High(QWord))<>255 then
    Fail(2);
  if ProvenIndex(High(QWord))<>73 then
    Fail(3);
  if ProvenWideIndex(High(QWord))<>73 then
    Fail(19);
  if (FloatingAdd(1.25,2.5)<>3.75) or
     (FloatingMultiply(1.25,2.0)<>2.5) then
    Fail(20);
  if FullByteIndex(255)<>73 then
    Fail(21);
  if FoldedCheckedCall<>41 then
    Fail(4);
  if CalledLeaf(47)<>63 then
    Fail(5);
  if StackCheckedLeaf(47)<>62 then
    Fail(6);
  if FoldedFiveArgCall<>15 then
    Fail(7);
  if ExpandedRealCall(47)<>57 then
    Fail(8);
  if ConvertShortString('late inline ABI')<>'late inline ABI' then
    Fail(22);
  if ConvertedLength<>15 then
    Fail(23);
  ExpectOverflow;
  ExpectRangeErrors;
  ExpectUnaryOverflow;
  WriteLn('CALL_OBLIGATION_OK');
end.
