program relation_semantic;
{$ifdef FPC}{$mode delphi}{$H+}{$endif}
{$APPTYPE CONSOLE}
{$R-}{$Q-}

type
  TPrices = array[0..7] of Double;
const
  Bits: array[0..6] of UInt64 = ($C008000000000000, $8000000000000000, 0,
    $4008000000000000, $7FF0000000000000, $FFF0000000000000, $7FF8000000000021);
  Rank: array[0..6] of Integer = (-3, 0, 0, 3, 100, -100, 0);
var
  Prices: TPrices;
  Failures: Integer;

function SearchSigned(Start, Limit: Integer; Needle: Double): Double;
var I: Integer;
begin
  I := Start;
  repeat
    Inc(I);
    If I >= Limit then Exit(-1);
  until Prices[I] >= Needle;
  If I < Limit then Result := I else Result := -2;
end;

function SearchUnsigned(Start, Limit: UInt32; Needle: Double): Double;
var I: UInt32;
begin
  I := Start;
  repeat
    If I >= Limit then Exit(-1);
    If Prices[I] >= Needle then Break;
    Inc(I);
  until False;
  If I < Limit then Result := I else Result := -2;
end;

function ExternalJoin(A, B: Integer; X, Y: Double): Integer;
label Done;
begin
  If A >= B then goto Done;
  If X > Y then Inc(A, 100);
Done:
  If A >= B then Result := 1 else Result := 0;
end;

function AlterLow(A, B: Integer; X, Y: Double): Integer;
begin
  If A >= B then Exit(2);
  If X > Y then PByte(@A)^ := 255;
  If A >= B then Result := 1 else Result := 0;
end;

function ScanBatch(Start, Limit, Repeats: Integer; Needle: Double): Double;
var I, J: Integer;
begin
  Result := 0;
  I := Start;
  for J := 0 to Repeats - 1 do begin
    while (I < Limit) and (Prices[I] < Needle) do Inc(I);
    If I >= Limit then Break;
    Result := Result + I + 1;
  end;
end;

var
  S, L, Rotation, N, I, Expected, Index, A, B, Repeats, ScanExpected: Integer;
  Needle, X, Y, Actual: Double;
begin
  for Rotation := 0 to 6 do begin
    for I := 0 to 7 do begin
      Index := (I + Rotation) mod 7;
      Move(Bits[Index], Prices[I], 8);
    end;
    for N := 0 to 6 do begin
      Move(Bits[N], Needle, 8);
      for S := -1 to 7 do for L := 0 to 8 do begin
        { The oracle compares integer ranks and an explicit unordered marker. }
        Expected := -1;
        for I := S + 1 to L - 1 do begin
          Index := (I + Rotation) mod 7;
          If (N <> 6) and (Index <> 6) and (Rank[Index] >= Rank[N]) then begin
            Expected := I;
            Break;
          end;
        end;
        Actual := SearchSigned(S, L, Needle);
        If Actual <> Expected then begin
          If Failures < 8 then
            WriteLn('SIGNED ', Rotation, ' ', N, ' ', S, ' ', L, ' expected=', Expected, ' actual=', Actual);
          Inc(Failures);
        end;
        ScanExpected := -1;
        for I := S + 1 to L - 1 do begin
          Index := (I + Rotation) mod 7;
          If (N = 6) or (Index = 6) or (Rank[Index] >= Rank[N]) then begin
            ScanExpected := I;
            Break;
          end;
        end;
        for Repeats := 0 to 3 do
          If ScanBatch(S + 1, L, Repeats, Needle) <> (ScanExpected + 1) * Repeats then Inc(Failures);
        Actual := SearchUnsigned(UInt32(S + 1), UInt32(L), Needle);
        If Actual <> Expected then begin
          If Failures < 8 then
            WriteLn('UNSIGNED ', Rotation, ' ', N, ' ', S, ' ', L, ' expected=', Expected, ' actual=', Actual);
          Inc(Failures);
        end;
      end;
    end;
  end;
  for A := -3 to 3 do for B := -3 to 3 do for I := 0 to 6 do for N := 0 to 6 do begin
    Move(Bits[I], X, 8);
    Move(Bits[N], Y, 8);
    Expected := A;
    If (A < B) and (I <> 6) and (N <> 6) and (Rank[I] > Rank[N]) then Inc(Expected, 100);
    If ExternalJoin(A, B, X, Y) <> Ord(Expected >= B) then Inc(Failures);
    If A >= B then Expected := 2 else begin
      Index := A;
      If (I <> 6) and (N <> 6) and (Rank[I] > Rank[N]) then Index := (A and not 255) or 255;
      Expected := Ord(Index >= B);
    end;
    If AlterLow(A, B, X, Y) <> Expected then Inc(Failures);
  end;
  If Failures <> 0 then begin
    WriteLn('RELATION-SEMANTIC:FAIL ', Failures);
    Halt(1);
  end;
  WriteLn('RELATION-SEMANTIC:PASS');
end.
