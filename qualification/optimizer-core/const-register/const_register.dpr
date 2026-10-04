program const_register;
{ Float constants and the registers of a loop.  A float constant which a
  procedure reads more than once lives in a register temp from the entry
  (compiler/optcse.pas, do_consttovar); the register allocator knows that the
  temp holds its constant and can read that constant's memory instead
  (compiler/rgobj.pas).
  With Max and Min expanded in the loop:
    HourDeltas   - the hour deltas over 5-minute candles: the loop takes 15
                   xmm registers, the constants 0, 1 and 100 are needed only
                   after it;
    PressureLoop - fifteen values of a loop, 0.25 three times a turn.
  Without any call:
    Witness14    - fourteen accumulators, 0.25 three times a turn;
    InLoop2      - fifteen values, 0.125 twice a turn: the accumulators, read
                   and written on every turn, keep the registers;
    BranchLoop   - 0.5 in both branches of a loop with few variables: there the
                   register pays and the constant keeps it;
    Reverse      - 0.75 four times a turn of a loop which needs every register,
                   a value written before the loop and read once after it: the
                   value goes to memory, the constant keeps its register;
    Deltas       - the hour deltas with the maxima and minima written out: the
                   constant 1, read twice after the loop, is the only value of
                   a register which Win64 saves and restores - the constant is
                   read from its memory and the register is not used.
  Each routine is checked against the same arithmetic on writable typed
  constants, which the compiler reads from memory. }
{$mode delphi}
{$J+}

uses
  Math;

type
  TCandle = packed record
    OpenP, CloseP, MaxP, MinP: Single;
    Vol: Single;
    Time: Double;
  end;

const
  Zero: Double = 0;
  One: Double = 1;
  Hundred: Double = 100;
  Half: Double = 0.5;
  Quarter: Double = 0.25;
  Eighth: Double = 0.125;
  ThreeQuarters: Double = 0.75;

var
  Deep: array of TCandle;
  Values: array[0..255] of Double;
  D15, D1h, R15, R1h: Double;

procedure Check(Condition: Boolean; const Message: string);
begin
  if not Condition then
  begin
    WriteLn('CONST_REGISTER_FAIL ', Message);
    Halt(1);
  end;
end;

procedure HourDeltas(NowTime, A, B: Double); noinline;
var
  j: Integer;
  Max15, Min15, Max30, Min30, Max1h, Min1h, Open1h, Open5, Max5: Double;
  tm5m, tm15m, tm30m, tm1h: Double;
  More: Boolean;
begin
  Max1h := A; Min1h := B; Open1h := 0; Max15 := A; Min15 := B; Max30 := A; Min30 := B; Max5 := A; Open5 := 0;
  More := False;
  tm5m := NowTime - 5 / 1440;
  tm15m := NowTime - 15 / 1440;
  tm30m := NowTime - 30 / 1440;
  tm1h := NowTime - 1 / 24;
  for j := High(Deep) downto 0 do
    with Deep[j] do
    begin
      if Time <= tm1h then
        Break;
      Max1h := Max(Max1h, MaxP);
      Min1h := Min(Min1h, MinP);
      Open1h := OpenP;
      if Time > tm15m then
      begin
        Max15 := Max(Max15, MaxP);
        Min15 := Min(Min15, MinP);
      end;
      if Time > tm30m then
      begin
        Max30 := Max(Max30, MaxP);
        Min30 := Min(Min30, MinP);
      end;
      if Time > tm5m then
      begin
        Max5 := Max(Max5, MaxP);
        Open5 := OpenP;
      end
      else
        More := True;
    end;
  if Min15 > 0 then
    D15 := (Max15 / Min15 - 1) * 100;
  if (Min1h > 0) and More then
    D1h := (Max1h / Min1h - 1) * 100 + (Max30 - Min30) + (Max5 - Open5) + Open1h;
end;

procedure HourDeltasRef(NowTime, A, B: Double); noinline;
var
  j: Integer;
  Max15, Min15, Max30, Min30, Max1h, Min1h, Open1h, Open5, Max5: Double;
  More: Boolean;
