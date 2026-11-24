{ A single expression keeps distinct target addresses live until the innermost
  argument returns. A stack reload for any of these addresses belongs before
  the entire atomic instruction. No worker threads or timing assumptions. }
type
  TMegaAtomicRow = class
    Guard: Int64;
    Count: Integer;
    Wide: Int64;
  end;
  TMegaAtomicRows = array[0..19] of TMegaAtomicRow;

var
  MegaAtomicStatic: Integer;
threadvar
  MegaAtomicLocal: Int64;

{$ifdef FPC}
{$if FPC_FULLVERSION < 30301}
function AtomicCmpExchange(var Target: Integer; Value, Expected: Integer): Integer; overload; inline;
begin
  Result := InterlockedCompareExchange(Target, Value, Expected);
end;

function AtomicIncrement(var Target: Integer; Delta: Integer): Integer; overload; inline;
begin
  Result := InterlockedExchangeAdd(Target, Delta) + Delta;
end;

function AtomicCmpExchange(var Target: Int64; Value, Expected: Int64): Int64; overload; inline;
begin
  Result := InterlockedCompareExchange64(Target, Value, Expected);
end;

function AtomicDecrement(var Target: Int64): Int64; overload; inline;
begin
  Result := InterlockedDecrement64(Target);
end;

function AtomicCmpExchange(var Target: Pointer; Value, Expected: Pointer; out Succeeded: Boolean): Pointer; overload; inline;
begin
  Result := InterlockedCompareExchange(Target, Value, Expected);
  Succeeded := Result = Expected;
end;

function AtomicExchange(var Target: Pointer; Value: Pointer): Pointer; inline;
begin
  Result := InterlockedExchange(Target, Value);
end;
{$endif}
{$endif}

function CascadeCompare(const Rows: TMegaAtomicRows; Written, Expected: Integer): Integer;
begin
  Result :=
    AtomicCmpExchange(Rows[0].Count, Written,
    AtomicCmpExchange(Rows[1].Count, Written,
    AtomicCmpExchange(Rows[2].Count, Written,
    AtomicCmpExchange(Rows[3].Count, Written,
    AtomicCmpExchange(Rows[4].Count, Written,
    AtomicCmpExchange(Rows[5].Count, Written,
    AtomicCmpExchange(Rows[6].Count, Written,
    AtomicCmpExchange(Rows[7].Count, Written,
    AtomicCmpExchange(Rows[8].Count, Written,
    AtomicCmpExchange(Rows[9].Count, Written,
    AtomicCmpExchange(Rows[10].Count, Written,
    AtomicCmpExchange(Rows[11].Count, Written,
    AtomicCmpExchange(Rows[12].Count, Written,
    AtomicCmpExchange(Rows[13].Count, Written,
    AtomicCmpExchange(Rows[14].Count, Written,
    AtomicCmpExchange(Rows[15].Count, Written,
    AtomicCmpExchange(Rows[16].Count, Written,
    AtomicCmpExchange(Rows[17].Count, Written,
    AtomicCmpExchange(Rows[18].Count, Written,
    AtomicCmpExchange(Rows[19].Count, Written, Expected))))))))))))))))))));
end;

function CascadeAdd(const Rows: TMegaAtomicRows; Delta: Integer): Integer;
begin
  Result :=
    AtomicIncrement(Rows[0].Count,
    AtomicIncrement(Rows[1].Count,
    AtomicIncrement(Rows[2].Count,
    AtomicIncrement(Rows[3].Count,
    AtomicIncrement(Rows[4].Count,
    AtomicIncrement(Rows[5].Count,
    AtomicIncrement(Rows[6].Count,
    AtomicIncrement(Rows[7].Count,
    AtomicIncrement(Rows[8].Count,
    AtomicIncrement(Rows[9].Count,
    AtomicIncrement(Rows[10].Count,
    AtomicIncrement(Rows[11].Count,
    AtomicIncrement(Rows[12].Count,
    AtomicIncrement(Rows[13].Count,
    AtomicIncrement(Rows[14].Count,
    AtomicIncrement(Rows[15].Count,
    AtomicIncrement(Rows[16].Count,
    AtomicIncrement(Rows[17].Count,
    AtomicIncrement(Rows[18].Count,
    AtomicIncrement(Rows[19].Count, Delta))))))))))))))))))));
end;

{ A read-only observation of the same kind as an order-count check. The
  failed comparison must return the actual count in the accumulator. }
function ObserveAtomicCount(Row: TMegaAtomicRow): Integer;
begin
  Result := AtomicCmpExchange(Row.Count, 0, 0);
end;

