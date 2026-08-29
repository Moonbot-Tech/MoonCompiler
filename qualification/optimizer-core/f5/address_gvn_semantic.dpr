program address_gvn_semantic;

{$mode unleashed}
{$Q-}
{$R-}

type
  TPair = record
    X,
    Y: Int64;
  end;

var
  Data: array[0..127] of TPair;

procedure Butterfly(I, J: Integer); noinline;
var
  AX,
  AY,
  BX,
  BY: Int64;
begin
  AX := Data[I].X;
  AY := Data[I].Y;
  BX := Data[J].X;
  BY := Data[J].Y;
  Data[I].X := AX + BX - BY;
  Data[I].Y := AY + BX + BY;
  Data[J].X := AX - BX;
  Data[J].Y := AY - BY;
end;

var
  Digest: QWord;
  I: Integer;
begin
  for I := 0 to High(Data) do begin
    Data[I].X := Int64(I) * 3 + 1;
    Data[I].Y := Int64(I) * 5 - 2;
  end;
  for I := 0 to 63 do
    Butterfly(I, I + 64);
  Digest := 0;
  for I := 0 to High(Data) do begin
    Digest := Digest + QWord(Data[I].X) * (I * 2 + 1);
    Digest := Digest + QWord(Data[I].Y) * (I * 2 + 2);
  end;
  WriteLn('ADDRESSGVN:PASS:', Digest);
end.
