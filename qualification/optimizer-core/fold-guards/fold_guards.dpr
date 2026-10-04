program fold_guards;
{ A fold asks the question of what it does with an evaluation
  (compiler/nutils.pas, might_have_sideeffects):
  - one evaluation where the source has two, or two where it has one: only
    effects matter, the first evaluation raises what the source raises;
  - no evaluation where the source has one: effects and the exceptions the
    program asked for (enabled checks, division, floating point) - not the
    fault of a memory access whose value is not used;
  - an evaluation where the source has none (a short-circuit operand made
    unconditional): also the fault of a memory access.
  Run at -O2 and -O3: values, no fault where a short-circuit guards an
  access, ERangeError of checked operands, 0*x of a real kept without fast
  math.  run_fold_guards_gate.py reads the folds in the -O3 object.  The
  file sets no range or overflow switch: the gate builds it without checks,
  as the product profile does, and again with -Cr -Co, where every operand
  keeps its check. }
{$mode delphi}
uses
  SysUtils, TypInfo, Math;

type
  PNode = ^TNode;
  TNode = record
    X: Integer;
    Count: Int64;
    Flag: Boolean;
    Value: QWord;
  end;

  TBox<T> = class
    FFlag: Boolean;
    function FieldFirst(const A: T): Integer;
  end;

var
  Text: array of AnsiChar;
  Checked: array of Integer;
  Reals: array of Double;
  Calls: Integer;

function Ext(P: Pointer): Integer; noinline;
begin
  Inc(Calls);
  Result := PByte(P)^ + 1;
end;

{ the decision is known for T = UnicodeString: no arm, no call }
function TBox<T>.FieldFirst(const A: T): Integer;
begin
  If FFlag and (GetTypeKind(T) in [tkInt64, tkQWord]) then
    Exit(Ext(@A));
  Result := 7;
end;

{ one evaluation for two: one unsigned compare of the element }
function IsDigitAt(I: Integer): Boolean; noinline;
begin
  Result := (Text[I] >= '0') and (Text[I] <= '9');
end;

{ one evaluation for two: x and x is x (the value; common subexpression
  elimination gave the same code before) }
function SameTwice(P: PNode): Integer; noinline;
begin
  Result := P^.X and P^.X;
end;

{ one evaluation for two: the rotate }
function RotateField(P: PNode): QWord; noinline;
begin
  Result := (P^.Value shl P^.Count) or (P^.Value shr (64 - P^.Count));
end;

{ one evaluation for two: n - n mod c }
function RoundDown(P: PNode): Integer; noinline;
begin
  Result := P^.X - P^.X mod 8;
end;

{ no evaluation for one: the value of the access is not needed }
function DropProduct(P: PNode): Integer; noinline;
begin
  Result := P^.X * 0 + 7;
end;

function DropDifference(P: PNode): Integer; noinline;
begin
  Result := P^.X - P^.X;
end;

{ an evaluation where the source has none: the short-circuit guards the
  access, it stays guarded }
function GuardedFlag(P: PNode): Boolean; noinline;
begin
  Result := (P <> nil) and P^.Flag;
end;

function KindGuard(K: Integer; P: PNode): Boolean; noinline;
begin
  Result := (K = 1) and (P^.X = 5);
end;

function SelectGuard(A, C: Boolean; P: PNode): Boolean; noinline;
begin
  Result := (A and P^.Flag) or (C and not P^.Flag);
end;

{ 0*x of a real is not 0 for a NaN x: only fast math folds it }
function ZeroTimes(I: Integer): Double; noinline;
begin
  Result := 0.0 * Reals[I];
end;

{$push}{$R+}
{ checked operands keep their exception: one evaluation for two raises in
  the kept evaluation, a dropped evaluation is not dropped }
function CheckedIsDigit(I: Integer): Boolean; noinline;
begin
  Result := (Checked[I] >= 0) and (Checked[I] <= 9);
end;

function CheckedDrop(I: Integer): Integer; noinline;
begin
  Result := Checked[I] and 0;
end;
{$pop}

function Raises(Code: Integer): Boolean;
begin
  Result := False;
  try
    case Code of
      1: CheckedIsDigit(Length(Checked));
      2: CheckedDrop(Length(Checked));
    end;
  except
    on ERangeError do
      Result := True;
  end;
end;

var
  Node: TNode;
  Box: TBox<UnicodeString>;
  S: UnicodeString;
begin
  SetLength(Text, 3);
  Text[0] := '5';
  Text[1] := 'a';
  Text[2] := '/';
  If not IsDigitAt(0) or IsDigitAt(1) or IsDigitAt(2) then
    Halt(1);
  Node.X := 1234;
  Node.Count := 8;
  Node.Value := $0123456789ABCDEF;
  Node.Flag := True;
  If SameTwice(@Node) <> 1234 then
    Halt(2);
  If RotateField(@Node) <> $23456789ABCDEF01 then
    Halt(3);
  If RoundDown(@Node) <> 1232 then
    Halt(4);
  If (DropProduct(@Node) <> 7) or (DropDifference(@Node) <> 0) then
    Halt(5);
  If GuardedFlag(nil) or not GuardedFlag(@Node) then
    Halt(6);
  If KindGuard(2, nil) then
    Halt(7);
  Node.X := 5;
  If not KindGuard(1, @Node) then
    Halt(8);
  If SelectGuard(False, False, nil) or not SelectGuard(True, False, @Node) or SelectGuard(False, True, @Node) then
    Halt(9);
  SetLength(Reals, 1);
  Reals[0] := NaN;
  If not IsNan(ZeroTimes(0)) then
    Halt(10);
  SetLength(Checked, 1);
  Checked[0] := 4;
  If not CheckedIsDigit(0) or (CheckedDrop(0) <> 0) then
    Halt(11);
  If not Raises(1) or not Raises(2) then
    Halt(12);
  Box := TBox<UnicodeString>.Create;
  Box.FFlag := ParamCount = 0;
  S := 'a';
  Calls := 0;
  If (Box.FieldFirst(S) <> 7) or (Calls <> 0) then
    Halt(13);
  FreeAndNil(Box);
  Writeln('FOLD_GUARDS_PASS');
end.