function TryReplaceWide(var Target: Int64; Expected, Replacement: Int64): Boolean;
begin
  Result := AtomicCmpExchange(Target, Replacement, Expected) = Expected;
end;

procedure CheckPublishedRow(First, Second: TMegaAtomicRow);
var
  Published, Old: Pointer;
  Changed: Boolean;
begin
  Published := Pointer(First);
  Changed := True;
  Old := AtomicCmpExchange(Published, nil, Pointer(Second), Changed);
  Check((not Changed) and (Old = Pointer(First)) and (Published = Old), 'atomic-pointer-failed-publication');
  Old := AtomicCmpExchange(Published, Pointer(Second), Old, Changed);
  Check(Changed and (Old = Pointer(First)) and (Published = Pointer(Second)), 'atomic-pointer-publication');
  Old := AtomicExchange(Published, nil);
  Check((Old = Pointer(Second)) and (Published = nil), 'atomic-pointer-retire');
end;

procedure CheckAtomicRows(const Rows: TMegaAtomicRows);
var
  I, Before, Expected, Actual: Integer;
  WideBefore: Int64;
begin
  for I := Low(Rows) to High(Rows) do
  begin
    Rows[I].Count := 11;
    Rows[I].Wide := (Int64(1) shl 36) + I;
    Rows[I].Guard := -101 - I;
  end;

  Check(CascadeCompare(Rows, 73, 11) = 11, 'atomic-nested-cas-return');
  for I := Low(Rows) to High(Rows) do
    Check(Rows[I].Count = 73, 'atomic-nested-cas-field');

  { Only the innermost comparison misses. Its old value feeds the next CAS. }
  Check(CascadeCompare(Rows, -3, 0) = 73, 'atomic-nested-cas-miss-return');
  Check(Rows[High(Rows)].Count = 73, 'atomic-nested-cas-miss-field');
  for I := Low(Rows) to High(Rows) - 1 do
    Check(Rows[I].Count = -3, 'atomic-nested-cas-following-hit');

  for I := Low(Rows) to High(Rows) do
    Rows[I].Count := I - 7;
  Actual := CascadeAdd(Rows, 5);
  Expected := 5;
  for I := High(Rows) downto Low(Rows) do
  begin
    Expected := Expected + I - 7;
    Check(Rows[I].Count = Expected, 'atomic-nested-xadd-field');
  end;
  Check(Actual = Expected, 'atomic-nested-xadd-return');
  CheckPublishedRow(Rows[Low(Rows)], Rows[High(Rows)]);

  for I := Low(Rows) to High(Rows) do
  begin
    Before := Rows[I].Count;
    WideBefore := (Int64(1) shl 36) + I;
    Check(AtomicCmpExchange(Rows[I].Wide, WideBefore + Before, WideBefore) = WideBefore, 'atomic-wide-cas-index');
    Check(AtomicDecrement(Rows[I].Wide) = WideBefore + Before - 1, 'atomic-wide-decrement');
    Check(Rows[I].Wide = WideBefore + Before - 1, 'atomic-wide-memory');
    WideBefore := WideBefore + Before - 1;
    Check(not TryReplaceWide(Rows[I].Wide, WideBefore xor (Int64(1) shl 40), -2), 'atomic-wide-high-miss');
    Check(Rows[I].Wide = WideBefore, 'atomic-wide-miss-no-write');
    Check(TryReplaceWide(Rows[I].Wide, WideBefore, -2), 'atomic-wide-replace-hit');
    Check(Rows[I].Wide = -2, 'atomic-wide-replace-memory');
    Check(ObserveAtomicCount(Rows[I]) = Before, 'atomic-observe-field');
    Check(Rows[I].Guard = -101 - I, 'atomic-address-neighbour');
  end;
end;

procedure RunAtomicAddressForms;
var
  Rows: TMegaAtomicRows;
  I: Integer;
begin
  MegaAtomicStatic := 27;
  MegaAtomicLocal := Int64(1) shl 40;
  Check(AtomicCmpExchange(MegaAtomicStatic, 13, 27) = 27, 'atomic-static-relocation');
  Check(AtomicCmpExchange(MegaAtomicLocal, 59, Int64(1) shl 40) = Int64(1) shl 40, 'atomic-threadlocal-address');
  Check((MegaAtomicStatic = 13) and (MegaAtomicLocal = 59), 'atomic-static-threadlocal-distinct');

  Rows := Default(TMegaAtomicRows);
  try
    for I := Low(Rows) to High(Rows) do
      Rows[I] := TMegaAtomicRow.Create;
    CheckAtomicRows(Rows);
  finally
    for I := Low(Rows) to High(Rows) do
      Rows[I].Free;
  end;
end;
