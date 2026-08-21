{ %OPT=-O3 }

program tloopinvariantarraywrite1;

{$mode delphi}
{$R-}{$Q-}

type
  TByteTable = array[0..255] of Byte;
  TByteBlock = array[0..15] of Byte;

var
  LookupTable: TByteTable;
  Data: TByteBlock;
  I,
  Round: Integer;

procedure CheckRound(Expected0, Expected1, Expected2, Expected3: Byte;
  ErrorCode: Integer);
begin
  If (Data[0]<>Expected0) or
    (Data[1]<>Expected1) or
    (Data[2]<>Expected2) or
    (Data[3]<>Expected3) then
    Halt(ErrorCode);
end;

begin
  for I:=0 to High(LookupTable) do
    LookupTable[I]:=Byte((I*7+13) and $ff);
  for I:=0 to High(Data) do
    Data[I]:=Byte(I);

  for Round:=1 to 3 do
    begin
      { After unrolling this inner loop, the outer-loop optimizer must still
        see that every following round reads values written by the previous
        one.  Hoisting LookupTable[Data[I]] across the outer loop would cache
        an address selected by stale Data. }
      for I:=0 to High(Data) do
        Data[I]:=LookupTable[Data[I]];
      for I:=0 to High(Data) do
        Data[I]:=Data[I] xor Byte(Round);

      case Round of
        1:
          CheckRound($0c,$15,$1a,$23,1);
        2:
          CheckRound($63,$a2,$c1,$00,2);
        3:
          CheckRound($c1,$78,$57,$0e,3);
      end;
    end;
end.
