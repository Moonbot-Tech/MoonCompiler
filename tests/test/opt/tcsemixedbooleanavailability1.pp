{ %OPT=-O2 -OoNODFA }
program tcsemixedbooleanavailability1;

{$mode objfpc}{$inline off}

type
  TPair = record A, B: LongInt; end;
  PPair = ^TPair;

var
  P: PPair;
  Gate, Tail: Boolean;

{ Keep the loads under the same local switches: changing switches on the
  entire right operand would make them unequal before availability is tested.
  The trailing B+ belongs to the enclosing operator, created after its RHS.
  Unused zero arguments prevent a stale incoming register from accidentally
  containing P and hiding the missing load. No invalid pointer is supplied. }
function TestAnd(Unused1, Unused2, Unused3: PtrUInt): Boolean; noinline;
begin
  Result := ((Gate {$B-} and (P^.B = 17)) {$B-} and ((P^.A = 31) {$B+})) {$B-} and Tail;
end;

function TestOr(Unused1, Unused2, Unused3: PtrUInt): Boolean; noinline;
begin
  Result := ((Gate {$B-} or (P^.B = 17)) {$B-} or ((P^.A = 31) {$B+})) {$B-} or Tail;
end;

var
  G, T, A, B: LongInt;
  GotAnd, GotOr, WantAnd, WantOr: Boolean;
begin
  New(P);
  for G := 0 to 1 do
    for T := 0 to 1 do
      for A := 30 to 31 do
        for B := 16 to 17 do
          begin
            Gate := G <> 0;
            Tail := T <> 0;
            P^.A := A;
            P^.B := B;
            GotAnd := TestAnd(0, 0, 0);
            GotOr := TestOr(0, 0, 0);
            WantAnd := False;
            if G <> 0 then
              if T <> 0 then
                if A = 31 then
                  if B = 17 then WantAnd := True;
            WantOr := False;
            if G <> 0 then WantOr := True;
            if T <> 0 then WantOr := True;
            if A = 31 then WantOr := True;
            if B = 17 then WantOr := True;
            if GotAnd <> WantAnd then Halt(1);
            if GotOr <> WantOr then Halt(2);
          end;
  Dispose(P);
  WriteLn('ok');
end.
