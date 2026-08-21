{ %OPT=-O2 }
program tmoondelphicallbacktypes1;

{$mode delphiunicode}
{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}

uses
  SysUtils;

var
  P0: TProc;
  P1: TProc<Integer>;
  P2: TProc<Integer, Integer>;
  P3: TProc<Integer, Integer, Integer>;
  P4: TProc<Integer, Integer, Integer, Integer>;
  F0: TFunc<Integer>;
  F1: TFunc<Integer, Integer>;
  F2: TFunc<Integer, Integer, Integer>;
  F3: TFunc<Integer, Integer, Integer, Integer>;
  F4: TFunc<Integer, Integer, Integer, Integer, Integer>;
  Pred: TPredicate<Integer>;
  Total: Integer;

begin
  P0 := procedure begin Inc(Total) end;
  P1 := procedure(A: Integer) begin Inc(Total, A) end;
  P2 := procedure(A, B: Integer) begin Inc(Total, A + B) end;
  P3 := procedure(A, B, C: Integer) begin Inc(Total, A + B + C) end;
  P4 := procedure(A, B, C, D: Integer) begin Inc(Total, A + B + C + D) end;
  F0 := function: Integer begin Result := 1 end;
  F1 := function(A: Integer): Integer begin Result := A end;
  F2 := function(A, B: Integer): Integer begin Result := A + B end;
  F3 := function(A, B, C: Integer): Integer begin Result := A + B + C end;
  F4 := function(A, B, C, D: Integer): Integer begin Result := A + B + C + D end;
  Pred := function(A: Integer): Boolean begin Result := A = 42 end;

  P0;
  P1(1);
  P2(1, 2);
  P3(1, 2, 3);
  P4(1, 2, 3, 4);
  If (Total <> 21) or
     (F0 <> 1) or (F1(2) <> 2) or (F2(2, 3) <> 5) or
     (F3(2, 3, 4) <> 9) or (F4(2, 3, 4, 5) <> 14) or
     not Pred(42) or Pred(41) then
    Halt(1);
end.
