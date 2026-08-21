program tdelphiintpair1;

{$ifdef FPC}
  {$mode delphiunicode}
{$endif}

type
  TUnsignedTiny = 0..100;
  TSignedTiny = -10..100;

function Pick(const Value: Integer): Byte; overload;
begin
  Result := 1;
end;

function Pick(const Value: Cardinal): Byte; overload;
begin
  Result := 2;
end;

function PickReverse(const Value: Cardinal): Byte; overload;
begin
  Result := 2;
end;

function PickReverse(const Value: Integer): Byte; overload;
begin
  Result := 1;
end;

function Pick64(const Value: Int64): Byte; overload;
begin
  Result := 1;
end;

function Pick64(const Value: UInt64): Byte; overload;
begin
  Result := 2;
end;

function Pick64Reverse(const Value: UInt64): Byte; overload;
begin
  Result := 2;
end;

function Pick64Reverse(const Value: Int64): Byte; overload;
begin
  Result := 1;
end;

procedure Check(Condition: Boolean; ErrorCode: Byte);
begin
  if not Condition then
    Halt(ErrorCode);
end;

var
  SI8: ShortInt;
  UI8: Byte;
  SI16: SmallInt;
  UI16: Word;
  SI32: Integer;
  UI32: Cardinal;
  SI64: Int64;
  UI64: UInt64;
  NI: NativeInt;
  NU: NativeUInt;
  UTiny: TUnsignedTiny;
  STiny: TSignedTiny;
begin
  SI8 := 7; UI8 := 7; SI16 := 7; UI16 := 7;
  SI32 := 7; UI32 := 7; SI64 := 7; UI64 := 7;
  NI := 7; NU := 7; UTiny := 7; STiny := 7;
  Check(Pick(SI8) = 1, 1);
  Check(Pick(UI8) = 1, 2);
  Check(Pick(SI16) = 1, 3);
  Check(Pick(UI16) = 1, 4);
  Check(Pick(SI32) = 1, 5);
  Check(Pick(UI32) = 2, 6);
  Check(Pick(SI64) = 2, 7);
  Check(Pick(UI64) = 2, 8);
  Check(Pick(NI) = 2, 9);
  Check(Pick(NU) = 2, 10);
  Check(Pick(UTiny) = 1, 11);
  Check(Pick(STiny) = 1, 12);
  Check(PickReverse(UI8) = 1, 13);
  Check(PickReverse(UI16) = 1, 14);
  Check(PickReverse(SI64) = 2, 15);
  Check(PickReverse(UI64) = 2, 16);
  Check(Pick(-1) = 1, 17);
  Check(Pick(2147483647) = 1, 18);
  Check(Pick($80000000) = 2, 19);
  Check(Pick($FFFFFFFF) = 2, 20);
  Check(Pick64(SI8) = 1, 21);
  Check(Pick64(UI8) = 1, 22);
  Check(Pick64(SI16) = 1, 23);
  Check(Pick64(UI16) = 1, 24);
  Check(Pick64(SI32) = 1, 25);
  Check(Pick64(UI32) = 1, 26);
  Check(Pick64(SI64) = 1, 27);
  Check(Pick64(UI64) = 2, 28);
  Check(Pick64(NI) = 1, 29);
  Check(Pick64(NU) = 2, 30);
  Check(Pick64Reverse(UI32) = 1, 31);
  Check(Pick64Reverse(SI64) = 1, 32);
  Check(Pick64Reverse(UI64) = 2, 33);
end.
