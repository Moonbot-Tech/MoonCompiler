program tlist_operator_records_semantic;

{ dvl-0059: the list's operations follow the "every capacity slot is
  alive" model of the backing dynamic array.  The user-visible hooks
  match DCC64 byte for byte where they are contractual: an insertion
  initializes the vacated gap and assigns into it (i then a), a
  deletion finalizes the removed value, moves ownership and re-births
  the vacated tail slot (f then i) - with no snapshot copy pair when
  nobody subscribed.  Growth cadence, read-copy temporaries and the
  shrink canvas differ from the Delphi RTL internals by design (library
  canvas is not a language contract); values agree for a normally
  copying Assign, and the birth/burial balance holds.  The delete axis
  matches byte for byte as well: the inlined Delete used to charge each
  caller frame a prologue temp pair for the discarded DoRemove result -
  moving the slow arm into the non-inlined DeleteFallback removed it
  (meta-audit of dvl-0059). }

{$APPTYPE CONSOLE}

uses
  {$ifdef FPC}
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  {$endif UNIX}
  {$endif FPC}
  SysUtils, Generics.Collections;

var
  Trace: string;

type
  TRes = record
    Slot: Integer;
    class operator Initialize(out Dest: TRes);
    class operator Finalize(var Dest: TRes);
    class operator Assign(var Dest: TRes; const [ref] Src: TRes);
  end;

class operator TRes.Initialize(out Dest: TRes);
begin
  Dest.Slot := 100;
  Trace := Trace + 'i';
end;

class operator TRes.Finalize(var Dest: TRes);
begin
  Trace := Trace + 'f' + IntToStr(Dest.Slot);
end;

class operator TRes.Assign(var Dest: TRes; const [ref] Src: TRes);
begin
  Dest.Slot := Src.Slot + 1;
  Trace := Trace + 'a';
end;

procedure Check(const Name, Expected: string);
begin
  If Trace <> Expected then
    raise Exception.CreateFmt('%s: "%s" expected "%s"', [Name, Trace, Expected]);
  Trace := '';
end;

procedure InsertHooks;
var
  L: TList<TRes>;
  R: TRes;
begin
  R.Slot := 5;
  L := TList<TRes>.Create;
  try
    Trace := Trace + '|';
    L.Add(R);
    Trace := Trace + '|';
    L.Insert(0, R);
    Trace := Trace + '|';
  finally
    L.Free;
  end;
end;

procedure DeleteHooks;
var
  L: TList<TRes>;
  R: TRes;
begin
  R.Slot := 5;
  L := TList<TRes>.Create;
  try
    Trace := Trace + '|';
    L.Add(R);
    Trace := Trace + '|';
    L.Delete(0);
    Trace := Trace + '|';
  finally
    L.Free;
  end;
end;

type
  { wide enough to dodge DCC64's pointer-sized managed-array crash
    (probe arrpair_ptrsize): the oracle must run to be an oracle }
  TQuad = array[0..3] of TRes;

procedure ArrayPairHooks;
var
  L: TList<TQuad>;
  P, Q: TQuad;
begin
  P[0].Slot := 5;
  P[1].Slot := 7;
  P[2].Slot := 9;
  P[3].Slot := 11;
  Q[0].Slot := 20;
  Q[1].Slot := 30;
  Q[2].Slot := 40;
  Q[3].Slot := 50;
  L := TList<TQuad>.Create;
  try
    Trace := Trace + '|';
    L.Add(P);
    Trace := Trace + '|';
    L.InsertRange(0, [Q]);
    Trace := Trace + '|';
  finally
    L.Free;
  end;
end;

procedure MoveHooks;
var
  L: TList<TRes>;
  R: TRes;
  V0, V1, V2: Integer;
