{ %CPU=x86_64 }
{ %TARGET=linux }
{ %OPT=-O3 -CfAVX2 -CpCOREAVX2 -OpCOREAVX2 }
program tintrinsicresulttype1avx2;

{$mode delphi}

uses
  uintrinsicresulttype1;

function RuntimeDouble(Value: Double): Double; noinline;
begin
  Result := Value;
end;

var
  Value: Extended;

begin
  Value := RuntimeDouble(1.25);
  if CrossUnitKinds(Value)<>8*64 then
    Halt(1);
end.
