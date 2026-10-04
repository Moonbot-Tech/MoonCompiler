program assign_cse_semantic;

{ An assignment is a domain of the common subexpressions again: what the
  target and the value have in common - the object, the pointer, the index,
  the address of the element - is computed once for both sides
  (compiler/optcse.pas, cseinvariant).  The assignment was taken out of the
  domains on 05.08 because a value which was read too early met a write
  through another name; that was the peephole optimizer moving a read across
  a write, repaired since.

  The forms: an element changed in place, a field behind two pointers, a
  field of an object counted from fields of the same object, a flag counted
  from fields, the nested routine which writes a local of the routine around
  from a field of its object, the value read through one name and the target
  written through another name of the same memory, the target whose index the
  value changes, an assignment of a managed value, the two reads of the
  parameter of tautoinline3.

  The values are those of Delphi 12.2 and of -O1; the two reads of the
  parameter have the value of the order of the statements, 7012, which
  tests/test/cg/tautoinline3.pp asks for: Delphi 12.2 reads the parameter
  once and prints 7007. }

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
  TServer = class
    Timeout: Cardinal;
  end;

  PNode = ^TNode;
  TNode = record
    Next: PNode;
    Value: Int64;
    Other: Int64;
  end;

  TBuf = record
    Count: Cardinal;
    Kind: Cardinal;
    Data: Pointer;
  end;

  TBigRec = record
    A, B, C, D: Int64;
  end;
  PBigRec = ^TBigRec;

  TSock = class
    fServer: TServer;
    fInputCount: Integer;
    fInput: Pointer;
    fKeep: Boolean;
    fItems: array of Int64;
    fNames: array of string;
    fIndex: Integer;
    fTotal: Int64;
    procedure Decide(Old: Boolean);
    function Fill: Integer;
    procedure StepItem(Index: Integer);
    procedure StepTotal;
    procedure StepAtIndex;
    procedure NameAtIndex(const Tail: string);
    function NextIndex: Integer;
    procedure StoreAtNext;
  end;

var
  Fails: Integer = 0;
  GRec: TBigRec;
  Static: array[0..15] of Int64;

procedure Check(Got, Want: Int64; const Name: string);
begin
  if Got <> Want then
  begin
    WriteLn('FAIL ', Name, ': ', Got, ' <> ', Want);
    Inc(Fails);
  end;
end;

procedure CheckText(const Got, Want, Name: string);
begin
  if Got <> Want then
  begin
    WriteLn('FAIL ', Name, ': ', Got, ' <> ', Want);
    Inc(Fails);
  end;
end;

procedure TSock.Decide(Old: Boolean);
begin
  fKeep := ((fServer = nil) or (fServer.Timeout > 0)) and not Old;
end;

function TSock.Fill: Integer;
var
  Buf: array[0..3] of TBuf;

  function Prepare: Cardinal;
  begin
    Buf[0].Count := fInputCount;
    Buf[0].Kind := 1;
    Buf[0].Data := fInput;
    Buf[1].Count := 0;
    Buf[1].Kind := 0;
    Buf[1].Data := nil;
    Result := Buf[0].Count + Buf[1].Count;
  end;

begin
  Result := Prepare;
  Inc(Result, Buf[0].Kind);
end;

procedure TSock.StepItem(Index: Integer);
begin
  fItems[Index] := fItems[Index] * 3 + fItems[Index + 1];
end;

procedure TSock.StepTotal;
begin
  fTotal := fTotal + fItems[fIndex] + fInputCount;
end;

procedure TSock.StepAtIndex;
begin
  fItems[fIndex] := fItems[fIndex] + fIndex;
end;

procedure TSock.NameAtIndex(const Tail: string);
begin
  fNames[fIndex] := fNames[fIndex] + Tail;
end;

function TSock.NextIndex: Integer;
begin
  Inc(fIndex);
  Result := fIndex * 10;
end;

procedure TSock.StoreAtNext;
begin
  { the value changes the index of the target: the target is the element
    the index names behind the call }
  fItems[fIndex] := NextIndex;
end;

procedure StepNode(P: PNode); noinline;
begin
  P^.Next^.Value := P^.Next^.Value * 2 + P^.Next^.Other;
end;

procedure StepStatic(Index: Integer); noinline;
begin
  Static[Index] := Static[Index] + Static[Index - 1];
