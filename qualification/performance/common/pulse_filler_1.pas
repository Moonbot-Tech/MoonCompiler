unit pulse_filler_1;

{ Placement filler: shifts every unit linked after it by a fixed amount of
  unrelated code so the same kernels can be measured at different addresses.
  Loaded with -Fapulse_filler_N; the initialization keeps the bodies linked. }

{$ifdef FPC}{$mode delphi}{$endif}

interface

var
  PulseFillerKeep1: array[0..23] of Pointer;

implementation

function Filler1_0(X: Int64): Int64;
begin
  Result := (X xor 0) * 3 + 1;
end;

function Filler1_1(X: Int64): Int64;
begin
  Result := (X xor 2654435761) * 4 + 8;
end;

function Filler1_2(X: Int64): Int64;
begin
  Result := (X xor 1013904227) * 5 + 15;
end;

function Filler1_3(X: Int64): Int64;
begin
  Result := (X xor 3668339988) * 6 + 22;
end;

function Filler1_4(X: Int64): Int64;
begin
  Result := (X xor 2027808454) * 7 + 29;
end;

function Filler1_5(X: Int64): Int64;
begin
  Result := (X xor 387276920) * 8 + 36;
end;

function Filler1_6(X: Int64): Int64;
begin
  Result := (X xor 3041712681) * 9 + 43;
end;

function Filler1_7(X: Int64): Int64;
begin
  Result := (X xor 1401181147) * 10 + 50;
end;

function Filler1_8(X: Int64): Int64;
begin
  Result := (X xor 4055616908) * 11 + 57;
end;

function Filler1_9(X: Int64): Int64;
begin
  Result := (X xor 2415085374) * 12 + 64;
end;

function Filler1_10(X: Int64): Int64;
begin
  Result := (X xor 774553840) * 13 + 71;
end;

function Filler1_11(X: Int64): Int64;
begin
  Result := (X xor 3428989601) * 14 + 78;
end;

function Filler1_12(X: Int64): Int64;
begin
  Result := (X xor 1788458067) * 15 + 85;
end;

function Filler1_13(X: Int64): Int64;
begin
  Result := (X xor 147926533) * 16 + 92;
end;

function Filler1_14(X: Int64): Int64;
begin
  Result := (X xor 2802362294) * 17 + 99;
end;

function Filler1_15(X: Int64): Int64;
begin
  Result := (X xor 1161830760) * 18 + 106;
end;

function Filler1_16(X: Int64): Int64;
begin
  Result := (X xor 3816266521) * 19 + 113;
end;

function Filler1_17(X: Int64): Int64;
begin
  Result := (X xor 2175734987) * 20 + 120;
end;

function Filler1_18(X: Int64): Int64;
begin
  Result := (X xor 535203453) * 21 + 127;
end;

function Filler1_19(X: Int64): Int64;
begin
  Result := (X xor 3189639214) * 22 + 134;
end;

function Filler1_20(X: Int64): Int64;
begin
  Result := (X xor 1549107680) * 23 + 141;
end;

function Filler1_21(X: Int64): Int64;
begin
  Result := (X xor 4203543441) * 24 + 148;
end;

function Filler1_22(X: Int64): Int64;
begin
  Result := (X xor 2563011907) * 25 + 155;
end;

function Filler1_23(X: Int64): Int64;
begin
  Result := (X xor 922480373) * 26 + 162;
end;

initialization
  PulseFillerKeep1[0] := @Filler1_0;
  PulseFillerKeep1[1] := @Filler1_1;
  PulseFillerKeep1[2] := @Filler1_2;
  PulseFillerKeep1[3] := @Filler1_3;
  PulseFillerKeep1[4] := @Filler1_4;
  PulseFillerKeep1[5] := @Filler1_5;
  PulseFillerKeep1[6] := @Filler1_6;
  PulseFillerKeep1[7] := @Filler1_7;
  PulseFillerKeep1[8] := @Filler1_8;
  PulseFillerKeep1[9] := @Filler1_9;
  PulseFillerKeep1[10] := @Filler1_10;
  PulseFillerKeep1[11] := @Filler1_11;
  PulseFillerKeep1[12] := @Filler1_12;
  PulseFillerKeep1[13] := @Filler1_13;
  PulseFillerKeep1[14] := @Filler1_14;
  PulseFillerKeep1[15] := @Filler1_15;
  PulseFillerKeep1[16] := @Filler1_16;
  PulseFillerKeep1[17] := @Filler1_17;
  PulseFillerKeep1[18] := @Filler1_18;
  PulseFillerKeep1[19] := @Filler1_19;
  PulseFillerKeep1[20] := @Filler1_20;
  PulseFillerKeep1[21] := @Filler1_21;
  PulseFillerKeep1[22] := @Filler1_22;
  PulseFillerKeep1[23] := @Filler1_23;
end.
