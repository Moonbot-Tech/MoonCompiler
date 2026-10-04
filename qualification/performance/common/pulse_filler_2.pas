unit pulse_filler_2;

{ Placement filler: shifts every unit linked after it by a fixed amount of
  unrelated code so the same kernels can be measured at different addresses.
  Loaded with -Fapulse_filler_N; the initialization keeps the bodies linked. }

{$ifdef FPC}{$mode delphi}{$endif}

interface

var
  PulseFillerKeep2: array[0..55] of Pointer;

implementation

function Filler2_0(X: Int64): Int64;
begin
  Result := (X xor 0) * 3 + 1;
end;

function Filler2_1(X: Int64): Int64;
begin
  Result := (X xor 2654435761) * 4 + 8;
end;

function Filler2_2(X: Int64): Int64;
begin
  Result := (X xor 1013904227) * 5 + 15;
end;

function Filler2_3(X: Int64): Int64;
begin
  Result := (X xor 3668339988) * 6 + 22;
end;

function Filler2_4(X: Int64): Int64;
begin
  Result := (X xor 2027808454) * 7 + 29;
end;

function Filler2_5(X: Int64): Int64;
begin
  Result := (X xor 387276920) * 8 + 36;
end;

function Filler2_6(X: Int64): Int64;
begin
  Result := (X xor 3041712681) * 9 + 43;
end;

function Filler2_7(X: Int64): Int64;
begin
  Result := (X xor 1401181147) * 10 + 50;
end;

function Filler2_8(X: Int64): Int64;
begin
  Result := (X xor 4055616908) * 11 + 57;
end;

function Filler2_9(X: Int64): Int64;
begin
  Result := (X xor 2415085374) * 12 + 64;
end;

function Filler2_10(X: Int64): Int64;
begin
  Result := (X xor 774553840) * 13 + 71;
end;

function Filler2_11(X: Int64): Int64;
begin
  Result := (X xor 3428989601) * 14 + 78;
end;

function Filler2_12(X: Int64): Int64;
begin
  Result := (X xor 1788458067) * 15 + 85;
end;

function Filler2_13(X: Int64): Int64;
begin
  Result := (X xor 147926533) * 16 + 92;
end;

function Filler2_14(X: Int64): Int64;
begin
  Result := (X xor 2802362294) * 17 + 99;
end;

function Filler2_15(X: Int64): Int64;
begin
  Result := (X xor 1161830760) * 18 + 106;
end;

function Filler2_16(X: Int64): Int64;
begin
  Result := (X xor 3816266521) * 19 + 113;
end;

function Filler2_17(X: Int64): Int64;
begin
  Result := (X xor 2175734987) * 20 + 120;
end;

function Filler2_18(X: Int64): Int64;
begin
  Result := (X xor 535203453) * 21 + 127;
end;

function Filler2_19(X: Int64): Int64;
begin
  Result := (X xor 3189639214) * 22 + 134;
end;

function Filler2_20(X: Int64): Int64;
begin
  Result := (X xor 1549107680) * 23 + 141;
end;

function Filler2_21(X: Int64): Int64;
begin
  Result := (X xor 4203543441) * 24 + 148;
end;

function Filler2_22(X: Int64): Int64;
begin
  Result := (X xor 2563011907) * 25 + 155;
end;

function Filler2_23(X: Int64): Int64;
begin
  Result := (X xor 922480373) * 26 + 162;
end;

function Filler2_24(X: Int64): Int64;
begin
  Result := (X xor 3576916134) * 27 + 169;
end;

function Filler2_25(X: Int64): Int64;
begin
  Result := (X xor 1936384600) * 28 + 176;
end;

function Filler2_26(X: Int64): Int64;
begin
  Result := (X xor 295853066) * 29 + 183;
end;

function Filler2_27(X: Int64): Int64;
begin
  Result := (X xor 2950288827) * 30 + 190;
end;

function Filler2_28(X: Int64): Int64;
begin
  Result := (X xor 1309757293) * 31 + 197;
end;

function Filler2_29(X: Int64): Int64;
begin
  Result := (X xor 3964193054) * 32 + 204;
end;

function Filler2_30(X: Int64): Int64;
begin
  Result := (X xor 2323661520) * 33 + 211;
end;

function Filler2_31(X: Int64): Int64;
begin
  Result := (X xor 683129986) * 34 + 218;
end;

function Filler2_32(X: Int64): Int64;
begin
  Result := (X xor 3337565747) * 35 + 225;
end;

function Filler2_33(X: Int64): Int64;
begin
  Result := (X xor 1697034213) * 36 + 232;
end;

function Filler2_34(X: Int64): Int64;
begin
  Result := (X xor 56502679) * 37 + 239;
end;

function Filler2_35(X: Int64): Int64;
begin
  Result := (X xor 2710938440) * 38 + 246;
end;

function Filler2_36(X: Int64): Int64;
begin
  Result := (X xor 1070406906) * 39 + 253;
end;

function Filler2_37(X: Int64): Int64;
begin
  Result := (X xor 3724842667) * 40 + 260;
end;

function Filler2_38(X: Int64): Int64;
begin
  Result := (X xor 2084311133) * 41 + 267;
end;

function Filler2_39(X: Int64): Int64;
begin
  Result := (X xor 443779599) * 42 + 274;
end;

