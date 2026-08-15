unit pulse_abi_targets;

{$ifdef FPC}
  {$mode delphi}{$H+}
{$endif}

interface

type
  TRec8 = record
    A: UInt64;
  end;
  TRec16 = record
    A, B: UInt64;
  end;
  TRec24 = record
    A, B, C: UInt64;
  end;
  TRec32 = record
    A, B, C, D: UInt64;
  end;
  TUInt64Func = function(Value: UInt64): UInt64;
  TUInt64Method = function(Value: UInt64): UInt64 of object;
  IAbiCall = interface
    ['{159CC175-F112-4F3D-BF7E-A84A0407BFC2}']
    function Apply(Value: UInt64): UInt64;
  end;
  TAbiObject = class(TInterfacedObject, IAbiCall)
  public
    function Apply(Value: UInt64): UInt64; virtual;
    function MethodApply(Value: UInt64): UInt64;
  end;

function NoArgs: UInt64;
function OneArg(A: UInt64): UInt64;
function FourArgs(A, B, C, D: UInt64): UInt64;
function EightArgs(A, B, C, D, E, F, G, H: UInt64): UInt64;
function MixedArgs(A: UInt64; B: Double; C: Pointer; D: Int32;
  E: Double; F: UInt64): UInt64;
function Record8Value(Value: TRec8): UInt64;
function Record16Value(Value: TRec16): UInt64;
function Record24Value(Value: TRec24): UInt64;
function Record32Value(Value: TRec32): UInt64;
function Record32Const(const Value: TRec32): UInt64;
procedure Record32Var(var Value: TRec32);
function ReturnRecord8(Value: UInt64): TRec8;
function ReturnRecord16(Value: UInt64): TRec16;
function ReturnRecord24(Value: UInt64): TRec24;
function ReturnRecord32(Value: UInt64): TRec32;
function StringValue(Value: UnicodeString): UInt64;
function StringConst(const Value: UnicodeString): UInt64;
function DynamicArrayValue(Value: TArray<Integer>): UInt64;
function DynamicArrayConst(const Value: TArray<Integer>): UInt64;
function OpenArrayConst(const Value: array of Integer): UInt64;
function InvokeCallback(Callback: TUInt64Func; Value: UInt64): UInt64;

implementation

function Mix(Value: UInt64): UInt64; inline;
begin
  Result := (Value xor (Value shr 29)) * UInt64($9E3779B185EBCA87);
end;

function NoArgs: UInt64;
begin
  Result := UInt64($243F6A8885A308D3);
end;

function OneArg(A: UInt64): UInt64;
begin
  Result := Mix(A);
end;

function FourArgs(A, B, C, D: UInt64): UInt64;
begin
  Result := Mix(A + B * 3 + C * 5 + D * 7);
end;

function EightArgs(A, B, C, D, E, F, G, H: UInt64): UInt64;
begin
  Result := Mix(A + B * 3 + C * 5 + D * 7 + E * 11 + F * 13 + G * 17 +
    H * 19);
end;

function MixedArgs(A: UInt64; B: Double; C: Pointer; D: Int32;
  E: Double; F: UInt64): UInt64;
begin
  Result := Mix(A + UInt64(Trunc(B * 1024.0)) + PByte(C)^ + UInt32(D) +
    UInt64(Trunc(E * 2048.0)) + F);
end;

function Record8Value(Value: TRec8): UInt64;
begin
  Result := Mix(Value.A);
end;

function Record16Value(Value: TRec16): UInt64;
begin
  Result := Mix(Value.A + Value.B * 3);
end;

function Record24Value(Value: TRec24): UInt64;
begin
  Result := Mix(Value.A + Value.B * 3 + Value.C * 5);
end;

function Record32Value(Value: TRec32): UInt64;
begin
  Result := Mix(Value.A + Value.B * 3 + Value.C * 5 + Value.D * 7);
end;

function Record32Const(const Value: TRec32): UInt64;
begin
  Result := Mix(Value.A + Value.B * 3 + Value.C * 5 + Value.D * 7);
end;

procedure Record32Var(var Value: TRec32);
begin
  Value.A := Mix(Value.A + Value.D);
  Value.B := Value.B + Value.A;
end;

function ReturnRecord8(Value: UInt64): TRec8;
begin
  Result.A := Mix(Value);
end;

function ReturnRecord16(Value: UInt64): TRec16;
begin
  Result.A := Mix(Value);
  Result.B := Mix(Value + 1);
end;

function ReturnRecord24(Value: UInt64): TRec24;
begin
  Result.A := Mix(Value);
  Result.B := Mix(Value + 1);
  Result.C := Mix(Value + 2);
end;

function ReturnRecord32(Value: UInt64): TRec32;
begin
  Result.A := Mix(Value);
  Result.B := Mix(Value + 1);
  Result.C := Mix(Value + 2);
  Result.D := Mix(Value + 3);
end;

function StringValue(Value: UnicodeString): UInt64;
begin
  Result := UInt64(Length(Value));
  If Value <> '' then
    Result := Result * 257 + Ord(Value[1]) + Ord(Value[Length(Value)]);
end;

function StringConst(const Value: UnicodeString): UInt64;
begin
  Result := UInt64(Length(Value));
  If Value <> '' then
    Result := Result * 257 + Ord(Value[1]) + Ord(Value[Length(Value)]);
end;

function DynamicArrayValue(Value: TArray<Integer>): UInt64;
begin
  Result := UInt64(Length(Value));
  If Length(Value) <> 0 then
    Result := Result * 257 + UInt32(Value[0]) + UInt32(Value[High(Value)]);
end;

function DynamicArrayConst(const Value: TArray<Integer>): UInt64;
begin
  Result := UInt64(Length(Value));
  If Length(Value) <> 0 then
    Result := Result * 257 + UInt32(Value[0]) + UInt32(Value[High(Value)]);
end;

function OpenArrayConst(const Value: array of Integer): UInt64;
begin
  Result := UInt64(Length(Value));
  If Length(Value) <> 0 then
    Result := Result * 257 + UInt32(Value[0]) + UInt32(Value[High(Value)]);
end;

function InvokeCallback(Callback: TUInt64Func; Value: UInt64): UInt64;
begin
  Result := Callback(Value);
end;

function TAbiObject.Apply(Value: UInt64): UInt64;
begin
  Result := Mix(Value + 17);
end;

function TAbiObject.MethodApply(Value: UInt64): UInt64;
begin
  Result := Mix(Value + 31);
end;

end.