begin
  Max1h := A; Min1h := B; Open1h := Zero; Max15 := A; Min15 := B; Max30 := A; Min30 := B; Max5 := A;
  Open5 := Zero;
  More := False;
  for j := High(Deep) downto 0 do
    with Deep[j] do
    begin
      if Time <= NowTime - 1 / 24 then
        Break;
      Max1h := Max(Max1h, MaxP);
      Min1h := Min(Min1h, MinP);
      Open1h := OpenP;
      if Time > NowTime - 15 / 1440 then
      begin
        Max15 := Max(Max15, MaxP);
        Min15 := Min(Min15, MinP);
      end;
      if Time > NowTime - 30 / 1440 then
      begin
        Max30 := Max(Max30, MaxP);
        Min30 := Min(Min30, MinP);
      end;
      if Time > NowTime - 5 / 1440 then
      begin
        Max5 := Max(Max5, MaxP);
        Open5 := OpenP;
      end
      else
        More := True;
    end;
  if Min15 > Zero then
    R15 := (Max15 / Min15 - One) * Hundred;
  if (Min1h > Zero) and More then
    R1h := (Max1h / Min1h - One) * Hundred + (Max30 - Min30) + (Max5 - Open5) + Open1h;
end;

function PressureLoop(N: Integer; A, B: Double): Double; noinline;
var
  i: Integer;
  S1, S2, S3, S4, S5, S6, S7, S8, S9, S10, S11, S12, S13, S14, V: Double;
begin
  S1 := A; S2 := B; S3 := A + B; S4 := A - B; S5 := A * 2; S6 := B * 3; S7 := A * B; S8 := A * 4;
  S9 := B * 8; S10 := A + 3; S11 := B + 5; S12 := A - 11; S13 := B - 13; S14 := A + B + 1;
  for i := 0 to N - 1 do
  begin
    V := Values[i and 255];
    S1 := S1 + V * 0.25; S2 := Max(S2, V); S3 := Min(S3, V); S4 := S4 + S1;
    S5 := S5 + S2; S6 := S6 + S3; S7 := S7 + S4 * 0.25; S8 := S8 + S5;
    S9 := S9 + S6; S10 := S10 + S7; S11 := S11 + S8; S12 := S12 + S9; S13 := S13 + S10 + S11 + S12;
    S14 := S14 + S13 * 0.25;
  end;
  Result := S1 + S2 + S3 + S4 + S5 + S6 + S7 + S8 + S9 + S10 + S11 + S12 + S13 + S14;
end;

function PressureLoopRef(N: Integer; A, B: Double): Double; noinline;
var
  i: Integer;
  S1, S2, S3, S4, S5, S6, S7, S8, S9, S10, S11, S12, S13, S14, V: Double;
begin
  S1 := A; S2 := B; S3 := A + B; S4 := A - B; S5 := A * 2; S6 := B * 3; S7 := A * B; S8 := A * 4;
  S9 := B * 8; S10 := A + 3; S11 := B + 5; S12 := A - 11; S13 := B - 13; S14 := A + B + 1;
  for i := 0 to N - 1 do
  begin
    V := Values[i and 255];
    S1 := S1 + V * Quarter; S2 := Max(S2, V); S3 := Min(S3, V); S4 := S4 + S1;
    S5 := S5 + S2; S6 := S6 + S3; S7 := S7 + S4 * Quarter; S8 := S8 + S5;
    S9 := S9 + S6; S10 := S10 + S7; S11 := S11 + S8; S12 := S12 + S9; S13 := S13 + S10 + S11 + S12;
    S14 := S14 + S13 * Quarter;
  end;
  Result := S1 + S2 + S3 + S4 + S5 + S6 + S7 + S8 + S9 + S10 + S11 + S12 + S13 + S14;
end;

function Witness14(N: Integer; A, B: Double): Double; noinline;
var
  i: Integer;
  S1, S2, S3, S4, S5, S6, S7, S8, S9, S10, S11, S12, S13, S14, V: Double;
