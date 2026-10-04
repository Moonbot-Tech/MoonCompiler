program tobservablesimplify1;

{$mode delphi}
{$Q+}
{$R+}

uses
  SysUtils;

var
  Calls: Integer;
  A: array of Integer;
  Texts: array of UnicodeString;
  Index,IntValue: Integer;
  Int64Value: Int64;
  UInt64Value: UInt64;
  BoolValue,Raised: Boolean;

function NextInt: Integer; noinline;
begin
  Inc(Calls);
  Result:=123;
end;

function NextWide: WideString; noinline;
begin
  Inc(Calls);
  if Calls=1 then
    Result:='abc'
  else
    Result:='';
end;

function ModSubProbe(Value,Divisor: Integer): Integer; noinline;
begin
  Result:=(Value mod Divisor)-(Value mod Divisor);
end;

function ModXorProbe(Value,Divisor: Integer): Integer; noinline;
begin
  Result:=(Value mod Divisor) xor (Value mod Divisor);
end;

function ModEqualProbe(Value,Divisor: Integer): Boolean; noinline;
begin
  Result:=(Value mod Divisor)=(Value mod Divisor);
end;

function RotateLeftProbe(Value: UInt64; Count: Int64): UInt64; noinline;
begin
  Result:=(Value shl Count) or (Value shr (64-Count));
end;

function RotateRightProbe(Value: UInt64; Count: Int64): UInt64; noinline;
begin
  Result:=(Value shr Count) or (Value shl (64-Count));
end;

procedure CheckRange(Code: Integer);
begin
  if not Raised then
    Halt(Code);
end;

begin
  Calls:=0;
  IntValue:=NextInt mod 1;
  if (Calls<>1) or (IntValue<>0) then
    Halt(1);
  Calls:=0;
  IntValue:=NextInt mod -1;
  if (Calls<>1) or (IntValue<>0) then
    Halt(2);

  Calls:=0;
  BoolValue:=Length(NextWide)=0;
  if (Calls<>1) or BoolValue then
    Halt(3);
  Calls:=0;
  BoolValue:=0<>Length(NextWide);
  if (Calls<>1) or not BoolValue then
    Halt(4);
  Calls:=0;
  BoolValue:=Length(NextWide)>0;
  if (Calls<>1) or not BoolValue then
    Halt(5);
  Calls:=0;
  BoolValue:=Length(NextWide)<=0;
  if (Calls<>1) or BoolValue then
    Halt(6);

  IntValue:=Low(Integer);
  Raised:=False;
  try
    IntValue:=-IntValue-1;
  except
    on EIntOverflow do
      Raised:=True;
  end;
  if not Raised then
    Halt(7);
  Int64Value:=Low(Int64);
  Raised:=False;
  try
    Int64Value:=-Int64Value-1;
  except
    on EIntOverflow do
      Raised:=True;
  end;
  if not Raised then
    Halt(8);

  SetLength(A,1);
  SetLength(Texts,1);
  Index:=2;
  Raised:=False;
  try IntValue:=A[Index]-A[Index]; except on ERangeError do Raised:=True; end;
  CheckRange(9);
  Raised:=False;
  try IntValue:=A[Index] xor A[Index]; except on ERangeError do Raised:=True; end;
  CheckRange(10);
  Raised:=False;
  try BoolValue:=A[Index]=A[Index]; except on ERangeError do Raised:=True; end;
  CheckRange(11);
  Raised:=False;
  try BoolValue:=A[Index]<>A[Index]; except on ERangeError do Raised:=True; end;
  CheckRange(12);
  Raised:=False;
  try BoolValue:=A[Index]<A[Index]; except on ERangeError do Raised:=True; end;
  CheckRange(13);
  Raised:=False;
  try BoolValue:=A[Index]<=A[Index]; except on ERangeError do Raised:=True; end;
  CheckRange(14);
  Raised:=False;
  try BoolValue:=A[Index]>A[Index]; except on ERangeError do Raised:=True; end;
  CheckRange(15);
  Raised:=False;
  try BoolValue:=A[Index]>=A[Index]; except on ERangeError do Raised:=True; end;
  CheckRange(16);

  Raised:=False;
  try IntValue:=A[Index] and 0; except on ERangeError do Raised:=True; end;
  CheckRange(17);
  Raised:=False;
  try IntValue:=A[Index]*0; except on ERangeError do Raised:=True; end;
  CheckRange(18);
  Raised:=False;
  try BoolValue:=Length(Texts[Index])>=0; except on ERangeError do Raised:=True; end;
  CheckRange(19);
{$B+}
  Raised:=False;
  try BoolValue:=False and (A[Index]=0); except on ERangeError do Raised:=True; end;
  CheckRange(20);
  Raised:=False;
  try BoolValue:=True or (A[Index]=0); except on ERangeError do Raised:=True; end;
  CheckRange(21);
{$B-}
  Raised:=False;
  try IntValue:=0 shl A[Index]; except on ERangeError do Raised:=True; end;
  CheckRange(22);

  Raised:=False;
  try IntValue:=ModSubProbe(7,0); except on EDivByZero do Raised:=True; end;
  CheckRange(23);
  Raised:=False;
  try IntValue:=ModXorProbe(7,0); except on EDivByZero do Raised:=True; end;
  CheckRange(24);
  Raised:=False;
  try BoolValue:=ModEqualProbe(7,0); except on EDivByZero do Raised:=True; end;
  CheckRange(25);
  if (ModSubProbe(7,3)<>0) or (ModXorProbe(7,3)<>0) or not ModEqualProbe(7,3) then
    Halt(26);

  Int64Value:=Low(Int64);
  Raised:=False;
  try UInt64Value:=RotateLeftProbe(1,Int64Value); except on EIntOverflow do Raised:=True; end;
  CheckRange(27);
  Raised:=False;
  try UInt64Value:=RotateRightProbe(1,Int64Value); except on EIntOverflow do Raised:=True; end;
  CheckRange(28);
  if (RotateLeftProbe($0123456789ABCDEF,8)<>$23456789ABCDEF01) or
     (RotateLeftProbe($0123456789ABCDEF,63)<>$8091A2B3C4D5E6F7) then
    Halt(29);
  if (RotateRightProbe($0123456789ABCDEF,8)<>$EF0123456789ABCD) or
     (RotateRightProbe($0123456789ABCDEF,63)<>$02468ACF13579BDE) then
    Halt(30);
end.
