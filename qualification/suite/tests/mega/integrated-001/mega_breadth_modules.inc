{ These forms deliberately use declarations and inline bodies from a
  compiled companion unit. }

procedure RunBreadthUnitMutation;
const
  Changes: array[0..4] of Integer = (7, -4, 13, -17, 23);
  Partial: array[0..4] of Integer = (34, 94, 167, 300, 379);
var
  I, Score: Integer;
begin
  BreadthUnitCoefficient := Integer(OpaqueI(9));
  Score := 0;
  for I := Low(Changes) to High(Changes) do
  begin
    Score := Score + (I + 2) * BreadthUnitCoefficient;
    BreadthChangeCoefficient(Changes[I]);
    Score := Score + BreadthUnitCoefficient;
    Check(Score = Partial[I], 'breadth-module-coefficient-checkpoint');
  end;
  Check(BreadthUnitCoefficient = 31, 'breadth-module-coefficient-final');
  Mix(UInt64(Score));
end;

procedure RunBreadthUnitAlias;
const
  Inputs: array[0..4] of Int64 = (32767, 32768, 65535, -4294967297, Int64($177000000000FF98));
  Widths: array[0..4] of UInt64 = ($2470A5027FFF, $2470A5028000, $2470A502FFFF, $2470A502FFFF, $2470A502FF98);
  Signed: array[0..4] of Integer = (32767, -32768, -1, -1, -104);
var
  I: Integer;
  V: TBreadthUnitCode;
  Key: UInt64;
begin
  for I := Low(Inputs) to High(Inputs) do
  begin
    V := BreadthUnitDecode(OpaqueI(Inputs[I]));
    Key := UInt64($2470A5000000) or (UInt64(SizeOf(V)) shl 16) or UInt64(Word(V));
    Check(Key = Widths[I], 'breadth-module-distinct-alias-width-and-cast');
    Check(SmallInt(V) = Signed[I], 'breadth-module-distinct-alias-signed-read');
    Mix(Key);
  end;
end;

procedure RunBreadthUnitPrivateState;
var
  First, Second: TBreadthUnitStamp;
begin
  BreadthResetSequence(Integer(OpaqueI(11)));
  First := BreadthNextStamp(AnsiString('one'), Integer(OpaqueI(-3)));
  Check((First.Data = 8000000053) and (First.LabelText = AnsiString('one!')), 'breadth-module-inline-first-result');
  Check(BreadthReadSequence = 8, 'breadth-module-inline-updates-private-state');
  Second := BreadthNextStamp(First.LabelText, Integer(OpaqueI(12)));
  Check((Second.Data = 20000000152) and (Second.LabelText = AnsiString('one!!')), 'breadth-module-inline-managed-result');
  Check((BreadthReadSequence = 20) and (First.LabelText = AnsiString('one!')), 'breadth-module-inline-uses-same-storage');
  Mix(UInt64(Second.Data));
end;

procedure RunBreadthModuleForms;
begin
  RunBreadthUnitMutation;
  RunBreadthUnitAlias;
  RunBreadthUnitPrivateState;
end;
