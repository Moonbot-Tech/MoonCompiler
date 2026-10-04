program tordinalinterval1;

{$mode delphiunicode}
{$R+}
{$Q+}
{$inline off}

uses
  SysUtils;

type
  TStorage = record
    Values: array[0..127] of Byte;
    Padding: array[128..255] of Byte;
  end;

var
  Fixed: array[0..255] of Byte;
  Storage: TStorage;
  Dynamic: array of Byte;
  Calls: Integer;
  NarrowIndex: Byte;

procedure Fail(const Msg: string);
begin
  WriteLn(Msg);
  Halt(1);
end;

function Produce(Value: QWord): QWord; noinline;
begin
  Inc(Calls);
  Result:=Value;
end;

function MaskIndex(Value: QWord): Byte; noinline;
begin
  Result:=Fixed[Value and 255];
end;

function ModIndex(Value: QWord): Byte; noinline;
begin
  Result:=Fixed[Value mod 256];
end;

function EffectIndex(Value: QWord): Byte; noinline;
begin
  Result:=Fixed[Produce(Value) and 255];
end;

function UnsafeMask(Value: QWord): Byte; noinline;
begin
  Result:=Storage.Values[Value and 511];
end;

function DynamicIndex(Value: QWord): Byte; noinline;
begin
  Result:=Dynamic[Value and 255];
end;

function StoredNarrowIndex: Byte; noinline;
begin
  Result:=Storage.Values[NarrowIndex];
end;

function WideIndex(const Value: UInt128): Byte; noinline;
begin
  Result:=Storage.Values[Byte((Value shr 1) shr 56)];
end;

function MaskedFloat32(Value: QWord): Double; noinline;
begin
  Result:=Value and $7fffffff;
end;

function MaskedFloat64(Value: QWord): Double; noinline;
begin
  Result:=Value and $7fffffffffffffff;
end;

function WideFloat(Value: QWord): Double; noinline;
begin
  Result:=Value;
end;

function CheckedAdd(Value: QWord): QWord; noinline;
begin
  Result:=Value+1;
end;

procedure ExpectRangeError(const Name: string; Which: Integer);
var
  Caught: Boolean;
  Value: Byte;
  Wide: UInt128;
begin
  Caught:=False;
  try
    case Which of
      0: Value:=UnsafeMask(256);
      1: Value:=DynamicIndex(20);
      2: Value:=StoredNarrowIndex;
      3:
        begin
          Wide:=UInt128(High(QWord)) shl 1;
          Value:=WideIndex(Wide);
        end;
    end;
  except
    on E: ERangeError do
      Caught:=True;
  end;
  if not Caught then
    Fail(Name+' did not raise ERangeError: '+IntToStr(Value));
end;

procedure ExpectOverflow;
var
  Caught: Boolean;
  Value: QWord;
begin
  Caught:=False;
  try
    Value:=CheckedAdd(High(QWord));
  except
    on E: EIntOverflow do
      Caught:=True;
  end;
  if not Caught then
    Fail('checked add did not raise EIntOverflow: '+UIntToStr(Value));
end;

var
  Input: Byte;
begin
  Fixed[255]:=73;
  Storage.Padding[255]:=99;
  SetLength(Dynamic,16);

  if MaskIndex(High(QWord))<>73 then
    Fail('masked fixed index');
  if ModIndex(High(QWord))<>73 then
    Fail('modulo fixed index');
  Calls:=0;
  if EffectIndex(High(QWord))<>73 then
    Fail('effectful masked index');
  if Calls<>1 then
    Fail('effectful operand evaluated '+IntToStr(Calls)+' times');

  Input:=200;
  NarrowIndex:=Input;
  ExpectRangeError('wide mask',0);
  ExpectRangeError('dynamic length',1);
  ExpectRangeError('stored narrow index',2);
  ExpectRangeError('UInt128 shift',3);
  ExpectOverflow;

  if MaskedFloat32(High(QWord))<>2147483647.0 then
    Fail('masked UInt32-sized conversion');
  if MaskedFloat64(High(QWord))<>9223372036854775807.0 then
    Fail('masked Int64-sized conversion');
  if WideFloat(High(QWord))<>18446744073709551615.0 then
    Fail('full UInt64 conversion');
  WriteLn('ORDINAL_INTERVAL_OK');
end.
