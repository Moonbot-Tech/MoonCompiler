program symbol_address_semantic;

{ The address of a variable of the unit in a register, the register the base
  of the operands which follow: "lea State(%rip),%rax; mov 584(%rax),%rdx;
  mov %rdx,576(%rax)".  The operands name the variable themselves, the
  register is free (x86 peephole: OptPass1LEA, "LeaOp2Op" for the operand of
  one instruction, "LeaOps2Ops" for the operands of several).  An operand
  which took the symbol of the LEA takes the kind of its reference with it;
  without it the operand was not told from another name of the same memory
  and the rules behind stopped at it.

  The forms: a field copied into a field of the same variable, a field
  counted from two fields, a field changed in place by a constant and by a
  register, fields compared, a variable read before another variable is
  written and used behind the write, fields of 1, 2, 4 and 8 bytes, a variable
  of the thread, an element with a constant index, a typed constant.

  The values are those of Delphi 12.2 and of -O1. }

{$mode delphi}{$H+}
{$Q-}{$R-}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  cwstring,
  {$endif UNIX}
  SysUtils;

type
  TState = record
    Pad: array[0..70] of Int64;
    A, B: Int64;
    C: LongInt;
    D: Word;
    E: Byte;
    F: Boolean;
    G: Cardinal;
  end;

  TPair = record
    A, B: Int64;
  end;

  TSmall = record
    A, B, C, D: Int64;
  end;

var
  Fails: Integer = 0;
  State: TState;
  Cell: Int64;
  G: TPair;
  Small: TSmall;
  Table: array[0..7] of TPair;

threadvar
  Local: TPair;

const
  Fixed: TPair = (A: 41; B: 43);

procedure Check(Got, Want: Int64; const Name: string);
begin
  if Got <> Want then
  begin
    WriteLn('FAIL ', Name, ': ', Got, ' <> ', Want);
    Inc(Fails);
  end;
end;

procedure CopyField; noinline;
begin
  State.A := State.B;
end;

procedure StepField; noinline;
begin
  State.A := State.A + State.B;
end;

procedure SumFields; noinline;
begin
  State.A := State.B + State.C + State.D + State.E;
end;

procedure BumpFields; noinline;
begin
  Inc(State.A, 5);
  Dec(State.C, 3);
  Inc(State.D);
  State.E := State.E or 2;
  State.G := State.G xor $FF00FF00;
end;

procedure BumpBy(K: Int64); noinline;
begin
  Inc(State.A, K);
  Inc(State.B, K);
end;

function FieldsEqual: Boolean; noinline;
begin
  Result := (State.A = State.B) and (State.C = 7);
end;

procedure FlagFromFields; noinline;
begin
  State.F := (State.C > 0) and (State.D < 100);
end;

procedure CopySmall; noinline;
begin
  { displacements of one byte: the register stays where the code with the
    symbol in every operand would be longer }
  Small.A := Small.B;
  Small.C := Small.D;
end;

function ShapeOtherName: Int64; noinline;
var
  X, Y: Int64;
begin
  X := Cell;
  G.B := G.B + 5;
  Y := X * 1000;
  Result := Y + G.B;
end;

function ShapeOtherNameTwice: Int64; noinline;
var
  X, Y: Int64;
begin
  X := Cell;
  G.B := G.B + 5;
  G.A := G.A + G.B;
  Y := X * 1000;
  Result := Y + G.A;
end;

function ShapeSameName: Int64; noinline;
var
  X, Y: Int64;
begin
  { the variable which was read is the one which is written }
  X := G.B;
  G.B := G.B + 5;
  Y := X * 1000;
  Result := Y + G.B;
end;

function ThroughPointer(P: PInt64): Int64; noinline;
var
  X: Int64;
begin
  { the pointer may name the variable which was read }
  X := Cell;
  P^ := P^ + 5;
  Result := X * 1000 + Cell;
end;

procedure StepTable; noinline;
begin
  Table[3].A := Table[3].A + Table[5].B;
  Table[5].B := Table[3].A;
end;

function StepLocal: Int64; noinline;
begin
  Local.A := Local.A + Local.B;
  Local.B := Local.A;
  Result := Local.A * 100 + Local.B;
end;

function FromFixed: Int64; noinline;
begin
  State.A := Fixed.A;
  State.B := Fixed.B + State.A;
  Result := State.A * 1000 + State.B;
end;

begin
  State.B := 7;
  CopyField;
  Check(State.A, 7, 'a field is copied into a field');
  StepField;
  Check(State.A, 14, 'a field is counted from itself and a field');
  State.C := -70000;
  State.D := 60000;
  State.E := 200;
  SumFields;
  Check(State.A, 7 - 70000 + 60000 + 200, 'a field is the sum of fields of four sizes');
  State.G := $12345678;
  BumpFields;
  Check(State.A, 7 - 70000 + 60000 + 200 + 5, 'a field grows by a constant');
  Check(State.C, -70003, 'a field of four bytes goes down by a constant');
  Check(State.D, 60001, 'a field of two bytes grows by one');
  Check(State.E, 202, 'a bit of a field of one byte is set');
  Check(State.G, $12345678 xor $FF00FF00, 'bits of a field are turned');
  State.A := 1;
  State.B := 2;
  BumpBy(40);
  Check(State.A * 100 + State.B, 4142, 'two fields grow by a register');
  State.A := 9;
  State.B := 9;
  State.C := 7;
  Check(Ord(FieldsEqual), 1, 'fields are compared');
  State.B := 8;
  Check(Ord(FieldsEqual), 0, 'fields which differ are compared');
  State.D := 60000;
  FlagFromFields;
  Check(Ord(State.F), 0, 'a flag is counted from fields');
  State.D := 60;
  FlagFromFields;
  Check(Ord(State.F), 1, 'a flag is counted from fields again');

  Small.B := 5;
  Small.D := 6;
  CopySmall;
  Check(Small.A * 10 + Small.C, 56, 'fields at the start of a variable are copied');

  Cell := 7;
  G.A := 1;
  G.B := 2;
  Check(ShapeOtherName, 7007, 'a variable is read, another one is written');
  Check(ShapeOtherNameTwice, 7013, 'a variable is read, two others are written');
  G.B := 2;
  Check(ShapeSameName, 2007, 'the variable which was read is written');
  Cell := 7;
  Check(ThroughPointer(@Cell), 7012, 'the variable which was read is written through a pointer');

  Table[3].A := 30;
  Table[5].B := 12;
  StepTable;
  Check(Table[3].A * 100 + Table[5].B, 4242, 'elements with a constant index');

  Local.A := 3;
  Local.B := 4;
  Check(StepLocal, 707, 'a variable of the thread');
  Check(FromFixed, 41084, 'a typed constant');

  if Fails = 0 then
    WriteLn('SYMBOL_ADDRESS_PASS')
  else
  begin
    WriteLn('SYMBOL_ADDRESS_FAIL ', Fails);
    Halt(1);
  end;
end.
