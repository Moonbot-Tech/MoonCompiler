{ %OPT=-O3 }
program tu64radixliteral1;

{$mode delphi}
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

function UVal(Value: UInt64): UInt64;
begin
  Result := Value;
end;

begin
  If Kind($7FFFFFFF) <> 1 then Halt(1);
  If Kind($80000000) <> 2 then Halt(2);
  If Kind($7FFFFFFFFFFFFFFF) <> 3 then Halt(3);
  If Kind($8000000000000000) <> 4 then Halt(4);
  If Kind($FFFFFFFFFFFFFFFF) <> 4 then Halt(5);
  If UVal($8000000000000000) <> UInt64($8000000000000000) then Halt(6);
  If UVal($FFFFFFFFFFFFFFFF) <> High(UInt64) then Halt(7);
  If Kind(-$8000000000000000) <> 3 then Halt(8);
  If Kind(+$8000000000000000) <> 4 then Halt(9);
  { Preserve FPC's accepted octal extension; DCC rejects this source. }
  If Kind(&1000000000000000000000) <> 3 then Halt(10);
  If Kind(%1000000000000000000000000000000000000000000000000000000000000000) <> 4 then Halt(11);
end.