begin
  S1 := A; S2 := B; S3 := A + B; S4 := A - B; S5 := A * 2; S6 := B * 3; S7 := A * B; S8 := A * 4;
  S9 := B * 8; S10 := A + 3; S11 := B + 5; S12 := A - 11; S13 := B - 13; S14 := A + B + 1;
  for i := 0 to N - 1 do
  begin
    V := Values[i and 255];
    S1 := S1 + V * 0.25; S2 := S2 + V; S3 := S3 - V; S4 := S4 + S1;
    S5 := S5 + S2; S6 := S6 + S3; S7 := S7 + S4 * 0.25; S8 := S8 + S5;
    S9 := S9 + S6; S10 := S10 + S7; S11 := S11 + S8; S12 := S12 + S9; S13 := S13 + S10 + S11 + S12;
    S14 := S14 + S13 * 0.25;
  end;
  Result := S1 + S2 + S3 + S4 + S5 + S6 + S7 + S8 + S9 + S10 + S11 + S12 + S13 + S14;
end;

function Witness14Ref(N: Integer; A, B: Double): Double; noinline;
var
  i: Integer;
  S1, S2, S3, S4, S5, S6, S7, S8, S9, S10, S11, S12, S13, S14, V: Double;
begin
  S1 := A; S2 := B; S3 := A + B; S4 := A - B; S5 := A * 2; S6 := B * 3; S7 := A * B; S8 := A * 4;
  S9 := B * 8; S10 := A + 3; S11 := B + 5; S12 := A - 11; S13 := B - 13; S14 := A + B + 1;
  for i := 0 to N - 1 do
  begin
    V := Values[i and 255];
    S1 := S1 + V * Quarter; S2 := S2 + V; S3 := S3 - V; S4 := S4 + S1;
    S5 := S5 + S2; S6 := S6 + S3; S7 := S7 + S4 * Quarter; S8 := S8 + S5;
    S9 := S9 + S6; S10 := S10 + S7; S11 := S11 + S8; S12 := S12 + S9; S13 := S13 + S10 + S11 + S12;
    S14 := S14 + S13 * Quarter;
  end;
  Result := S1 + S2 + S3 + S4 + S5 + S6 + S7 + S8 + S9 + S10 + S11 + S12 + S13 + S14;
end;

function InLoop2(N: Integer; A, B: Double): Double; noinline;
var
  i: Integer;
  S1, S2, S3, S4, S5, S6, S7, S8, S9, S10, S11, S12, S13, S14, V: Double;
begin
  S1 := A; S2 := B; S3 := A + B; S4 := A - B; S5 := A * 2; S6 := B * 3; S7 := A * B; S8 := A / 7;
  S9 := B / 9; S10 := A + 3; S11 := B + 5; S12 := A - 11; S13 := B - 13; S14 := A + B + 1;
  for i := 0 to N - 1 do
  begin
    V := Values[i and 255];
    S1 := S1 + V * 0.125; S2 := S2 + V; S3 := S3 - V; S4 := S4 + S1;
    S5 := S5 + S2; S6 := S6 + S3; S7 := S7 + S4 * 0.125; S8 := S8 + S5;
    S9 := S9 + S6; S10 := S10 + S7; S11 := S11 + S8; S12 := S12 + S9; S13 := S13 + S10 + S11 + S12;
    S14 := S14 + S13;
  end;
  Result := S1 + S2 + S3 + S4 + S5 + S6 + S7 + S8 + S9 + S10 + S11 + S12 + S13 + S14;
end;

function InLoop2Ref(N: Integer; A, B: Double): Double; noinline;
var
  i: Integer;
  S1, S2, S3, S4, S5, S6, S7, S8, S9, S10, S11, S12, S13, S14, V: Double;
begin
  S1 := A; S2 := B; S3 := A + B; S4 := A - B; S5 := A * 2; S6 := B * 3; S7 := A * B; S8 := A / 7;
  S9 := B / 9; S10 := A + 3; S11 := B + 5; S12 := A - 11; S13 := B - 13; S14 := A + B + 1;
  for i := 0 to N - 1 do
  begin
    V := Values[i and 255];
    S1 := S1 + V * Eighth; S2 := S2 + V; S3 := S3 - V; S4 := S4 + S1;
    S5 := S5 + S2; S6 := S6 + S3; S7 := S7 + S4 * Eighth; S8 := S8 + S5;
    S9 := S9 + S6; S10 := S10 + S7; S11 := S11 + S8; S12 := S12 + S9; S13 := S13 + S10 + S11 + S12;
    S14 := S14 + S13;
  end;
  Result := S1 + S2 + S3 + S4 + S5 + S6 + S7 + S8 + S9 + S10 + S11 + S12 + S13 + S14;
