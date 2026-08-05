{ %OPT=-O3 }
program tunarysign1;

{$ifdef FPC}
  {$mode delphi}
{$endif FPC}

function Kind(Value: Byte): Byte; overload;
begin
  Result := 1;
end;

function Kind(Value: Word): Byte; overload;
begin
  Result := 2;
end;

function Kind(Value: ShortInt): Byte; overload;
begin
  Result := 3;
end;

function Kind(Value: SmallInt): Byte; overload;
begin
  Result := 4;
end;

function Kind(Value: Integer): Byte; overload;
begin
  Result := 5;
end;

function Kind(Value: Cardinal): Byte; overload;
begin
  Result := 6;
end;

function Kind(Value: Int64): Byte; overload;
begin
  Result := 7;
end;

function Kind(Value: UInt64): Byte; overload;
begin
  Result := 8;
end;

var
  B: Byte;
  W: Word;
  C: Cardinal;
  U: UInt64;
begin
  B := 2;
  W := 2;
  C := 2;
  U := 2;

  If Kind(-B) <> 5 then Halt(1);
  If Kind(-W) <> 5 then Halt(2);
  If Kind(-C) <> 7 then Halt(3);
  If Kind(-U) <> 8 then Halt(26);
  If Kind(+B) <> 5 then Halt(27);
  If Kind(+W) <> 5 then Halt(28);
  If Kind(+C) <> 6 then Halt(29);
  If Kind(+U) <> 8 then Halt(30);
  If Kind(-Byte(1)) <> 3 then Halt(4);
  If Kind(-(B and 1)) <> 5 then Halt(5);
  If Kind(-(1)) <> 3 then Halt(6);
  If Kind(-(-1)) <> 3 then Halt(7);
  If Kind(-(-128)) <> 1 then Halt(46);
  If Kind(-(-32768)) <> 2 then Halt(47);
  If Kind(-Word(1)) <> 3 then Halt(48);
  If Kind(-SmallInt(1)) <> 3 then Halt(49);
  If Kind(-Integer(1)) <> 3 then Halt(50);
  If Kind(-Cardinal(1)) <> 3 then Halt(51);
  If Kind(-Int64(1)) <> 3 then Halt(52);
  If Kind(-UInt64(0)) <> 3 then Halt(59);
  If Kind(-UInt64($8000000000000000)) <> 7 then Halt(60);

  If Kind(-1 and B) <> 5 then Halt(8);
  If Kind(-1 or B) <> 5 then Halt(9);
  If Kind(-1 xor B) <> 5 then Halt(10);
  If Kind(-(1) and B) <> 5 then Halt(11);
  If Kind(-Byte(1) and B) <> 5 then Halt(12);
  If Kind((-1) and B) <> 4 then Halt(13);
  If Kind((-1) or B) <> 4 then Halt(14);
  If Kind((-1) xor B) <> 4 then Halt(15);
  If Kind((-Byte(1)) and B) <> 4 then Halt(16);
  If Kind(B and -1) <> 4 then Halt(17);
  If Kind(B or -1) <> 4 then Halt(18);
  If Kind(B xor -1) <> 4 then Halt(19);

  If Kind(-1 and C) <> 6 then Halt(20);
  If Kind(Byte(-1) and B) <> 1 then Halt(21);
  If Kind(SmallInt(-1) and B) <> 4 then Halt(22);
  If Kind(+1 and B) <> 5 then Halt(31);
  If Kind(+1 or B) <> 5 then Halt(32);
  If Kind(+1 xor B) <> 5 then Halt(33);
  If Kind((+1) and B) <> 5 then Halt(34);
  If Kind((+1) or B) <> 5 then Halt(35);
  If Kind((+1) xor B) <> 5 then Halt(36);
  If Kind(B and +1) <> 5 then Halt(37);
  If Kind(B or +1) <> 5 then Halt(38);
  If Kind(B xor +1) <> 5 then Halt(39);
  If Kind(+Byte(1) and B) <> 5 then Halt(40);
  If Kind((+Byte(1)) and B) <> 5 then Halt(41);
  If Kind(Byte(+1) and B) <> 1 then Halt(42);
  If (-1 and B) <> 2 then Halt(23);
  If (-1 or B) <> -1 then Halt(24);
  If (-1 xor B) <> -3 then Halt(25);
  If (+1 and B) <> 0 then Halt(43);
  If (+1 or B) <> 3 then Halt(44);
  If (+1 xor B) <> 3 then Halt(45);
  If Kind((+1 div 1) and B) <> 1 then Halt(53);
  If Kind((-1 div 1) and B) <> 4 then Halt(54);
  If Kind(B and (+1 div 1)) <> 1 then Halt(55);
  If Kind(B and (-1 div 1)) <> 4 then Halt(56);
  If Kind((+1 mod 1) and B) <> 1 then Halt(57);
  If Kind((-1 mod 1) and B) <> 1 then Halt(58);
end.
