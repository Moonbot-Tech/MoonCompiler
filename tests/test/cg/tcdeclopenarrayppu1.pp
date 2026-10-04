program tcdeclopenarrayppu1;

{$mode objfpc}

uses
  ucdeclopenarray1;

var
  Values: TVarRecDynArray;
  Pair: TCdeclConstPair;
  Reader: TCdeclConstReader;
  Calls: Integer;

function MakeArgs(First,Second: Integer): TVarRecDynArray;
begin
  Inc(Calls);
  SetLength(Result,2);
  Result[0].VType:=vtInteger;
  Result[0].VInteger:=First;
  Result[1].VType:=vtInteger;
  Result[1].VInteger:=Second;
end;

procedure CheckEvaluation(Code: Integer; Value: Int64);
begin
  if (Value<>5232155) or (Calls<>2) then
    Halt(Code);
  Calls:=0;
end;

begin
  if OpenHigh([11,22,33])<>2 then
    Halt(1);
  if ConstHigh([11,'x',3.5])<>2 then
    Halt(2);
  if ConstFirstInteger([47])<>47 then
    Halt(3);
  SetLength(Values,1);
  Values[0].VType:=vtInteger;
  Values[0].VInteger:=73;
  if ConstFirstInteger(Values)<>73 then
    Halt(4);
  if ConstPair([17],[23],5)<>5112317 then
    Halt(5);
  Pair:=@ConstPair;
  if Pair(Values,[],7)<>7100073 then
    Halt(6);
  Reader:=TCdeclConstReader.Create;
  try
    if Reader.ReadPair([],Values,9)<>9017300 then
      Halt(7);
  finally
    Reader.Free;
  end;
  Calls:=0;
  CheckEvaluation(8,ConstPair(MakeArgs(11,22),MakeArgs(33,44),5));
  Pair:=@ConstPair;
  CheckEvaluation(9,Pair(MakeArgs(11,22),MakeArgs(33,44),5));
  Reader:=TCdeclConstReader.Create;
  try
    CheckEvaluation(10,Reader.ReadPair(MakeArgs(11,22),MakeArgs(33,44),5));
  finally
    Reader.Free;
  end;
  CheckEvaluation(11,ForwardConstPair(MakeArgs(11,22),MakeArgs(33,44),5));
  CheckEvaluation(12,ForwardTypedPair(MakeArgs(11,22),MakeArgs(33,44),5));
end.
