{ %OPT=-O3 }
program tintpromotion1;

{$mode delphi}
{$Q+}
{$R+}

function Kind(Value: Integer): Byte; overload;
begin
  Result := 1;
end;

function Kind(Value: Cardinal): Byte; overload;
begin
  Result := 2;
end;

function Kind(Value: Int64): Byte; overload;
begin
  Result := 3;
end;

function Kind(Value: UInt64): Byte; overload;
begin
  Result := 4;
end;

function Kind(Value: Byte): Byte; overload;
begin
  Result := 5;
end;

function Kind(Value: Word): Byte; overload;
begin
  Result := 6;
end;

function Kind(Value: SmallInt): Byte; overload;
begin
  Result := 7;
end;

function Kind(Value: ShortInt): Byte; overload;
begin
  Result := 8;
end;

type
  TUsage = (u0, u1, u2, u3, u4, u5, u6, u7, u8);
  TUsages = set of TUsage;

const
  UntypedOne = 1;
  TypedByteOne: Byte = 1;
  TypedWordOne: Word = 1;
  TypedSmallIntOne: SmallInt = 1;
  TypedSmallInt256: SmallInt = 256;
  TypedIntegerMinusOne: Integer = -1;
  Untyped256 = 256;
  NamedSmallIntCast = SmallInt(1);
  UntypedNegOne = -1;
  ExplicitShortNegOne = ShortInt(-1);
  TypedShortNegOne: ShortInt = -1;

var
  B1, B2: Byte;
  SI: ShortInt;
  S: SmallInt;
  W1, W2: Word;
  I: Integer;
  C: Cardinal;
  P, LoopCount: PtrInt;
  U: TUsages;
