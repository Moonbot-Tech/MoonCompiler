{ %OPT=-O3 }

program tvecscaledstride1;

{$mode delphi}
{$R-}{$Q-}

type
  T6 = packed array[0..5] of Byte;
  T10 = packed array[0..9] of Byte;
  T12 = packed array[0..11] of Byte;
  T18 = packed array[0..17] of Byte;
  T20 = packed array[0..19] of Byte;
  T24 = packed array[0..23] of Byte;
  T36 = packed array[0..35] of Byte;
  T40 = packed array[0..39] of Byte;
  T72 = packed array[0..71] of Byte;

var
  A6: array[-4..7] of T6;
  A10: array[-4..7] of T10;
  A12: array[-4..7] of T12;
  A18: array[-4..7] of T18;
  A20: array[-4..7] of T20;
  A24: array[-4..7] of T24;
  A36: array[-4..7] of T36;
  A40: array[-4..7] of T40;
  A72: array[-4..7] of T72;
  Matrix: array[-2..3,-4..7] of T24;

procedure Check(I,J: Integer); noinline;
begin
  if PtrUInt(@A6[I][J])-PtrUInt(@A6[0][0])<>PtrUInt(I*6+J) then Halt(1);
  if PtrUInt(@A10[I][J])-PtrUInt(@A10[0][0])<>PtrUInt(I*10+J) then Halt(2);
  if PtrUInt(@A12[I][J])-PtrUInt(@A12[0][0])<>PtrUInt(I*12+J) then Halt(3);
  if PtrUInt(@A18[I][J])-PtrUInt(@A18[0][0])<>PtrUInt(I*18+J) then Halt(4);
  if PtrUInt(@A20[I][J])-PtrUInt(@A20[0][0])<>PtrUInt(I*20+J) then Halt(5);
  if PtrUInt(@A24[I][J])-PtrUInt(@A24[0][0])<>PtrUInt(I*24+J) then Halt(6);
  if PtrUInt(@A36[I][J])-PtrUInt(@A36[0][0])<>PtrUInt(I*36+J) then Halt(7);
  if PtrUInt(@A40[I][J])-PtrUInt(@A40[0][0])<>PtrUInt(I*40+J) then Halt(8);
  if PtrUInt(@A72[I][J])-PtrUInt(@A72[0][0])<>PtrUInt(I*72+J) then Halt(9);
  A6[I][J]:=Byte(I+J);
  A10[I][J]:=Byte(I-J);
  A72[I][J]:=Byte(I*J);
  if A6[I][J]<>Byte(I+J) then Halt(10);
  if A10[I][J]<>Byte(I-J) then Halt(11);
  if A72[I][J]<>Byte(I*J) then Halt(12);
end;

procedure CheckMatrix(I,J,K: Integer); noinline;
begin
  if PtrUInt(@Matrix[I,J][K])-PtrUInt(@Matrix[0,0][0])<>PtrUInt((I*12+J)*24+K) then Halt(13);
  Matrix[I,J][K]:=Byte(I+J+K);
  if Matrix[I,J][K]<>Byte(I+J+K) then Halt(14);
end;

{$push}{$R+}{$Q+}
procedure CheckChecked(I,J: Integer); noinline;
begin
  if PtrInt(@A24[I][J])-PtrInt(@A24[0][0])<>I*24+J then Halt(15);
end;
{$pop}

var
  I,J,K: Integer;
begin
  for I:=-4 to 7 do
    for J:=0 to 5 do
    begin
      Check(I,J);
      CheckChecked(I,J);
    end;
  for I:=-2 to 3 do
    for J:=-4 to 7 do
      for K:=0 to 23 do
        CheckMatrix(I,J,K);
end.
