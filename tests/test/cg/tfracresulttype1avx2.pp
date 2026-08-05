{ %CPU=x86_64 }
{ %TARGET=linux }
{ %OPT=-O3 -CfAVX2 -CpCOREAVX2 -OpCOREAVX2 }
program tfracresulttype1avx2;

{$mode objfpc}
{$excessprecision off}

function Kind(Value: Single): Integer; overload;
begin
  Result := 32;
end;

function Kind(Value: Double): Integer; overload;
begin
  Result := 64;
end;

function RuntimeSingle(Value: Single): Single; noinline;
begin
  Result := Value;
end;

var
  Value: Single;

begin
  Value := RuntimeSingle(1.25);
  if Kind(Frac(Value))<>32 then
    Halt(1);
  if Frac(Value)<>0.25 then
    Halt(2);
end.
