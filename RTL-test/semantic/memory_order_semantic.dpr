program memory_order_semantic;

{ Two names of one memory.  The x86 peephole moves a read of memory down to
  the instruction which uses the value ("mov (%rcx),%rax ... imul
  $1000,%rax,%rdx" is "imul $1000,(%rcx),%rdx"), merges two loads and two
  stores of 8 bytes into one of 16, takes a second read of a cell from the
  register of the first.  On -O3 the instructions need not be adjacent, and
  what stands between them may write the memory.  The question "was it
  written" counted only a write through the same address expression: a
  write to a variable by its name was no write to what a pointer looks at,
  a write through one pointer no write to the target of another.

  Wrong before the repair:
  PointerThenName    X := P^; Cell := Cell + 5; Y := X * 1000        (-O3)
  BitOfOldValue      X := P^; Cell := Cell or 4; if (X and 4) <> 0   (-O3)
  ShiftUp, ShiftDown, CopyRecord
                     two cells are copied one by one, the target overlaps
                     the source by one cell; the merged copy read the second
                     cell before the first one was written (-O2 and above)
  CopySequential     eight cells are copied one by one into the next eight;
                     each write must precede the next read (-O3)
  ErrorCodeInTry     Err := IOResult in a routine with a try block: the
                     inlined IOResult reads the code of the error and clears
                     it through a pointer which lives in the frame; the code
                     was cleared before it was read, a failed Reset gave 0
                     (-O3)

  The same rules in forms which were not wrong: PointerThenField,
  NameThenPointer, TwoPointers.

  The other routines are the same statements with memory which is certainly
  not the one which is read: they hold the values where the read may and
  does go down.

  The values are the order of the statements, which -O1 keeps.  Delphi 12.2
  agrees on every routine of this file; it has the defect of its own in
  other forms (a value read through a pointer is taken again from its
  register behind a write to the variable by its name). }

{$mode delphi}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  cwstring,
  {$endif UNIX}
  SysUtils;

type
  TRec = record
    A, B, C, D: Int64;
  end;
  PRec = ^TRec;
  TCells = array[0..7] of Int64;
  PCells = ^TCells;

var
  Fails: Integer = 0;
  Closed: Integer = 0;
  Cell: Int64;
  Cell32: Integer;
  G: TRec;
  M: TCells;
  N: array[0..8] of Int64;

procedure Check(Got, Want: Int64; const Name: string);
begin
  if Got <> Want then
  begin
    WriteLn('FAIL ', Name, ': ', Got, ' <> ', Want);
    Inc(Fails);
  end;
end;

function PointerThenName(P: PInt64): Int64; noinline;
var
  X, Y: Int64;
begin
  X := P^;
  Cell := Cell + 5;
  Y := X * 1000;
  Result := Y + Cell;
end;

function PointerThenName32(P: PInteger): Integer; noinline;
var
  X, Y: Integer;
begin
  X := P^;
  Cell32 := Cell32 + 5;
  Y := X * 1000;
  Result := Y + Cell32;
end;

function PointerThenField(P: PInt64; K: Int64): Int64; noinline;
var
  X, Y: Int64;
begin
  X := P^;
  Y := K + 1;
  G.C := G.C + 4;
  Result := X * 7 + Y + G.C;
end;

function NameThenPointer(P: PInt64; K: Int64): Int64; noinline;
var
  X, Y: Int64;
begin
  Y := K * 3;
  X := Cell;
  P^ := P^ - 1;
  Result := Y + X * 7 + P^;
end;

function TwoPointers(A: PCells; R: PRec; K: Int64): Int64; noinline;
var
  X, Y: Int64;
begin
  Y := A^[1];
  X := Y;
  Y := 7;
  R^.A := 2;
  Result := Y + X * 1000 + K + R^.C;
end;

function BitOfOldValue(P: PInt64): Int64; noinline;
var
  X: Int64;
begin
  X := P^;
  Cell := Cell or 4;
  if (X and 4) <> 0 then
    Result := 1
  else
    Result := 2;
end;

function BitOfOldValue32(P, Q: PInteger): Integer; noinline;
var
  X: Integer;
begin
  X := P^;
  Q^ := Q^ or 8;
  if (X and 8) <> 0 then
    Result := 1
  else
    Result := 2;
end;

procedure ShiftUp(Target: PCells); noinline;
begin
  Target^[0] := M[0];
  Target^[1] := M[1];
end;

procedure ShiftDown(Target: PCells); noinline;
begin
  Target^[1] := M[2];
  Target^[0] := M[1];
end;

procedure CopyRecord(Target: PRec); noinline;
begin
  Target^.A := G.A;
  Target^.B := G.B;
end;

procedure CopySequential(Target: PCells); noinline;
var
  I: Integer;
begin
  for I := 0 to 7 do
    Target^[I] := N[I];
end;

procedure TestSequential;
var
  I: Integer;
begin
  for I := 0 to 8 do
    N[I] := I + 1;
  CopySequential(PCells(@N[1]));
  for I := 0 to 8 do
    Check(N[I], 1, 'eight cells are copied one cell up');
end;

function ErrorCodeInTry(const Dir: string): Integer; noinline;
var
  F: file;
  Err: Integer;
begin
  Result := -1;
  AssignFile(F, Dir + PathDelim + 'no_such_file.bin');
  try
    {$I-}
    Reset(F, 1);
    {$I+}
    Err := IOResult;
    Result := Err;
  finally
    { the program closes the file here }
    if Result = 0 then
      Inc(Closed);
  end;
end;

function ErrorCodeTwice(const Dir: string): Integer; noinline;
var
  F: file;
  First, Second: Integer;
begin
  Result := -1;
  AssignFile(F, Dir + PathDelim + 'no_such_file.bin');
  try
    {$I-}
    Reset(F, 1);
    {$I+}
    First := IOResult;
    Second := IOResult;
    Result := Ord(First <> 0) * 10 + Ord(Second <> 0);
  finally
    if Result < 0 then
      Inc(Closed);
  end;
end;

{ memory which is certainly another one }

function OtherField(R: PRec): Int64; noinline;
var
  X, Y: Int64;
begin
  X := R^.A;
  R^.B := R^.B + 5;
  Y := X * 1000;
  Result := Y + R^.B;
end;

function NameThenLocal(K: Int64): Int64; noinline;
var
  X, Y, L: Int64;
  PL: PInt64;
begin
  L := K;
  PL := @L;
  X := Cell;
  PL^ := PL^ + 5;
  Y := X * 1000;
  Result := Y + L;
end;

function NameThenName: Int64; noinline;
var
  X, Y: Int64;
begin
  X := Cell;
  G.B := G.B + 5;
  Y := X * 1000;
  Result := Y + G.B;
end;

function NoWrite(P: PInt64; K: Int64): Int64; noinline;
var
  X, Y: Int64;
begin
  X := P^;
  K := K + 5;
  Y := X * 1000;
  Result := Y + K;
end;

begin
  Cell := 7;
  Check(PointerThenName(@Cell), 7012, 'a pointer is read, the variable is written by name');
  Cell32 := 7;
  Check(PointerThenName32(@Cell32), 7012, 'the same in 32 bits');
  G.C := 128;
  Check(PointerThenField(@G.C, 0), 128 * 7 + 1 + 132, 'a pointer is read, the field is written by name');
  Cell := 107;
  Check(NameThenPointer(@Cell, 100), 300 + 107 * 7 + 106, 'the variable is read by name, written through a pointer');
  M[0] := 142; M[1] := 149; M[2] := 156; M[3] := 163; M[4] := 170; M[5] := 177; M[6] := 184; M[7] := 191;
  Check(TwoPointers(@M[3], @M[4], 1), 7 + 170 * 1000 + 1 + 184, 'two pointers at one cell');
  Check(M[4], 2, 'two pointers at one cell, the cell');
  Cell := 0;
  Check(BitOfOldValue(@Cell), 2, 'a bit of the value read before the write');
  Cell32 := 0;
  Check(BitOfOldValue32(@Cell32, @Cell32), 2, 'the same in 32 bits through two pointers');

  M[0] := 1; M[1] := 2; M[2] := 3; M[3] := 4;
  ShiftUp(@M[1]);
  Check(M[0] * 1000 + M[1] * 100 + M[2] * 10 + M[3], 1114, 'two cells are copied one cell up');
  M[0] := 1; M[1] := 2; M[2] := 3; M[3] := 4;
  ShiftDown(@M[0]);
  Check(M[0] * 1000 + M[1] * 100 + M[2] * 10 + M[3], 3334, 'two cells are copied one cell down');
  G.A := 1; G.B := 2; G.C := 3; G.D := 4;
  CopyRecord(@G.B);
  Check(G.A * 1000 + G.B * 100 + G.C * 10 + G.D, 1114, 'two fields are copied one field up');
  TestSequential;

  Check(Ord(ErrorCodeInTry('memory_order_no_such_directory') <> 0), 1,
    'the code of the error is read before it is cleared');
  Check(Closed, 0, 'a file which was not opened is not closed');
  Check(ErrorCodeTwice('memory_order_no_such_directory'), 10,
    'the second IOResult finds the code cleared');

  G.A := 7; G.B := 1;
  Check(OtherField(@G), 7006, 'another field behind the same pointer is written');
  Cell := 7;
  Check(NameThenLocal(1), 7006, 'a local is written through its address');
  Cell := 7; G.B := 1;
  Check(NameThenName, 7006, 'another variable is written by name');
  Cell := 7;
  Check(NoWrite(@Cell, 1), 7006, 'nothing is written');

  if Fails = 0 then
    WriteLn('MEMORY_ORDER_PASS')
  else
  begin
    WriteLn('MEMORY_ORDER_FAIL ', Fails);
    Halt(1);
  end;
end.