end;

function BranchLoop(N: Integer): Double; noinline;
var
  i: Integer;
  S, V: Double;
begin
  S := 0;
  for i := 0 to N - 1 do
  begin
    V := Values[i and 255];
    if V > 1.0 then
      S := S + V * 0.5
    else
      S := S - V * 0.5;
  end;
  Result := S;
end;

function BranchLoopRef(N: Integer): Double; noinline;
var
  i: Integer;
  S, V: Double;
begin
  S := Zero;
  for i := 0 to N - 1 do
  begin
    V := Values[i and 255];
    if V > One then
      S := S + V * Half
    else
      S := S - V * Half;
  end;
  Result := S;
end;

function Reverse(N: Integer; A, B: Double): Double; noinline;
var
  i: Integer;
  S1, S2, S3, S4, S5, S6, S7, S8, S9, S10, S11, S12, S13, V, Keep: Double;
begin
  Keep := A * B + 7;
  S1 := A; S2 := B; S3 := A + B; S4 := A - B; S5 := A * 2; S6 := B * 3; S7 := A * B; S8 := A / 7;
  S9 := B / 9; S10 := A + 3; S11 := B + 5; S12 := A - 11; S13 := B - 13;
  for i := 0 to N - 1 do
  begin
    V := Values[i and 255];
    S1 := S1 + V * 0.75; S2 := S2 + V * 0.75; S3 := S3 - V * 0.75; S4 := S4 + S1 * 0.75;
    S5 := S5 + S2; S6 := S6 + S3; S7 := S7 + S4; S8 := S8 + S5;
    S9 := S9 + S6; S10 := S10 + S7; S11 := S11 + S8; S12 := S12 + S9; S13 := S13 + S10 + S11 + S12;
  end;
  Result := S1 + S2 + S3 + S4 + S5 + S6 + S7 + S8 + S9 + S10 + S11 + S12 + S13 + Keep;
end;

function ReverseRef(N: Integer; A, B: Double): Double; noinline;
var
  i: Integer;
  S1, S2, S3, S4, S5, S6, S7, S8, S9, S10, S11, S12, S13, V, Keep: Double;
begin
  Keep := A * B + 7;
  S1 := A; S2 := B; S3 := A + B; S4 := A - B; S5 := A * 2; S6 := B * 3; S7 := A * B; S8 := A / 7;
  S9 := B / 9; S10 := A + 3; S11 := B + 5; S12 := A - 11; S13 := B - 13;
  for i := 0 to N - 1 do
  begin
    V := Values[i and 255];
    S1 := S1 + V * ThreeQuarters; S2 := S2 + V * ThreeQuarters; S3 := S3 - V * ThreeQuarters;
    S4 := S4 + S1 * ThreeQuarters;
    S5 := S5 + S2; S6 := S6 + S3; S7 := S7 + S4; S8 := S8 + S5;
    S9 := S9 + S6; S10 := S10 + S7; S11 := S11 + S8; S12 := S12 + S9; S13 := S13 + S10 + S11 + S12;
  end;
  Result := S1 + S2 + S3 + S4 + S5 + S6 + S7 + S8 + S9 + S10 + S11 + S12 + S13 + Keep;
end;

procedure Deltas(NowTime, A, B: Double); noinline;
var
  j: Integer;
  Max15, Min15, Max30, Min30, Max1h, Min1h, Open1h, Open5, Max5: Double;
  tm5m, tm15m, tm30m, tm1h: Double;
  More: Boolean;
