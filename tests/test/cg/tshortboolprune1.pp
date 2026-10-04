{ %CPU=x86_64 }
{ %OPT=-O3 }

program tshortboolprune1;

{ With short boolean evaluation a constant on the left that decides the result
  means the right operand is never evaluated: dropping it drops nothing
  observable, whatever it contains (a field of a possibly nil object, a call).
  With complete evaluation the right operand is evaluated, so its call has to
  stay.

  The generic class is the shape of TList<T>.IndexOf: the kind of T is a
  constant of the specialization and stands first, the run-time flag behind it;
  the arm of the other kinds has to disappear from the specialization. }

{$mode delphi}
{ The pruned operand was never a constant condition of the source: no `unreachable
  code` warning may come with the prune (the compiler builds itself with -Sew). }
{$warn 6018 error}

uses
  SysUtils;

const
  NeverTrue = SizeOf(LongInt) = 8;
  AlwaysTrue = SizeOf(LongInt) = 4;

type
  TFlagHolder = class
    Flag: Boolean;
  end;

  TBox<T> = class
    FUseDefault: Boolean;
    FCount: LongInt;
    function Pick(const Value: T): LongInt;
  end;

var
  Calls: LongInt;

function Touch: Boolean; noinline;
begin
  Inc(Calls);
  Result := True;
end;

function StringArm(Index: LongInt): LongInt; noinline;
begin
  Result := 1 + Index * 0;
end;

function OrdinalArm(Index: LongInt): LongInt; noinline;
begin
  Result := 2 + Index * 0;
end;

function GenericArm: LongInt; noinline;
begin
  Result := 3;
end;

function TBox<T>.Pick(const Value: T): LongInt;
var
  I: LongInt;
begin
  If (GetTypeKind(T) = tkUString) and FUseDefault then
  begin
    { an arm with a loop and calls, like the UnicodeString search of IndexOf:
      found dead only by the code generator it stays in the routine as
      unreachable code and costs every kind its registers and frame }
    for I := 0 to FCount - 1 do
      If StringArm(I) = 1 then
        Exit(1);
    Exit(-1);
  end;
  If (GetTypeKind(T) in [tkInteger, tkInt64]) and (SizeOf(T) in [4, 8]) and
     FUseDefault then
  begin
    for I := 0 to FCount - 1 do
      If OrdinalArm(I) = 2 then
        Exit(2);
    Exit(-1);
  end;
  Result := GenericArm;
end;

{$B-}
function ShortAndField(Holder: TFlagHolder): LongInt; noinline;
begin
  If NeverTrue and Holder.Flag then
    Result := 1
  else
    Result := 2;
end;

function ShortOrField(Holder: TFlagHolder): LongInt; noinline;
begin
  If AlwaysTrue or Holder.Flag then
    Result := 1
  else
    Result := 2;
end;

function ShortAndCall: LongInt; noinline;
begin
  If NeverTrue and Touch then
    Result := 1
  else
    Result := 2;
end;

function ShortOrCall: LongInt; noinline;
begin
  If AlwaysTrue or Touch then
    Result := 1
  else
    Result := 2;
end;

{$B+}
function CompleteAndField(Holder: TFlagHolder): LongInt; noinline;
begin
  If NeverTrue and Holder.Flag then
    Result := 1
  else
    Result := 2;
end;

function CompleteOrField(Holder: TFlagHolder): LongInt; noinline;
begin
  If AlwaysTrue or Holder.Flag then
    Result := 1
  else
    Result := 2;
end;

function CompleteAndCall: LongInt; noinline;
begin
  If NeverTrue and Touch then
    Result := 1
  else
    Result := 2;
end;

function CompleteOrCall: LongInt; noinline;
begin
  If AlwaysTrue or Touch then
    Result := 1
  else
    Result := 2;
end;
{$B-}

var
  IntegerBox: TBox<LongInt>;
  StringBox: TBox<UnicodeString>;
  DoubleBox: TBox<Double>;
  Holder: TFlagHolder;
begin
  Holder := TFlagHolder.Create;
  Holder.Flag := True;
  If (ShortAndField(nil) <> 2) or (ShortOrField(nil) <> 1) or
     (ShortAndField(Holder) <> 2) or (ShortOrField(Holder) <> 1) then
    Halt(1);
  Calls := 0;
  If (ShortAndCall <> 2) or (ShortOrCall <> 1) or (Calls <> 0) then
    Halt(2);
  If (CompleteAndField(Holder) <> 2) or (CompleteOrField(Holder) <> 1) then
    Halt(3);
  Calls := 0;
  If (CompleteAndCall <> 2) or (CompleteOrCall <> 1) or (Calls <> 2) then
    Halt(5);

  IntegerBox := TBox<LongInt>.Create;
  StringBox := TBox<UnicodeString>.Create;
  DoubleBox := TBox<Double>.Create;
  try
    If (IntegerBox.Pick(7) <> 3) or (StringBox.Pick('x') <> 3) or
       (DoubleBox.Pick(1.5) <> 3) then
      Halt(6);
    IntegerBox.FCount := 4;
    StringBox.FCount := 4;
    DoubleBox.FCount := 4;
    IntegerBox.FUseDefault := True;
    StringBox.FUseDefault := True;
    DoubleBox.FUseDefault := True;
    If (IntegerBox.Pick(7) <> 2) or (StringBox.Pick('x') <> 1) or
       (DoubleBox.Pick(1.5) <> 3) then
      Halt(7);
  finally
    IntegerBox.Free;
    StringBox.Free;
    DoubleBox.Free;
    Holder.Free;
  end;
end.
