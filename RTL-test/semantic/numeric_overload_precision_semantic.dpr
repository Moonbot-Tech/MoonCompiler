program numeric_overload_precision_semantic;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.Math;

function Pair(A, B: Single): string; overload;
begin
  Result := 'Single';
end;

function Pair(A, B: Double): string; overload;
begin
  Result := 'Double';
end;

function ConstPair(const A, B: Single): string; overload;
begin
  Result := 'Single';
end;

function ConstPair(const A, B: Double): string; overload;
begin
  Result := 'Double';
end;

function VarPair(A: Single; var B: Single): string; overload;
begin
  Result := 'Single';
end;

function VarPair(A: Double; var B: Double): string; overload;
begin
  Result := 'Double';
end;

function OutPair(A: Single; out B: Single): string; overload;
begin
  B := A;
  Result := 'Single';
end;

function OutPair(A: Double; out B: Double): string; overload;
begin
  B := A;
  Result := 'Double';
end;

function FloatOnly(A: Single): string; overload;
begin
  Result := 'Single';
end;

function FloatOnly(A: Double): string; overload;
begin
  Result := 'Double';
end;

function IntegerOrFloat(A: Int64): string; overload;
begin
  Result := 'Int64';
end;

function IntegerOrFloat(A: Double): string; overload;
begin
  Result := 'Double';
end;

function NarrowIntegerOrFloat(A: Integer): string; overload;
begin
  Result := 'Integer';
end;

function NarrowIntegerOrFloat(A: Single): string; overload;
begin
  Result := 'Single';
end;

var
  Value, Actual: Double;
  SmallValue: Single;
  IntegerValue: Integer;
  WideInteger: Int64;
  UnsignedInteger: Cardinal;
  WideUnsigned: UInt64;
  NativeInteger: NativeInt;
  NativeUnsigned: NativeUInt;
  Index, Iterations: Integer;
  Choices: Integer;

procedure RecordChoice(const TestName, Choice: string);
const
  { Delphi 12.2 black-box oracle, not RTL implementation. }
  Expected: array[0..33] of string = (
    'Double',
    'Double',
    'Double',
    'Double',
    'Double',
    'Single',
    'Single',
    'Double',
    'Double',
    'Single',
    'Single',
    'Single',
    'Double',
    'Single',
    'Double',
    'Double',
    'Single',
    'Double',
    'Int64',
    'Int64',
    'Double',
    'Double',
    'Int64',
    'Single',
    'Single',
    'Single',
    'Integer',
    'Double',
    'Double',
    'Single',
    'Double',
    'Single',
    'Double',
    'Single');
begin
  If (Choices > High(Expected)) or (Choice <> Expected[Choices]) then
    raise Exception.Create(TestName + ': ' + Choice);
  Inc(Choices);
end;

begin
  Value := 123.45;
  Actual := Max(0, Value);
  If Actual <> Value then raise Exception.Create('Max narrows Double');
  Actual := Max(Value, 0);
  If Actual <> Value then raise Exception.Create('Max right integer narrows Double');
  Actual := Min(500, Value);
  If Actual <> Value then raise Exception.Create('Min narrows Double');
  Actual := Min(Value, 500);
  If Actual <> Value then raise Exception.Create('Min right integer narrows Double');
  SmallValue := 1.25;
  IntegerValue := 2;
  WideInteger := 3;
  UnsignedInteger := 4;
  WideUnsigned := 5;
  NativeInteger := 6;
  NativeUnsigned := 4;
  Iterations := 0;
  for Index := 0 to Min(IntegerValue - 1, NativeUnsigned - 1) do Inc(Iterations);
  If Iterations <> 2 then raise Exception.Create('Mixed integer Min must remain ordinal');
  Choices := 0;
    RecordChoice('literal, Double', Pair(0, Value));
    RecordChoice('Double, literal', Pair(Value, 0));
    RecordChoice('Integer, Double', Pair(IntegerValue, Value));
    RecordChoice('Double, Integer', Pair(Value, IntegerValue));
    RecordChoice('Int64, Double', Pair(WideInteger, Value));
    RecordChoice('literal, Single', Pair(0, SmallValue));
    RecordChoice('Single, literal', Pair(SmallValue, 0));
    RecordChoice('Single, Double', Pair(SmallValue, Value));
    RecordChoice('Double, Single', Pair(Value, SmallValue));
    RecordChoice('integers', Pair(0, IntegerValue));
    RecordChoice('float-only literal', FloatOnly(0));
    RecordChoice('float-only Integer', FloatOnly(IntegerValue));
    RecordChoice('float-only Int64', FloatOnly(WideInteger));
    RecordChoice('float-only Cardinal', FloatOnly(UnsignedInteger));
    RecordChoice('float-only UInt64', FloatOnly(WideUnsigned));
    RecordChoice('float-only NativeInt', FloatOnly(NativeInteger));
    RecordChoice('float-only wide literal', FloatOnly(2147483648));
    RecordChoice('float-only huge literal', FloatOnly($100000000));
    RecordChoice('integer-or-float literal', IntegerOrFloat(0));
    RecordChoice('integer-or-float Integer', IntegerOrFloat(IntegerValue));
    RecordChoice('integer-or-float UInt64', IntegerOrFloat(WideUnsigned));
    RecordChoice('integer-or-float Double', IntegerOrFloat(Value));
    RecordChoice('integer-or-float Cardinal', IntegerOrFloat(UnsignedInteger));
    RecordChoice('narrow integer-or-float Cardinal', NarrowIntegerOrFloat(UnsignedInteger));
    RecordChoice('narrow integer-or-float UInt64', NarrowIntegerOrFloat(WideUnsigned));
    RecordChoice('narrow integer-or-float Int64', NarrowIntegerOrFloat(WideInteger));
    RecordChoice('narrow integer-or-float Integer', NarrowIntegerOrFloat(IntegerValue));
    RecordChoice('const literal, Double', ConstPair(0, Value));
    RecordChoice('const Double, literal', ConstPair(Value, 0));
    RecordChoice('const literal, Single', ConstPair(0, SmallValue));
    RecordChoice('var Double', VarPair(0, Value));
    RecordChoice('var Single', VarPair(0, SmallValue));
    RecordChoice('out Double', OutPair(0, Actual));
    RecordChoice('out Single', OutPair(0, SmallValue));
  If Choices <> 34 then raise Exception.Create('Incomplete overload matrix');
  WriteLn('NUMERIC_OVERLOAD_PRECISION_PASS');
end.