end;

procedure StepPointer(P: PInt64; Index: Integer); noinline;
begin
  P[Index] := P[Index] + P[Index + 1];
end;

procedure TwoNames(A, B: PBigRec); noinline;
begin
  { A and B may be one record: every statement reads what the statement in
    front of it wrote }
  A^.B := B^.B + 5;
  B^.C := A^.B * 2;
  A^.D := B^.C + A^.B;
end;

procedure SwapThrough(A, B: PNode); noinline;
begin
  { B^.Next may be A: the first statement changes what the second one
    reads }
  A^.Value := B^.Next^.Value + 1;
  B^.Next^.Other := A^.Value + B^.Next^.Value;
end;

procedure PokeG;
begin
  GRec.B := GRec.B + 5;
end;

function TwoReads(const R: TBigRec): Int64;
begin
  Result := R.B;
  PokeG;
  Result := Result * 1000 + R.B;
end;

var
  S: TSock;
  N1, N2: TNode;
  R: TBigRec;
  Cells: array[0..7] of Int64;
  K: Integer;
begin
  S := TSock.Create;
  S.fServer := TServer.Create;
  S.fServer.Timeout := 5;
  S.fInputCount := 40;
  S.Decide(False);
  Check(Ord(S.fKeep), 1, 'a flag is counted from a field of a field');
  S.Decide(True);
  Check(Ord(S.fKeep), 0, 'a flag is counted from a parameter');
  S.fServer.Timeout := 0;
  S.Decide(False);
  Check(Ord(S.fKeep), 0, 'a flag is counted from a field which is zero');
  S.fServer := nil;
  S.Decide(False);
  Check(Ord(S.fKeep), 1, 'a flag is counted without the object of the field');
  Check(S.Fill, 41, 'a nested routine writes a local of the routine around');

  SetLength(S.fItems, 8);
  for K := 0 to 7 do
    S.fItems[K] := K + 1;
  S.StepItem(2);
  Check(S.fItems[2], 3 * 3 + 4, 'an element is counted from itself and its neighbour');
  S.fIndex := 5;
  S.fTotal := 1000;
  S.StepTotal;
  Check(S.fTotal, 1000 + 6 + 40, 'a field is counted from itself and an element');
  S.StepAtIndex;
  Check(S.fItems[5], 6 + 5, 'an element at the index which is a field');
  SetLength(S.fNames, 8);
  S.fNames[5] := 'moon';
  S.NameAtIndex('bot');
  S.NameAtIndex('!');
  CheckText(S.fNames[5], 'moonbot!', 'a string at the index which is a field');
  S.fIndex := 2;
  S.StoreAtNext;
  Check(S.fIndex, 3, 'the value moved the index');
  Check(S.fItems[2] * 1000 + S.fItems[3], 13 * 1000 + 30, 'the target is named behind the value');

  N1.Next := @N2;
  N2.Next := @N1;
  N2.Value := 7;
  N2.Other := 3;
  StepNode(@N1);
  Check(N2.Value, 17, 'a field behind two pointers');

  for K := 0 to 15 do
    Static[K] := K * K;
  StepStatic(4);
  Check(Static[4], 16 + 9, 'an element of an array of the unit');
  for K := 0 to 7 do
    Cells[K] := 10 * K;
  StepPointer(@Cells[0], 6);
  Check(Cells[6], 60 + 70, 'an element behind a pointer');

  R.B := 1;
  R.C := 0;
  R.D := 0;
  TwoNames(@R, @R);
  Check(R.B * 10000 + R.C * 100 + R.D, 6 * 10000 + 12 * 100 + 18, 'two names of one record');
  N1.Value := 0;
  N1.Other := 0;
  N2.Value := 5;
  { N1.Next is N2 and N2.Next is N1: B^.Next is A }
  SwapThrough(@N1, @N2);
  Check(N1.Value * 100 + N1.Other, 1 * 100 + 2, 'the target is what the next statement reads');

  GRec.B := 7;
  Check(TwoReads(GRec), 7012, 'two reads of a parameter which is a variable of the unit');

  if Fails = 0 then
    WriteLn('ASSIGN_CSE_PASS')
  else
  begin
    WriteLn('ASSIGN_CSE_FAIL ', Fails);
    Halt(1);
  end;
end.
