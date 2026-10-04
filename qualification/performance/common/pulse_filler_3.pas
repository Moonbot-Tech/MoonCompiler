unit pulse_filler_3;

{ Placement filler: shifts every unit linked after it by a fixed amount of
  unrelated code so the same kernels can be measured at different addresses.
  Loaded with -Fapulse_filler_N; the initialization keeps the bodies linked. }

{$ifdef FPC}{$mode delphi}{$endif}

interface

var
  PulseFillerKeep3: array[0..103] of Pointer;

implementation

function Filler3_0(X: Int64): Int64;
begin
  Result := (X xor 0) * 3 + 1;
end;

function Filler3_1(X: Int64): Int64;
begin
  Result := (X xor 2654435761) * 4 + 8;
end;

function Filler3_2(X: Int64): Int64;
begin
  Result := (X xor 1013904227) * 5 + 15;
end;

function Filler3_3(X: Int64): Int64;
begin
  Result := (X xor 3668339988) * 6 + 22;
end;

function Filler3_4(X: Int64): Int64;
begin
  Result := (X xor 2027808454) * 7 + 29;
end;

function Filler3_5(X: Int64): Int64;
begin
  Result := (X xor 387276920) * 8 + 36;
end;

function Filler3_6(X: Int64): Int64;
begin
  Result := (X xor 3041712681) * 9 + 43;
end;

function Filler3_7(X: Int64): Int64;
begin
  Result := (X xor 1401181147) * 10 + 50;
end;

function Filler3_8(X: Int64): Int64;
begin
  Result := (X xor 4055616908) * 11 + 57;
end;

function Filler3_9(X: Int64): Int64;
begin
  Result := (X xor 2415085374) * 12 + 64;
end;

function Filler3_10(X: Int64): Int64;
begin
  Result := (X xor 774553840) * 13 + 71;
end;

function Filler3_11(X: Int64): Int64;
begin
  Result := (X xor 3428989601) * 14 + 78;
end;

function Filler3_12(X: Int64): Int64;
begin
  Result := (X xor 1788458067) * 15 + 85;
end;

function Filler3_13(X: Int64): Int64;
begin
  Result := (X xor 147926533) * 16 + 92;
end;

function Filler3_14(X: Int64): Int64;
begin
  Result := (X xor 2802362294) * 17 + 99;
end;

function Filler3_15(X: Int64): Int64;
begin
  Result := (X xor 1161830760) * 18 + 106;
end;

function Filler3_16(X: Int64): Int64;
begin
  Result := (X xor 3816266521) * 19 + 113;
end;

function Filler3_17(X: Int64): Int64;
begin
  Result := (X xor 2175734987) * 20 + 120;
end;

function Filler3_18(X: Int64): Int64;
begin
  Result := (X xor 535203453) * 21 + 127;
end;

function Filler3_19(X: Int64): Int64;
begin
  Result := (X xor 3189639214) * 22 + 134;
end;

function Filler3_20(X: Int64): Int64;
begin
  Result := (X xor 1549107680) * 23 + 141;
end;

function Filler3_21(X: Int64): Int64;
begin
  Result := (X xor 4203543441) * 24 + 148;
end;

function Filler3_22(X: Int64): Int64;
begin
  Result := (X xor 2563011907) * 25 + 155;
end;

function Filler3_23(X: Int64): Int64;
begin
  Result := (X xor 922480373) * 26 + 162;
end;

function Filler3_24(X: Int64): Int64;
begin
  Result := (X xor 3576916134) * 27 + 169;
end;

function Filler3_25(X: Int64): Int64;
begin
  Result := (X xor 1936384600) * 28 + 176;
end;

function Filler3_26(X: Int64): Int64;
begin
  Result := (X xor 295853066) * 29 + 183;
end;

function Filler3_27(X: Int64): Int64;
begin
  Result := (X xor 2950288827) * 30 + 190;
end;

function Filler3_28(X: Int64): Int64;
begin
  Result := (X xor 1309757293) * 31 + 197;
end;

function Filler3_29(X: Int64): Int64;
begin
  Result := (X xor 3964193054) * 32 + 204;
end;

function Filler3_30(X: Int64): Int64;
begin
  Result := (X xor 2323661520) * 33 + 211;
end;

function Filler3_31(X: Int64): Int64;
begin
  Result := (X xor 683129986) * 34 + 218;
end;

function Filler3_32(X: Int64): Int64;
begin
  Result := (X xor 3337565747) * 35 + 225;
end;

function Filler3_33(X: Int64): Int64;
begin
  Result := (X xor 1697034213) * 36 + 232;
end;

function Filler3_34(X: Int64): Int64;
begin
  Result := (X xor 56502679) * 37 + 239;
end;

function Filler3_35(X: Int64): Int64;
begin
  Result := (X xor 2710938440) * 38 + 246;
