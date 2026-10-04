program live_register;

{$mode delphiunicode}{$H+}{$Q-}{$R-}

uses SysUtils;

var Sink: UInt64;

function Hash3(A0: Byte; A1: Integer; A2: Int64): UInt64; noinline;
begin
  Result := UInt64($CBF29CE484222325);
  Result := (Result xor UInt64(A0)) * UInt64($100000001B3);
  Result := (Result xor UInt64(A1)) * UInt64($100000001B3);
  Result := (Result xor UInt64(A2)) * UInt64($100000001B3);
end;

function Hash4(A0: Byte; A1: Integer; A2: Int64; A3: Cardinal): UInt64; noinline;
begin
  Result := UInt64($CBF29CE484222325);
  Result := (Result xor UInt64(A0)) * UInt64($100000001B3);
  Result := (Result xor UInt64(A1)) * UInt64($100000001B3);
  Result := (Result xor UInt64(A2)) * UInt64($100000001B3);
  Result := (Result xor UInt64(A3)) * UInt64($100000001B3);
end;

function KeepReturn(A, B: UInt64): UInt64; noinline;
begin
  Result := UInt64($9E3779B185EBCA87);
  Sink := A * UInt64($9E3779B185EBCA87);
  Sink := Sink xor (B * UInt64($9E3779B185EBCA87));
end;

function WidthRoundTrip(P: PSmallInt; A1, A2: Int64): Int64; noinline;
var X: SmallInt; Acc, C: Int64; Y: Cardinal;
begin
  C := A1; Acc := A1 xor A2; X := P^; Y := Cardinal(A2);
  if A2 > 3 then Inc(C);
  if X < Y then Acc := Acc + C;
  if C > 2 then Inc(Acc, Y);
  Result := Acc + C;
end;

var Zero: SmallInt;

begin
  Zero := 0;
  WriteLn(IntToHex(Hash3(Byte(5), Integer(24), Int64(43)), 16));
  WriteLn(IntToHex(Hash4(Byte(5), Integer(24), Int64(43), Cardinal(62)), 16));
  WriteLn(IntToHex(KeepReturn(5, 7), 16));
  WriteLn(IntToHex(Sink, 16));
  WriteLn(WidthRoundTrip(@Zero, 1, -4));
end.