begin
  Max1h := A; Min1h := B; Open1h := 0; Max15 := A; Min15 := B; Max30 := A; Min30 := B; Max5 := A; Open5 := 0;
  More := False;
  tm5m := NowTime - 5 / 1440;
  tm15m := NowTime - 15 / 1440;
  tm30m := NowTime - 30 / 1440;
  tm1h := NowTime - 1 / 24;
  for j := High(Deep) downto 0 do
    with Deep[j] do
    begin
      if Time <= tm1h then
        Break;
      if MaxP > Max1h then Max1h := MaxP;
      if MinP < Min1h then Min1h := MinP;
      Open1h := OpenP;
      if Time > tm15m then
      begin
        if MaxP > Max15 then Max15 := MaxP;
        if MinP < Min15 then Min15 := MinP;
      end;
      if Time > tm30m then
      begin
        if MaxP > Max30 then Max30 := MaxP;
        if MinP < Min30 then Min30 := MinP;
      end;
      if Time > tm5m then
      begin
        if MaxP > Max5 then Max5 := MaxP;
        Open5 := OpenP;
      end
      else
        More := True;
    end;
  if Min15 > 0 then
    D15 := (Max15 / Min15 - 1) * 100;
  if (Min1h > 0) and More then
    D1h := (Max1h / Min1h - 1) * 100 + (Max30 - Min30) + (Max5 - Open5) + Open1h;
end;

procedure DeltasRef(NowTime, A, B: Double); noinline;
var
  j: Integer;
  Max15, Min15, Max30, Min30, Max1h, Min1h, Open1h, Open5, Max5: Double;
  More: Boolean;
begin
  Max1h := A; Min1h := B; Open1h := Zero; Max15 := A; Min15 := B; Max30 := A; Min30 := B; Max5 := A;
  Open5 := Zero;
  More := False;
  for j := High(Deep) downto 0 do
    with Deep[j] do
    begin
      if Time <= NowTime - 1 / 24 then
        Break;
      if MaxP > Max1h then Max1h := MaxP;
      if MinP < Min1h then Min1h := MinP;
      Open1h := OpenP;
      if Time > NowTime - 15 / 1440 then
      begin
        if MaxP > Max15 then Max15 := MaxP;
        if MinP < Min15 then Min15 := MinP;
      end;
      if Time > NowTime - 30 / 1440 then
      begin
        if MaxP > Max30 then Max30 := MaxP;
        if MinP < Min30 then Min30 := MinP;
      end;
      if Time > NowTime - 5 / 1440 then
      begin
        if MaxP > Max5 then Max5 := MaxP;
        Open5 := OpenP;
      end
      else
        More := True;
    end;
  if Min15 > Zero then
    R15 := (Max15 / Min15 - One) * Hundred;
  if (Min1h > Zero) and More then
    R1h := (Max1h / Min1h - One) * Hundred + (Max30 - Min30) + (Max5 - Open5) + Open1h;
end;

var
  I: Integer;
begin
  SetLength(Deep, 20);
  for I := 0 to High(Deep) do
    with Deep[I] do
    begin
      OpenP := 64 + I; CloseP := 65 + I; MaxP := 66 + I * 1.5; MinP := 63 + I * 0.5; Vol := I;
      Time := 1.0 - (High(Deep) - I) * 5 / 1440;
    end;
  for I := 0 to 255 do
    Values[I] := (I mod 17) * 0.125 + 0.5;
  HourDeltas(1.0, 2.0, 1.0);
  HourDeltasRef(1.0, 2.0, 1.0);
  Check((D15 = R15) and (D1h = R1h), 'hour deltas');
  Check(PressureLoop(64, 1.5, 2.5) = PressureLoopRef(64, 1.5, 2.5), 'pressure loop');
  Check(Witness14(64, 1.5, 2.5) = Witness14Ref(64, 1.5, 2.5), 'witness14');
  Check(InLoop2(64, 1.5, 2.5) = InLoop2Ref(64, 1.5, 2.5), 'in loop 2');
  Check(BranchLoop(1000) = BranchLoopRef(1000), 'branch loop');
  Check(Reverse(64, 1.5, 2.5) = ReverseRef(64, 1.5, 2.5), 'reverse');
  Deltas(1.0, 2.0, 1.0);
  DeltasRef(1.0, 2.0, 1.0);
  Check((D15 = R15) and (D1h = R1h), 'deltas');
  WriteLn('CONST_REGISTER_PASS');
end.
