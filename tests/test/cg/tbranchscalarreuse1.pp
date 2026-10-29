program tbranchscalarreuse1;

{$mode delphi}{$H+}{$inline off}
{$modeswitch inlinevars}

uses SysUtils, Math;

type
  TSample = record
    Price, Quantity: Double;
    Side: Integer;
  end;
  TSingleSample = record
    Price, Quantity: Single;
    Side: Integer;
  end;
  TSamples = array of TSample;

var
  Calls, FinallyCount: Integer;

procedure Change(var Value: Double); noinline;
begin
  Inc(Calls);
  Value := Value + 0.25;
end;

function FoldDouble(const Data: TSamples; Mode: Integer): Double;
var
  Buy, Sell, Total, Maximum: Double;
begin
  Buy := 0;
  Sell := 0;
  Total := 0;
  Maximum := 0;
  for var I := 0 to High(Data) do begin
    If Data[I].Side = Mode then Buy := Buy + Data[I].Price * Data[I].Quantity
    else Sell := Sell + Data[I].Price * Data[I].Quantity;
    If Data[I].Price > Maximum then Maximum := Data[I].Price;
    Total := Total + Data[I].Quantity;
  end;
  Result := Buy + Sell + Maximum + Total;
end;

function FoldSingle(const Data: array of TSingleSample; Mode: Integer): Single;
var
  Buy, Sell, Total: Single;
begin
  Buy := 0;
  Sell := 0;
  Total := 0;
  for var I := 0 to High(Data) do begin
    If Data[I].Side = Mode then Buy := Buy + Data[I].Price * Data[I].Quantity
    else Sell := Sell + Data[I].Price * Data[I].Quantity;
    Total := Total + Data[I].Price + Data[I].Quantity;
  end;
  Result := Buy + Sell + Total;
end;

function ChangedMemory(var Data: TSamples; Mode: Integer): Double;
var
  Buy, Sell, Total: Double;
  Alias: PDouble;
begin
  Buy := 0;
  Sell := 0;
  Total := 0;
  for var I := 0 to High(Data) do begin
    Alias := @Data[I].Price;
    If Data[I].Side = Mode then begin
      Buy := Buy + Data[I].Price * Data[I].Quantity;
      Alias^ := Alias^ + 1;
    end else begin
      Sell := Sell + Data[I].Price * Data[I].Quantity;
      Change(Alias^);
    end;
    Total := Total + Data[I].Price + Data[I].Quantity;
  end;
  Result := Buy + Sell + Total;
end;

function DifferentAddresses(const Data: TSamples; Mode: Integer): Double;
var
  Buy, Sell, Total: Double;
begin
  Buy := 0;
  Sell := 0;
  Total := 0;
  for var I := 0 to High(Data) - 1 do begin
    If Data[I].Side = Mode then Buy := Buy + Data[I].Price * Data[I].Quantity
    else Sell := Sell + Data[I+1].Price * Data[I+1].Quantity;
    Total := Total + Data[I].Price;
  end;
  Result := Buy + Sell + Total;
end;

function EarlyExit(const Data: TSamples; Mode: Integer): Double;
var
  Buy, Sell: Double;
begin
  Buy := 0;
  Sell := 0;
  for var I := 0 to High(Data) do begin
    If Data[I].Side = Mode then Buy := Buy + Data[I].Price * Data[I].Quantity
    else begin
      Sell := Sell + Data[I].Price * Data[I].Quantity;
      If I > 31 then Exit(Buy + Sell + Data[I].Price);
    end;
  end;
  Result := Buy + Sell;
end;

function Guarded(const Data: TSamples; Mode: Integer): Double;
var
  Buy, Sell: Double;
begin
  Buy := 0;
  Sell := 0;
  try
    for var I := 0 to High(Data) do begin
      If Data[I].Side = Mode then Buy := Buy + Data[I].Price * Data[I].Quantity
      else Sell := Sell + Data[I].Price * Data[I].Quantity;
      If I = 41 then raise Exception.Create('observer');
    end;
  except
    on E: Exception do Result := Buy + Sell;
  end;
end;

function Pressure(const Data: TSamples; Mode: Integer): Double;
var
  A, B, C, D, E, F, G, H, J, K, L, M: Double;
begin
  A := 1;
  B := 2;
  C := 3;
  D := 4;
  E := 5;
  F := 6;
  G := 7;
  H := 8;
  J := 9;
  K := 10;
  L := 11;
  M := 12;
  for var I := 0 to High(Data) do begin
    If Data[I].Side = Mode then A := A + Data[I].Price * Data[I].Quantity
    else B := B + Data[I].Price * Data[I].Quantity;
    C := C + Data[I].Price;
    D := D + Data[I].Quantity;
    E := E + A / 1024;
    F := F + B / 1024;
    G := G + C / 1024;
    H := H + D / 1024;
    J := J + E / 1024;
    K := K + F / 1024;
    L := L + G / 1024;
    M := M + H / 1024;
  end;
  Result := A+B+C+D+E+F+G+H+J+K+L+M;
end;

procedure PrintDouble(Value: Double);
var Bits: QWord;
begin
  Move(Value, Bits, SizeOf(Bits));
  Writeln(IntToHex(Bits, 16));
end;

procedure PrintSingle(Value: Single);
var Bits: Cardinal;
begin
  Move(Value, Bits, SizeOf(Bits));
  Writeln(IntToHex(Bits, 8));
end;

procedure TrapOrder(Mode: Integer);
var
  P: PDouble;
  Zero, One, Buy, Sell: Double;
  Saved: TFPUExceptionMask;
begin
  Zero := 0;
  One := 1;
  P := @Zero;
  Buy := 0;
  Sell := 0;
  Saved := GetExceptionMask;
  SetExceptionMask(Saved - [exZeroDivide]);
  try
    try
      If Mode = 0 then Buy := One / P^
      else Sell := One / P^;
      Halt(21);
    except
      on E: EZeroDivide do begin
        If (Buy <> 0) or (Sell <> 0) then Halt(22);
        Writeln('division observed');
      end;
    end;
  finally
    SetExceptionMask(Saved);
    Inc(FinallyCount);
  end;
end;

var
  Data: TSamples;
  Singles: array of TSingleSample;
  Seed, Mode: Integer;
begin
  Seed := StrToIntDef(ParamStr(1), 1);
  SetLength(Data, 257);
  SetLength(Singles, Length(Data));
  for Mode := 0 to 3 do begin
    for var I := 0 to High(Data) do begin
      Data[I].Price := ((I * 73 + Seed) mod 1000 - 500) / 64;
      Data[I].Quantity := ((I * 17 + Seed) mod 100 - 50) / 128;
      Data[I].Side := (I + Seed) mod 3;
      Singles[I].Price := Data[I].Price;
      Singles[I].Quantity := Data[I].Quantity;
      Singles[I].Side := Data[I].Side;
    end;
    PrintDouble(FoldDouble(Data, Mode));
    PrintSingle(FoldSingle(Singles, Mode));
    PrintDouble(DifferentAddresses(Data, Mode));
    PrintDouble(EarlyExit(Data, Mode));
    PrintDouble(Guarded(Data, Mode));
    PrintDouble(Pressure(Data, Mode));
    PrintDouble(ChangedMemory(Data, Mode));
    TrapOrder(Mode);
  end;
  Writeln(Calls, ' ', FinallyCount);
end.
