{ %OPT=-O3 }
program texplicitconst1;

{$mode delphi}

uses
  uexplicitconst1;

function Kind(Value: Integer): Byte; overload;
begin
  Result := 1;
end;

function Kind(Value: Word): Byte; overload;
begin
  Result := 2;
end;

function Kind(Value: SmallInt): Byte; overload;
begin
  Result := 3;
end;

function Kind(Value: ShortInt): Byte; overload;
begin
  Result := 4;
end;

function Kind(Value: Byte): Byte; overload;
begin
  Result := 5;
end;

var
  SI: ShortInt;
  W: Word;
begin
  SI := 2;
  W := 2;
  If Kind(SI and UntypedOne) <> 4 then Halt(1);
  If Kind(SI and ExplicitByteOne) <> 3 then Halt(2);
  If Kind(W or Untyped256) <> 2 then Halt(3);
  If Kind(W or ExplicitSmallIntOne) <> 1 then Halt(4);
  If Kind(UntypedNegOne or Byte(SI)) <> 3 then Halt(5);
  If Kind(ExplicitShortNegOne or Byte(SI)) <> 3 then Halt(6);
  If Kind(TypedShortNegOne or Byte(SI)) <> 3 then Halt(7);
  If Kind(Byte(SI) and UntypedPlusOne) <> 1 then Halt(8);
  If Kind(UntypedPlusOne and Byte(SI)) <> 1 then Halt(9);
  If Kind(Byte(SI) and TypedPlusOne) <> 5 then Halt(10);
  If Kind(TypedPlusOne and Byte(SI)) <> 5 then Halt(11);
  If Kind(Byte(SI) or UntypedPlusOne) <> 1 then Halt(12);
  If Kind(UntypedPlusOne or Byte(SI)) <> 1 then Halt(13);
  If Kind(Byte(SI) xor UntypedPlusOne) <> 1 then Halt(14);
  If Kind(UntypedPlusOne xor Byte(SI)) <> 1 then Halt(15);
  If Kind(Byte(SI) or TypedPlusOne) <> 5 then Halt(16);
  If Kind(TypedPlusOne or Byte(SI)) <> 5 then Halt(17);
  If Kind(Byte(SI) xor TypedPlusOne) <> 5 then Halt(18);
  If Kind(TypedPlusOne xor Byte(SI)) <> 5 then Halt(19);
end.
