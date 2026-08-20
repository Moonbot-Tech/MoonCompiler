{ %CPU=x86_64 }
{ %OPT=-O2 }
program tx86boolconstmovwidth1;

{$mode delphi}

var
  B: Boolean;
  BB: ByteBool;
  WB: WordBool;
  LB: LongBool;
  B2: Boolean;
  N: Integer;

procedure Check(Got, Want: Int64); noinline;
begin
  if Got <> Want then
    Halt(1);
end;

function DynamicWord: WordBool; noinline;
begin
  Result := WordBool($100);
end;

function DynamicFalse: Boolean; noinline;
begin
  Result := False;
end;

begin
  B := True;
  BB := ByteBool(True);
  WB := WordBool(True);
  LB := LongBool(True);
  Check(Ord(B), 1);
  Check(Ord(BB), -1);
  Check(Ord(WB), -1);
  Check(Ord(LB), -1);
  Check(Ord(WB) + Ord(BB) + Ord(LB), -3);
  Check(Ord(WB <> False), 1);
  Check(Ord(WB = True), 1);
  Check(Ord(BB <> False), 1);
  Check(Ord(LB = True), 1);
  Check(Ord(WB = False), 0);
  Check(SizeOf(WB <> False), 2);
  B2 := False;
  Check(Ord(WB <> B2), 1);
  B2 := WB <> False;
  Check(Ord(B2), 1);
  if WB <> False then
    N := 1
  else
    N := 0;
  Check(N, 1);

  { B2 is allocated in the low byte of the same physical register that WB
    subsequently occupies as a word.  The word assignment must not be removed
    merely because both constants are zero: the byte write leaves the high byte
    untouched. }
  WB := WordBool(False);
  Check(Ord(WB <> False), 0);
  Check(Ord(WB = False), 1);

  { A byte-sized false value must not prove a word-sized register zero: the
    high byte remains semantically live for WordBool comparisons. }
  WB := DynamicWord;
  B2 := DynamicFalse;
  Check(Ord(WB <> B2), 1);
end.