begin
  B1 := 2;
  B2 := 1;
  SI := 2;
  S := 2;
  W1 := 2;
  W2 := 1;
  I := 2;
  C := 1;
  If Kind(B1 + B2) <> 1 then Halt(1);
  If Kind(B1 - B2) <> 1 then Halt(2);
  If Kind(B1 * B2) <> 1 then Halt(3);
  If Kind(B1 div B2) <> 1 then Halt(4);
  If Kind(B1 mod B2) <> 1 then Halt(5);
  If Kind(B1 and B2) <> 5 then Halt(6);
  If Kind(W1 + W2) <> 1 then Halt(7);
  If Kind(W1 - W2) <> 1 then Halt(8);
  If Kind(C + C) <> 2 then Halt(9);
  If Kind(C - C) <> 2 then Halt(10);
  If Kind(C * C) <> 2 then Halt(11);
  If Kind(C div C) <> 2 then Halt(12);
  If Kind(C mod C) <> 2 then Halt(13);
  If Kind(I + C) <> 3 then Halt(14);
  If Kind(I - C) <> 3 then Halt(15);
  If Kind(C - I) <> 3 then Halt(16);
  If Kind(W1 * W2) <> 1 then Halt(17);
  If Kind(W1 div W2) <> 1 then Halt(18);
  If Kind(W1 mod W2) <> 1 then Halt(19);
  If Kind(W1 and W2) <> 6 then Halt(20);
  If Kind(W1 or W2) <> 6 then Halt(21);
  If Kind(W1 xor W2) <> 6 then Halt(22);
  If Kind(C and C) <> 2 then Halt(23);
  If Kind(C or C) <> 2 then Halt(24);
  If Kind(C xor C) <> 2 then Halt(25);
  If Kind(I * C) <> 3 then Halt(26);
  If Kind(I div C) <> 3 then Halt(27);
  If Kind(I mod C) <> 3 then Halt(28);
  If Kind(I and C) <> 2 then Halt(29);
  If Kind(I or C) <> 3 then Halt(30);
  If Kind(I xor C) <> 3 then Halt(31);
  If Kind(S + B1) <> 1 then Halt(32);
  If Kind(S div W1) <> 1 then Halt(33);
  W1 := $81ff;
  If Kind(W1 and $ff) <> 6 then Halt(34);
  U := TUsages(W1 and $ff);
  If not (u0 in U) or not (u7 in U) or (u8 in U) then Halt(35);
  If Kind(B1 and $01) <> 5 then Halt(36);
  If Kind($01 and B1) <> 5 then Halt(37);
  If Kind(B1 or $01) <> 5 then Halt(38);
  If Kind($01 or B1) <> 5 then Halt(39);
  If Kind(B1 xor $01) <> 5 then Halt(40);
  If Kind($01 xor B1) <> 5 then Halt(41);
  If Kind(W1 and $01) <> 6 then Halt(42);
  If Kind($01 and W1) <> 6 then Halt(43);
  If Kind(W1 or $01) <> 6 then Halt(44);
  If Kind($01 or W1) <> 6 then Halt(45);
  If Kind(W1 xor $01) <> 6 then Halt(46);
  If Kind($01 xor W1) <> 6 then Halt(47);
  If Kind(B1 or $100) <> 7 then Halt(48);
  If Kind(B1 or $ffff) <> 6 then Halt(49);
  If Kind(B1 or $10000) <> 1 then Halt(50);
  If Kind(W1 or $100) <> 6 then Halt(51);
  If Kind(W1 or $ffff) <> 6 then Halt(52);
  If Kind(W1 or $10000) <> 1 then Halt(53);
  If Kind(S and $01) <> 7 then Halt(54);
  If Kind(S or $100) <> 7 then Halt(55);
  If Kind(S or $ffff) <> 1 then Halt(56);
  If Kind(S or $10000) <> 1 then Halt(57);
  U := TUsages(W1 or $01);
  If not (u0 in U) then Halt(58);
  B1 := 0;
  P := B1 - 1;
  If P <> -1 then Halt(59);
  LoopCount := 0;
  for P := 0 to B1 - 1 do
    Inc(LoopCount);
  If LoopCount <> 0 then Halt(60);
  If Kind(B1 and UntypedOne) <> 5 then Halt(61);
  If Kind(B1 and TypedByteOne) <> 5 then Halt(62);
  If Kind(B1 and TypedWordOne) <> 6 then Halt(63);
  If Kind(I and $ffffffff) <> 2 then Halt(64);
  If Kind($ffffffff and I) <> 2 then Halt(65);
  If Kind(C and -1) <> 2 then Halt(66);
  If Kind(-1 and C) <> 2 then Halt(67);
  If Kind(C and TypedIntegerMinusOne) <> 2 then Halt(68);
  If Kind(UInt64(C) and -1) <> 4 then Halt(69);
  If Kind(UInt64(C) and TypedIntegerMinusOne) <> 4 then Halt(70);
  If Kind(B1 and TypedSmallIntOne) <> 7 then Halt(76);
  If Kind(B1 and SmallInt(1)) <> 7 then Halt(77);
  If Kind(S and TypedWordOne) <> 1 then Halt(78);
  If Kind(SI and UntypedOne) <> 8 then Halt(79);
  If Kind(SI and TypedByteOne) <> 7 then Halt(80);
  If Kind(SI and Byte(1)) <> 7 then Halt(81);
  If Kind(W1 or Untyped256) <> 6 then Halt(82);
  If Kind(W1 or TypedSmallIntOne) <> 1 then Halt(83);
  If Kind(W1 or TypedSmallInt256) <> 1 then Halt(84);
  If Kind(W1 or SmallInt(1)) <> 1 then Halt(85);
  If Kind(W1 or NamedSmallIntCast) <> 1 then Halt(86);
  If Kind(C + 1) <> 2 then Halt(87);
  If Kind(1 + C) <> 2 then Halt(88);
  If Kind(C - 1) <> 2 then Halt(89);
  If Kind(1 - C) <> 2 then Halt(90);
  If Kind(C * 1) <> 2 then Halt(91);
  If Kind(B1 and -1) <> 7 then Halt(92);
  If Kind(B1 or -1) <> 7 then Halt(94);
  If Kind(B1 xor -1) <> 7 then Halt(96);
  If Kind(UntypedNegOne and B1) <> 7 then Halt(98);
  If Kind(UntypedNegOne or B1) <> 7 then Halt(99);
  If Kind(UntypedNegOne xor B1) <> 7 then Halt(100);
  If Kind(ExplicitShortNegOne and B1) <> 7 then Halt(101);
  If Kind(ExplicitShortNegOne or B1) <> 7 then Halt(102);
  If Kind(ExplicitShortNegOne xor B1) <> 7 then Halt(103);
  If Kind(TypedShortNegOne and B1) <> 7 then Halt(104);
  If Kind(TypedShortNegOne or B1) <> 7 then Halt(105);
  If Kind(TypedShortNegOne xor B1) <> 7 then Halt(106);
  If Kind(B1 or TypedSmallIntOne) <> 7 then Halt(107);
  If Kind(B1 xor TypedSmallIntOne) <> 7 then Halt(108);
  If Kind(B1 and UntypedNegOne) <> 7 then Halt(109);
  If Kind(B1 or UntypedNegOne) <> 7 then Halt(110);
  If Kind(B1 xor UntypedNegOne) <> 7 then Halt(111);
  If Kind(B1 and ExplicitShortNegOne) <> 7 then Halt(112);
  If Kind(B1 or ExplicitShortNegOne) <> 7 then Halt(113);
  If Kind(B1 xor ExplicitShortNegOne) <> 7 then Halt(114);
  If Kind(B1 and TypedShortNegOne) <> 7 then Halt(115);
  If Kind(B1 or TypedShortNegOne) <> 7 then Halt(116);
  If Kind(B1 xor TypedShortNegOne) <> 7 then Halt(117);
end.
