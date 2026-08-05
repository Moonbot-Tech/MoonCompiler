{ %OPT=-O3 }
program tu64radixliteralfpc1;

{$mode objfpc}

function Kind(Value: Int64): Byte; overload;
begin
  Result := 1;
end;

function Kind(Value: UInt64): Byte; overload;
begin
  Result := 2;
end;

begin
  If Kind($8000000000000000) <> 1 then
    Halt(1);
end.