function Filler2_40(X: Int64): Int64;
begin
  Result := (X xor 3098215360) * 43 + 281;
end;

function Filler2_41(X: Int64): Int64;
begin
  Result := (X xor 1457683826) * 44 + 288;
end;

function Filler2_42(X: Int64): Int64;
begin
  Result := (X xor 4112119587) * 45 + 295;
end;

function Filler2_43(X: Int64): Int64;
begin
  Result := (X xor 2471588053) * 46 + 302;
end;

function Filler2_44(X: Int64): Int64;
begin
  Result := (X xor 831056519) * 47 + 309;
end;

function Filler2_45(X: Int64): Int64;
begin
  Result := (X xor 3485492280) * 48 + 316;
end;

function Filler2_46(X: Int64): Int64;
begin
  Result := (X xor 1844960746) * 49 + 323;
end;

function Filler2_47(X: Int64): Int64;
begin
  Result := (X xor 204429212) * 50 + 330;
end;

function Filler2_48(X: Int64): Int64;
begin
  Result := (X xor 2858864973) * 51 + 337;
end;

function Filler2_49(X: Int64): Int64;
begin
  Result := (X xor 1218333439) * 52 + 344;
end;

function Filler2_50(X: Int64): Int64;
begin
  Result := (X xor 3872769200) * 53 + 351;
end;

function Filler2_51(X: Int64): Int64;
begin
  Result := (X xor 2232237666) * 54 + 358;
end;

function Filler2_52(X: Int64): Int64;
begin
  Result := (X xor 591706132) * 55 + 365;
end;

function Filler2_53(X: Int64): Int64;
begin
  Result := (X xor 3246141893) * 56 + 372;
end;

function Filler2_54(X: Int64): Int64;
begin
  Result := (X xor 1605610359) * 57 + 379;
end;

function Filler2_55(X: Int64): Int64;
begin
  Result := (X xor 4260046120) * 58 + 386;
end;

initialization
  PulseFillerKeep2[0] := @Filler2_0;
  PulseFillerKeep2[1] := @Filler2_1;
  PulseFillerKeep2[2] := @Filler2_2;
  PulseFillerKeep2[3] := @Filler2_3;
  PulseFillerKeep2[4] := @Filler2_4;
  PulseFillerKeep2[5] := @Filler2_5;
  PulseFillerKeep2[6] := @Filler2_6;
  PulseFillerKeep2[7] := @Filler2_7;
  PulseFillerKeep2[8] := @Filler2_8;
  PulseFillerKeep2[9] := @Filler2_9;
  PulseFillerKeep2[10] := @Filler2_10;
  PulseFillerKeep2[11] := @Filler2_11;
  PulseFillerKeep2[12] := @Filler2_12;
  PulseFillerKeep2[13] := @Filler2_13;
  PulseFillerKeep2[14] := @Filler2_14;
  PulseFillerKeep2[15] := @Filler2_15;
  PulseFillerKeep2[16] := @Filler2_16;
  PulseFillerKeep2[17] := @Filler2_17;
  PulseFillerKeep2[18] := @Filler2_18;
  PulseFillerKeep2[19] := @Filler2_19;
  PulseFillerKeep2[20] := @Filler2_20;
  PulseFillerKeep2[21] := @Filler2_21;
  PulseFillerKeep2[22] := @Filler2_22;
  PulseFillerKeep2[23] := @Filler2_23;
  PulseFillerKeep2[24] := @Filler2_24;
  PulseFillerKeep2[25] := @Filler2_25;
  PulseFillerKeep2[26] := @Filler2_26;
  PulseFillerKeep2[27] := @Filler2_27;
  PulseFillerKeep2[28] := @Filler2_28;
  PulseFillerKeep2[29] := @Filler2_29;
  PulseFillerKeep2[30] := @Filler2_30;
  PulseFillerKeep2[31] := @Filler2_31;
  PulseFillerKeep2[32] := @Filler2_32;
  PulseFillerKeep2[33] := @Filler2_33;
  PulseFillerKeep2[34] := @Filler2_34;
  PulseFillerKeep2[35] := @Filler2_35;
  PulseFillerKeep2[36] := @Filler2_36;
  PulseFillerKeep2[37] := @Filler2_37;
  PulseFillerKeep2[38] := @Filler2_38;
  PulseFillerKeep2[39] := @Filler2_39;
  PulseFillerKeep2[40] := @Filler2_40;
  PulseFillerKeep2[41] := @Filler2_41;
  PulseFillerKeep2[42] := @Filler2_42;
  PulseFillerKeep2[43] := @Filler2_43;
  PulseFillerKeep2[44] := @Filler2_44;
  PulseFillerKeep2[45] := @Filler2_45;
  PulseFillerKeep2[46] := @Filler2_46;
  PulseFillerKeep2[47] := @Filler2_47;
  PulseFillerKeep2[48] := @Filler2_48;
  PulseFillerKeep2[49] := @Filler2_49;
  PulseFillerKeep2[50] := @Filler2_50;
  PulseFillerKeep2[51] := @Filler2_51;
  PulseFillerKeep2[52] := @Filler2_52;
  PulseFillerKeep2[53] := @Filler2_53;
  PulseFillerKeep2[54] := @Filler2_54;
  PulseFillerKeep2[55] := @Filler2_55;
end.
