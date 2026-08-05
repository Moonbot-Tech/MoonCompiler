{ %OPT=-O3 }
program tdelphiconsttype1;

{$mode delphi}

function Kind(Value: ShortInt): Byte; overload;
begin
  Result := 1;
end;

function Kind(Value: Byte): Byte; overload;
begin
  Result := 2;
end;

function Kind(Value: SmallInt): Byte; overload;
begin
  Result := 3;
end;

function Kind(Value: Word): Byte; overload;
begin
  Result := 4;
end;

function Kind(Value: Integer): Byte; overload;
begin
  Result := 5;
end;

begin
  If Kind(-1) <> 1 then Halt(1);
  If Kind(0) <> 1 then Halt(2);
  If Kind(1) <> 1 then Halt(3);
  If Kind($ff) <> 2 then Halt(4);
  If Kind($100) <> 3 then Halt(5);
  If Kind($7fff) <> 3 then Halt(6);
  If Kind($8000) <> 4 then Halt(7);
  If Kind($ffff) <> 4 then Halt(8);
  If Kind($10000) <> 5 then Halt(9);
  If Kind(Byte(6) + Byte(4)) <> 1 then Halt(10);
  If Kind(Byte(2) and $01) <> 1 then Halt(11);
  If Kind(Word(2) or $100) <> 3 then Halt(12);
  If Kind(SmallInt(2) xor $01) <> 1 then Halt(13);
end.
