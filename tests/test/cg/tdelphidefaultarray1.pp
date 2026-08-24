{ %OPT=-O2 }
program tdelphidefaultarray1;

{$ifdef FPC}
  {$mode delphi}
  {$modeswitch advancedrecords}
  {$modeswitch implicitgenerics}
{$endif FPC}

type
  TValue = record
    Slot: Integer;
    class operator Initialize(out Dest: TValue);
    class operator Finalize(var Dest: TValue);
    class operator Assign(var Dest: TValue; const [ref] Src: TValue);
  end;
  TPair = array[0..1] of TValue;
  TAssignOnly = record
    Slot: Integer;
    class operator Assign(var Dest: TAssignOnly;
      const [ref] Src: TAssignOnly);
  end;
  TAssignOnlyPair = array[0..1] of TAssignOnly;
  TMatrix = array[0..1] of TPair;
  TReset = class sealed
  public
    class procedure ToDefault<T>(var Dest: T); static;
  end;

var
  Calls: Integer;

class operator TValue.Initialize(out Dest: TValue);
begin
  Dest.Slot := 100;
end;

class operator TValue.Finalize(var Dest: TValue);
begin
  Dest.Slot := -1;
end;

class operator TValue.Assign(var Dest: TValue; const [ref] Src: TValue);
begin
  Dest.Slot := Src.Slot + 1;
end;

class operator TAssignOnly.Assign(var Dest: TAssignOnly;
  const [ref] Src: TAssignOnly);
begin
  Dest.Slot := Src.Slot + 1;
end;

class procedure TReset.ToDefault<T>(var Dest: T);
begin
  Dest := Default(T);
end;

function Pick: Integer;
begin
  Result := Calls;
  Inc(Calls);
end;

procedure Check(Condition: Boolean);
begin
  if not Condition then
    Halt(1);
end;

var
  Pair: TPair;
  AssignOnlyPair: TAssignOnlyPair;
  Matrix: TMatrix;
begin
  Pair[0].Slot := 10;
  Pair[1].Slot := 11;
  Pair := Default(TPair);
  Check((Pair[0].Slot = 100) and (Pair[1].Slot = 100));

  AssignOnlyPair[0].Slot := 12;
  AssignOnlyPair[1].Slot := 13;
  AssignOnlyPair := Default(TAssignOnlyPair);
  Check((AssignOnlyPair[0].Slot = 0) and (AssignOnlyPair[1].Slot = 0));

  Matrix[0][0].Slot := 20;
  Matrix[0][1].Slot := 21;
  Matrix[1][0].Slot := 30;
  Matrix[1][1].Slot := 31;
  Calls := 0;
  Matrix[Pick] := Default(TPair);
  Check(Calls = 1);
  Check((Matrix[0][0].Slot = 100) and (Matrix[0][1].Slot = 100));
  Check((Matrix[1][0].Slot = 30) and (Matrix[1][1].Slot = 31));

  Pair[0].Slot := 40;
  Pair[1].Slot := 41;
  TReset.ToDefault<TPair>(Pair);
  Check((Pair[0].Slot = 100) and (Pair[1].Slot = 100));
end.