begin
  R.Slot := 5;
  L := TList<TRes>.Create;
  try
    L.Add(R);
    R.Slot := 40;
    L.Add(R);
    R.Slot := 70;
    L.Add(R);
    { a reorder is an ownership transfer: DCC64 runs NO user operator in
      Move - the contract is the empty trace }
    Trace := '';
    L.Move(0, 2);
    Check('move hooks', '');
    V0 := L[0].Slot;
    V1 := L[1].Slot;
    V2 := L[2].Slot;
    { reading L[i] costs each compiler its own copy canvas, identical for
      all three reads - pairwise differences cancel it, pinning the
      reordered 40,70,5 exactly }
    If (V0 - V1 <> -30) or (V1 - V2 <> 65) then
      raise Exception.CreateFmt('move order: %d:%d:%d', [V0, V1, V2]);
    Trace := '';
  finally
    L.Free;
  end;
  Trace := '';
end;

procedure BalanceScan;
var
  K, Births, Burials: Integer;
begin
  Births := 0;
  Burials := 0;
  for K := 1 to Length(Trace) do
    case Trace[K] of
      'i': Inc(Births);
      'f': Inc(Burials);
    end;
  { Every initialized capacity slot is buried exactly once.  DCC64 silently
    overwrites three idle slots in this scenario, but reproducing that leak
    is not a language contract and is observably wrong for an Initialize
    operator which owns a resource. }
  If Births <> Burials then
    raise Exception.CreateFmt('balance: %d births vs %d burials (delta %d, expected 0) in "%s"',
      [Births, Burials, Births - Burials, Trace]);
  Trace := '';
end;

procedure FullLifecycleBalance;
var
  L: TList<TRes>;
  R: TRes;
  Pair: array[0..1] of TRes;
begin
  R.Slot := 5;
  Pair[0].Slot := 20;
  Pair[1].Slot := 30;
  L := TList<TRes>.Create;
  try
    L.Add(R);
    L.Insert(0, R);
    L.InsertRange(1, Pair);
    L.Delete(0);
    L.DeleteRange(0, 2);
    L.Clear;
    L.Add(R);
  finally
    L.Free;
  end;
end;

begin
  try
    Trace := '';
    InsertHooks;
    {$ifdef FPC}
    Check('insert hooks', 'i|iiiia|f100ia|f6f6iif100f100f100f100f5');
    {$else}
    Check('insert hooks', 'i|iiiia|ia|f6f6iif100f100f100f100f5');
    {$endif}

    Trace := '';
    DeleteHooks;
    Check('delete hooks', 'i|iiiia|f6i|f100f100f100f100f5');

    { a static ARRAY of operator records: the LDirect byte arm must stay
      away from it just like from a bare record - the whole trace matches
      DCC64 byte for byte, growth and teardown included (the original gate
      excluded only tkRecord, so tkArray slipped into Move+addref and the
      operators never ran - meta-audit of dvl-0059) }
    Trace := '';
    ArrayPairHooks;
    {$ifdef FPC}
    Check('array pair hooks',
      'iiiiiiii|iiiiiiiiiiiiiiiiaaaa|f100f100f100f100iiiiaaaa|f21f31f41f51f6f8f10f12' +
      'iiiiiiiif100f100f100f100f100f100f100f100f100f100f100f100f100f100f100f100' +
      'f20f30f40f50f5f7f9f11');
    {$else}
    Check('array pair hooks',
      'iiiiiiii|iiiiiiiiiiiiiiiiaaaa|iiiiaaaa|f21f31f41f51f6f8f10f12' +
      'iiiiiiiif100f100f100f100f100f100f100f100f100f100f100f100f100f100f100f100' +
      'f20f30f40f50f5f7f9f11');
    {$endif}

    MoveHooks;

    { the full mixed lifecycle: no zero-slot burials and no leak of idle
      capacity slots; unlike DCC64, the FPC branch requires strict balance }
    Trace := '';
    FullLifecycleBalance;
    BalanceScan;

    WriteLn('TLIST_OPERATOR_RECORDS_OK');
  except
    on E: Exception do begin
      WriteLn('TLIST_OPERATOR_RECORDS_FAIL ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