end;

function Filler3_36(X: Int64): Int64;
begin
  Result := (X xor 1070406906) * 39 + 253;
end;

function Filler3_37(X: Int64): Int64;
begin
  Result := (X xor 3724842667) * 40 + 260;
end;

function Filler3_38(X: Int64): Int64;
begin
  Result := (X xor 2084311133) * 41 + 267;
end;

function Filler3_39(X: Int64): Int64;
begin
  Result := (X xor 443779599) * 42 + 274;
end;

function Filler3_40(X: Int64): Int64;
begin
  Result := (X xor 3098215360) * 43 + 281;
end;

function Filler3_41(X: Int64): Int64;
begin
  Result := (X xor 1457683826) * 44 + 288;
end;

function Filler3_42(X: Int64): Int64;
begin
  Result := (X xor 4112119587) * 45 + 295;
end;

function Filler3_43(X: Int64): Int64;
begin
  Result := (X xor 2471588053) * 46 + 302;
end;

function Filler3_44(X: Int64): Int64;
begin
  Result := (X xor 831056519) * 47 + 309;
end;

function Filler3_45(X: Int64): Int64;
begin
  Result := (X xor 3485492280) * 48 + 316;
end;

function Filler3_46(X: Int64): Int64;
begin
  Result := (X xor 1844960746) * 49 + 323;
end;

function Filler3_47(X: Int64): Int64;
begin
  Result := (X xor 204429212) * 50 + 330;
end;

function Filler3_48(X: Int64): Int64;
begin
  Result := (X xor 2858864973) * 51 + 337;
end;

function Filler3_49(X: Int64): Int64;
begin
  Result := (X xor 1218333439) * 52 + 344;
end;

function Filler3_50(X: Int64): Int64;
begin
  Result := (X xor 3872769200) * 53 + 351;
end;

function Filler3_51(X: Int64): Int64;
begin
  Result := (X xor 2232237666) * 54 + 358;
end;

function Filler3_52(X: Int64): Int64;
begin
  Result := (X xor 591706132) * 55 + 365;
end;

function Filler3_53(X: Int64): Int64;
begin
  Result := (X xor 3246141893) * 56 + 372;
end;

function Filler3_54(X: Int64): Int64;
begin
  Result := (X xor 1605610359) * 57 + 379;
end;

function Filler3_55(X: Int64): Int64;
begin
  Result := (X xor 4260046120) * 58 + 386;
end;

function Filler3_56(X: Int64): Int64;
begin
  Result := (X xor 2619514586) * 59 + 393;
end;

function Filler3_57(X: Int64): Int64;
begin
  Result := (X xor 978983052) * 60 + 400;
end;

function Filler3_58(X: Int64): Int64;
begin
  Result := (X xor 3633418813) * 61 + 407;
end;

function Filler3_59(X: Int64): Int64;
begin
  Result := (X xor 1992887279) * 62 + 414;
end;

function Filler3_60(X: Int64): Int64;
begin
  Result := (X xor 352355745) * 63 + 421;
end;

function Filler3_61(X: Int64): Int64;
begin
  Result := (X xor 3006791506) * 64 + 428;
end;

function Filler3_62(X: Int64): Int64;
begin
  Result := (X xor 1366259972) * 65 + 435;
end;

function Filler3_63(X: Int64): Int64;
begin
  Result := (X xor 4020695733) * 66 + 442;
end;

function Filler3_64(X: Int64): Int64;
begin
  Result := (X xor 2380164199) * 67 + 449;
end;

function Filler3_65(X: Int64): Int64;
begin
  Result := (X xor 739632665) * 68 + 456;
end;

function Filler3_66(X: Int64): Int64;
begin
  Result := (X xor 3394068426) * 69 + 463;
end;

function Filler3_67(X: Int64): Int64;
begin
  Result := (X xor 1753536892) * 70 + 470;
end;

function Filler3_68(X: Int64): Int64;
begin
  Result := (X xor 113005358) * 71 + 477;
end;

function Filler3_69(X: Int64): Int64;
begin
  Result := (X xor 2767441119) * 72 + 484;
end;

function Filler3_70(X: Int64): Int64;
begin
  Result := (X xor 1126909585) * 73 + 491;
end;

function Filler3_71(X: Int64): Int64;
begin
  Result := (X xor 3781345346) * 74 + 498;
end;

function Filler3_72(X: Int64): Int64;
begin
  Result := (X xor 2140813812) * 75 + 505;
end;

function Filler3_73(X: Int64): Int64;
begin
  Result := (X xor 500282278) * 76 + 512;
end;

function Filler3_74(X: Int64): Int64;
begin
  Result := (X xor 3154718039) * 77 + 519;
end;

function Filler3_75(X: Int64): Int64;
begin
  Result := (X xor 1514186505) * 78 + 526;
end;

