program address_gvn_semantic;

{$mode unleashed}
{$Q-}
{$R-}

type
  TPair = record
    X,
    Y: Int64;
  end;

  TFloatPair = record
    Re,
    Im: Double;
  end;

var
  Data: array[0..127] of TPair;

procedure ButterflyOpen(var OpenData: array of TPair; I, J: Integer); noinline;
var
  AX,
  AY,
  BX,
  BY: Int64;
begin
  AX := OpenData[I].X;
  AY := OpenData[I].Y;
  BX := OpenData[J].X;
  BY := OpenData[J].Y;
  OpenData[I].X := AX + BX - BY;
  OpenData[I].Y := AY + BX + BY;
  OpenData[J].X := AX - BX;
  OpenData[J].Y := AY - BY;
end;

procedure ButterflyFloatOpen(var OpenData: array of TFloatPair; I, J: Integer;
  WRe, WIm: Double); noinline;
var
  TRe,
  TIm,
  URe,
  UIm: Double;
begin
  TRe := WRe * OpenData[J].Re - WIm * OpenData[J].Im;
  TIm := WRe * OpenData[J].Im + WIm * OpenData[J].Re;
  URe := OpenData[I].Re;
  UIm := OpenData[I].Im;
  OpenData[I].Re := URe + TRe;
  OpenData[I].Im := UIm + TIm;
  OpenData[J].Re := URe - TRe;
  OpenData[J].Im := UIm - TIm;
end;

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
  FloatData: array of TFloatPair;
  OpenData: array of TPair;
  I: Integer;
begin
  for I := 0 to High(Data) do begin
    Data[I].X := Int64(I) * 3 + 1;
    Data[I].Y := Int64(I) * 5 - 2;
  end;
  for I := 0 to 63 do
    Butterfly(I, I + 64);
  SetLength(OpenData,4);
  for I := 0 to High(OpenData) do begin
    OpenData[I].X := Int64(I) * 3 + 1;
    OpenData[I].Y := Int64(I) * 5 - 2;
  end;
  ButterflyOpen(OpenData,1,3);
  if (OpenData[1].X<>1) or (OpenData[1].Y<>26) or
     (OpenData[3].X<>-6) or (OpenData[3].Y<>-10) then begin
    WriteLn('ADDRESSGVN:FAIL:OPEN');
    Halt(1);
  end;
  SetLength(FloatData,4);
  for I := 0 to High(FloatData) do begin
    FloatData[I].Re := I + 1;
    FloatData[I].Im := (I + 1) * 0.5;
  end;
  ButterflyFloatOpen(FloatData,1,3,0.6,-0.8);
  if (Abs(FloatData[1].Re-6.0)>1e-12) or
     (Abs(FloatData[1].Im+1.0)>1e-12) or
     (Abs(FloatData[3].Re+2.0)>1e-12) or
     (Abs(FloatData[3].Im-3.0)>1e-12) then begin
    WriteLn('ADDRESSGVN:FAIL:FLOATOPEN');
    Halt(1);
  end;
  Digest := 0;
  for I := 0 to High(Data) do begin
    Digest := Digest + QWord(Data[I].X) * (I * 2 + 1);
    Digest := Digest + QWord(Data[I].Y) * (I * 2 + 2);
  end;
  WriteLn('ADDRESSGVN:PASS:', Digest);
end.
