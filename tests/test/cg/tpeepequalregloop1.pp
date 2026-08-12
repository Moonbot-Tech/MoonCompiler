program tpeepequalregloop1;

{$mode delphi}

var
  RuntimeZero: QWord = 0;

function OpaqueI(Value: Int64): Int64;
begin
  Result:=Int64(QWord(Value) xor RuntimeZero);
end;

procedure CheckAscending;
var
  K, LowBound, HighBound: ShortInt;
  Count, Sum: Integer;
begin
  LowBound:=0;
  HighBound:=0;
  Count:=0;
  Sum:=0;
  for K:=ShortInt(OpaqueI(LowBound)) to ShortInt(OpaqueI(HighBound)) do
    begin
      Inc(Count);
      Inc(Sum,K);
    end;
  If (Count<>1) or (Sum<>0) then
    Halt(1);
end;

procedure CheckDescending;
var
  K, LowBound, HighBound: ShortInt;
  Count, Sum: Integer;
begin
  LowBound:=0;
  HighBound:=0;
  Count:=0;
  Sum:=0;
  for K:=ShortInt(OpaqueI(LowBound)) downto ShortInt(OpaqueI(HighBound)) do
    begin
      Inc(Count);
      Inc(Sum,K);
    end;
  If (Count<>1) or (Sum<>0) then
    Halt(2);
end;

procedure CheckNonzeroAscending;
var
  K, LowBound, HighBound: ShortInt;
  Count, Sum: Integer;
begin
  LowBound:=-3;
  HighBound:=2;
  Count:=0;
  Sum:=0;
  for K:=ShortInt(OpaqueI(LowBound)) to ShortInt(OpaqueI(HighBound)) do
    begin
      Inc(Count);
      Inc(Sum,K);
    end;
  If (Count<>6) or (Sum<>-3) then
    Halt(3);
end;

procedure CheckNonzeroDescending;
var
  K, LowBound, HighBound: ShortInt;
  Count, Sum: Integer;
begin
  LowBound:=4;
  HighBound:=-1;
  Count:=0;
  Sum:=0;
  for K:=ShortInt(OpaqueI(LowBound)) downto ShortInt(OpaqueI(HighBound)) do
    begin
      Inc(Count);
      Inc(Sum,K);
    end;
  If (Count<>6) or (Sum<>9) then
    Halt(4);
end;

begin
  CheckAscending;
  CheckDescending;
  CheckNonzeroAscending;
  CheckNonzeroDescending;
end.