function Filler3_76(X: Int64): Int64;
begin
  Result := (X xor 4168622266) * 79 + 533;
end;

function Filler3_77(X: Int64): Int64;
begin
  Result := (X xor 2528090732) * 80 + 540;
end;

function Filler3_78(X: Int64): Int64;
begin
  Result := (X xor 887559198) * 81 + 547;
end;

function Filler3_79(X: Int64): Int64;
begin
  Result := (X xor 3541994959) * 82 + 554;
end;

function Filler3_80(X: Int64): Int64;
begin
  Result := (X xor 1901463425) * 83 + 561;
end;

function Filler3_81(X: Int64): Int64;
begin
  Result := (X xor 260931891) * 84 + 568;
end;

function Filler3_82(X: Int64): Int64;
begin
  Result := (X xor 2915367652) * 85 + 575;
end;

function Filler3_83(X: Int64): Int64;
begin
  Result := (X xor 1274836118) * 86 + 582;
end;

function Filler3_84(X: Int64): Int64;
begin
  Result := (X xor 3929271879) * 87 + 589;
end;

function Filler3_85(X: Int64): Int64;
begin
  Result := (X xor 2288740345) * 88 + 596;
end;

function Filler3_86(X: Int64): Int64;
begin
  Result := (X xor 648208811) * 89 + 603;
end;

function Filler3_87(X: Int64): Int64;
begin
  Result := (X xor 3302644572) * 90 + 610;
end;

function Filler3_88(X: Int64): Int64;
begin
  Result := (X xor 1662113038) * 91 + 617;
end;

function Filler3_89(X: Int64): Int64;
begin
  Result := (X xor 21581504) * 92 + 624;
end;

function Filler3_90(X: Int64): Int64;
begin
  Result := (X xor 2676017265) * 93 + 631;
end;

function Filler3_91(X: Int64): Int64;
begin
  Result := (X xor 1035485731) * 94 + 638;
end;

function Filler3_92(X: Int64): Int64;
begin
  Result := (X xor 3689921492) * 95 + 645;
end;

function Filler3_93(X: Int64): Int64;
begin
  Result := (X xor 2049389958) * 96 + 652;
end;

function Filler3_94(X: Int64): Int64;
begin
  Result := (X xor 408858424) * 97 + 659;
end;

function Filler3_95(X: Int64): Int64;
begin
  Result := (X xor 3063294185) * 98 + 666;
end;

function Filler3_96(X: Int64): Int64;
begin
  Result := (X xor 1422762651) * 99 + 673;
end;

function Filler3_97(X: Int64): Int64;
begin
  Result := (X xor 4077198412) * 100 + 680;
end;

function Filler3_98(X: Int64): Int64;
begin
  Result := (X xor 2436666878) * 101 + 687;
end;

function Filler3_99(X: Int64): Int64;
begin
  Result := (X xor 796135344) * 102 + 694;
end;

function Filler3_100(X: Int64): Int64;
begin
  Result := (X xor 3450571105) * 103 + 701;
end;

function Filler3_101(X: Int64): Int64;
begin
  Result := (X xor 1810039571) * 104 + 708;
end;

function Filler3_102(X: Int64): Int64;
begin
  Result := (X xor 169508037) * 105 + 715;
end;

function Filler3_103(X: Int64): Int64;
begin
  Result := (X xor 2823943798) * 106 + 722;
end;

