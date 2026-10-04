program tmoddivreassociate1;

{$mode delphi}
{$Q+}

function Direct32(Value,FirstDivisor,SecondDivisor: Integer): Integer; noinline;
begin
  Result:=(Value div FirstDivisor) div SecondDivisor;
end;

function Staged32(Value,FirstDivisor,SecondDivisor: Integer): Integer; noinline;
var
  Step: Integer;
begin
  Step:=Value div FirstDivisor;
  Result:=Step div SecondDivisor;
end;

function DirectU32(Value,FirstDivisor,SecondDivisor: Cardinal): Cardinal; noinline;
begin
  Result:=(Value div FirstDivisor) div SecondDivisor;
end;

function StagedU32(Value,FirstDivisor,SecondDivisor: Cardinal): Cardinal; noinline;
var
  Step: Cardinal;
begin
  Step:=Value div FirstDivisor;
  Result:=Step div SecondDivisor;
end;

procedure Check32(Value,FirstDivisor,SecondDivisor: Integer;Code: Integer);
begin
  if Direct32(Value,FirstDivisor,SecondDivisor)<>
     Staged32(Value,FirstDivisor,SecondDivisor) then
    Halt(Code);
end;

procedure CheckU32(Value,FirstDivisor,SecondDivisor: Cardinal;Code: Integer);
begin
  if DirectU32(Value,FirstDivisor,SecondDivisor)<>
     StagedU32(Value,FirstDivisor,SecondDivisor) then
    Halt(Code);
end;

begin
  Check32(Low(Integer),50000,50000,1);
  Check32(Low(Integer),-50000,50000,2);
  Check32(High(Integer),46340,46340,3);
  Check32(High(Integer),46341,46341,4);
  CheckU32(High(Cardinal),65535,65535,5);
  CheckU32(High(Cardinal),65536,65536,6);
end.