initialization
  PulseFillerKeep3[0] := @Filler3_0;
  PulseFillerKeep3[1] := @Filler3_1;
  PulseFillerKeep3[2] := @Filler3_2;
  PulseFillerKeep3[3] := @Filler3_3;
  PulseFillerKeep3[4] := @Filler3_4;
  PulseFillerKeep3[5] := @Filler3_5;
  PulseFillerKeep3[6] := @Filler3_6;
  PulseFillerKeep3[7] := @Filler3_7;
  PulseFillerKeep3[8] := @Filler3_8;
  PulseFillerKeep3[9] := @Filler3_9;
  PulseFillerKeep3[10] := @Filler3_10;
  PulseFillerKeep3[11] := @Filler3_11;
  PulseFillerKeep3[12] := @Filler3_12;
  PulseFillerKeep3[13] := @Filler3_13;
  PulseFillerKeep3[14] := @Filler3_14;
  PulseFillerKeep3[15] := @Filler3_15;
  PulseFillerKeep3[16] := @Filler3_16;
  PulseFillerKeep3[17] := @Filler3_17;
  PulseFillerKeep3[18] := @Filler3_18;
  PulseFillerKeep3[19] := @Filler3_19;
  PulseFillerKeep3[20] := @Filler3_20;
  PulseFillerKeep3[21] := @Filler3_21;
  PulseFillerKeep3[22] := @Filler3_22;
  PulseFillerKeep3[23] := @Filler3_23;
  PulseFillerKeep3[24] := @Filler3_24;
  PulseFillerKeep3[25] := @Filler3_25;
  PulseFillerKeep3[26] := @Filler3_26;
  PulseFillerKeep3[27] := @Filler3_27;
  PulseFillerKeep3[28] := @Filler3_28;
  PulseFillerKeep3[29] := @Filler3_29;
  PulseFillerKeep3[30] := @Filler3_30;
  PulseFillerKeep3[31] := @Filler3_31;
  PulseFillerKeep3[32] := @Filler3_32;
  PulseFillerKeep3[33] := @Filler3_33;
  PulseFillerKeep3[34] := @Filler3_34;
  PulseFillerKeep3[35] := @Filler3_35;
  PulseFillerKeep3[36] := @Filler3_36;
  PulseFillerKeep3[37] := @Filler3_37;
  PulseFillerKeep3[38] := @Filler3_38;
  PulseFillerKeep3[39] := @Filler3_39;
  PulseFillerKeep3[40] := @Filler3_40;
  PulseFillerKeep3[41] := @Filler3_41;
  PulseFillerKeep3[42] := @Filler3_42;
  PulseFillerKeep3[43] := @Filler3_43;
  PulseFillerKeep3[44] := @Filler3_44;
  PulseFillerKeep3[45] := @Filler3_45;
  PulseFillerKeep3[46] := @Filler3_46;
  PulseFillerKeep3[47] := @Filler3_47;
  PulseFillerKeep3[48] := @Filler3_48;
  PulseFillerKeep3[49] := @Filler3_49;
  PulseFillerKeep3[50] := @Filler3_50;
  PulseFillerKeep3[51] := @Filler3_51;
  PulseFillerKeep3[52] := @Filler3_52;
  PulseFillerKeep3[53] := @Filler3_53;
  PulseFillerKeep3[54] := @Filler3_54;
  PulseFillerKeep3[55] := @Filler3_55;
  PulseFillerKeep3[56] := @Filler3_56;
  PulseFillerKeep3[57] := @Filler3_57;
  PulseFillerKeep3[58] := @Filler3_58;
  PulseFillerKeep3[59] := @Filler3_59;
  PulseFillerKeep3[60] := @Filler3_60;
  PulseFillerKeep3[61] := @Filler3_61;
  PulseFillerKeep3[62] := @Filler3_62;
  PulseFillerKeep3[63] := @Filler3_63;
  PulseFillerKeep3[64] := @Filler3_64;
  PulseFillerKeep3[65] := @Filler3_65;
  PulseFillerKeep3[66] := @Filler3_66;
  PulseFillerKeep3[67] := @Filler3_67;
  PulseFillerKeep3[68] := @Filler3_68;
  PulseFillerKeep3[69] := @Filler3_69;
  PulseFillerKeep3[70] := @Filler3_70;
  PulseFillerKeep3[71] := @Filler3_71;
  PulseFillerKeep3[72] := @Filler3_72;
  PulseFillerKeep3[73] := @Filler3_73;
  PulseFillerKeep3[74] := @Filler3_74;
  PulseFillerKeep3[75] := @Filler3_75;
  PulseFillerKeep3[76] := @Filler3_76;
  PulseFillerKeep3[77] := @Filler3_77;
  PulseFillerKeep3[78] := @Filler3_78;
  PulseFillerKeep3[79] := @Filler3_79;
  PulseFillerKeep3[80] := @Filler3_80;
  PulseFillerKeep3[81] := @Filler3_81;
  PulseFillerKeep3[82] := @Filler3_82;
  PulseFillerKeep3[83] := @Filler3_83;
  PulseFillerKeep3[84] := @Filler3_84;
  PulseFillerKeep3[85] := @Filler3_85;
  PulseFillerKeep3[86] := @Filler3_86;
  PulseFillerKeep3[87] := @Filler3_87;
  PulseFillerKeep3[88] := @Filler3_88;
  PulseFillerKeep3[89] := @Filler3_89;
  PulseFillerKeep3[90] := @Filler3_90;
  PulseFillerKeep3[91] := @Filler3_91;
  PulseFillerKeep3[92] := @Filler3_92;
  PulseFillerKeep3[93] := @Filler3_93;
  PulseFillerKeep3[94] := @Filler3_94;
  PulseFillerKeep3[95] := @Filler3_95;
  PulseFillerKeep3[96] := @Filler3_96;
  PulseFillerKeep3[97] := @Filler3_97;
  PulseFillerKeep3[98] := @Filler3_98;
  PulseFillerKeep3[99] := @Filler3_99;
  PulseFillerKeep3[100] := @Filler3_100;
  PulseFillerKeep3[101] := @Filler3_101;
  PulseFillerKeep3[102] := @Filler3_102;
  PulseFillerKeep3[103] := @Filler3_103;
end.
