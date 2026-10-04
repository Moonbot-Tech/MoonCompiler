program nested_local;
{ A loop over a local dynamic array or string walks a pointer taken from the variable once, in front of the loop
  (compiler/optloop.pas, implicit_array_base_is_loop_invariant).  That holds while nothing in the body gives the
  variable a new value.  A call gives it one if it reaches code which names the variable: a routine nested in the
  routine whose local it is.

  The Check calls are the semantic matrix.  The write: the array assigned, its length set, passed by reference;
  the string replaced, a character written, Delete, Insert, SetLength.  The way to it: the nested routine called
  from the loop, through another nested routine, two levels deep, through its address (FPC), from the cleanup of
  a nested routine, with and without an exception, from a cleanup and from a handler inside the loop.  The loop:
  of the routine whose local it is; of a nested routine, which calls a routine beside it, its own nested routine,
  itself.  The array of records has its index multiplied.

  The nested routine which only reads, the one which writes another array, the one which writes the array and is
  not called from the loop, the one whose address is known and which only reads are no reason to walk the array
  by the index: the Shape routines are counted in the -O3 object by run_nested_local_gate.py.

  Delphi 12.2 compiles the file as well and is the oracle of the values. }
{$IFDEF FPC}
  {$MODE DELPHI}{$H+}
  {$MODESWITCH NESTEDPROCVARS}
{$ELSE}
  {$APPTYPE CONSOLE}
{$ENDIF}
{$Q-}{$R-}

uses
  SysUtils;

type
  TIntDyn = array of Integer;
  TRec = record
    Key: Integer;
    Val: Int64;
    Pad: array[0..2] of Int64;
  end;
  TRecDyn = array of TRec;
{$IFDEF FPC}
  TStep = procedure is nested;
{$ENDIF}

var
  Failures: Integer;
  Seen: Int64;
  Total: Int64;

procedure Check(const Name: string; Got, Want: Int64);
begin
  if Got <> Want then
  begin
    WriteLn('FAIL ', Name, ': ', Got, ' <> ', Want);
    Inc(Failures);
  end;
end;

procedure Sink(V: Int64); {$IFDEF FPC} noinline; {$ENDIF}
begin
  Inc(Seen, V);
end;

procedure Count(V: Int64); {$IFDEF FPC} noinline; {$ENDIF}
begin
  Inc(Seen, V);
end;

{$IFDEF FPC}
procedure Run(Step: TStep); noinline;
begin
  Step();
end;
{$ENDIF}

procedure Replace(var A: TIntDyn; const B: TIntDyn); {$IFDEF FPC} noinline; {$ENDIF}
begin
  A := B;
end;

procedure Fail(K: Integer); {$IFDEF FPC} noinline; {$ENDIF}
begin
  if K = 1 then
    raise Exception.Create('one');
end;

{ ---- the nested routine gives the array a new value ---- }

function Assigned2(const A, B: TIntDyn; Cnt: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  L: TIntDyn;
  I: Integer;
  S: Int64;

  procedure Swap;
  begin
    L := B;
  end;

begin
  L := A;
  S := 0;
  for I := 0 to Cnt - 1 do
  begin
    S := S + L[I];
    if I = 1 then
      Swap;
  end;
  Result := S;
end;

function AssignedRecords(const A, B: TRecDyn; Cnt: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  L: TRecDyn;
  I: Integer;
  S: Int64;

  procedure Swap;
  begin
    L := B;
  end;

begin
  L := A;
  S := 0;
  for I := 0 to Cnt - 1 do
  begin
    S := S + L[I].Val;
    if I = 1 then
      Swap;
  end;
  Result := S;
end;

function Grown(const A: TIntDyn; Cnt: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  L: TIntDyn;
  I: Integer;
  S: Int64;

  procedure Grow;
  var
    K, Old: Integer;
  begin
    Old := Length(L);
    SetLength(L, Old + 4096);
    for K := 0 to Old - 1 do
      L[K] := L[K] + 1000;
  end;

begin
  L := Copy(A);
  S := 0;
  for I := 0 to Cnt - 1 do
  begin
    S := S + L[I];
    if I = 1 then
      Grow;
  end;
  Result := S;
end;

function ThroughAnother(const A, B: TIntDyn; Cnt: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  L: TIntDyn;
  I: Integer;
  S: Int64;

  procedure Swap;
  begin
    L := B;
  end;

  procedure Maybe(K: Integer);
  begin
    if K = 2 then
      Swap;
  end;

begin
  L := A;
  S := 0;
  for I := 0 to Cnt - 1 do
  begin
    S := S + L[I];
    Maybe(I);
  end;
  Result := S;
end;

function TwoLevels(const A, B: TIntDyn; Cnt: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  L: TIntDyn;
  I: Integer;
  S: Int64;

  procedure Outer(K: Integer);

    procedure Inner;
    begin
      L := B;
    end;

  begin
    if K = 0 then
      Inner;
  end;

begin
  L := A;
  S := 0;
  for I := 0 to Cnt - 1 do
  begin
    S := S + L[I];
    Outer(I);
  end;
  Result := S;
end;

{$IFDEF FPC}
function ThroughAddress(const A, B: TIntDyn; Cnt: Integer): Int64; noinline;
var
  L: TIntDyn;
  I: Integer;
  S: Int64;

  procedure Swap;
  begin
    L := B;
  end;

begin
  L := A;
  S := 0;
  for I := 0 to Cnt - 1 do
  begin
    S := S + L[I];
    if I = 1 then
      Run(Swap);
  end;
  Result := S;
end;
{$ENDIF}

{ ---- the loop of a nested routine over the array of its parent ---- }

function LoopOfNested(const A, B: TIntDyn; Cnt: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  L: TIntDyn;

  procedure Swap(K: Integer);
  begin
    if K = 1 then
      L := B;
  end;

  function Sum: Int64;
  var
    I: Integer;
  begin
    Result := 0;
    for I := 0 to Cnt - 1 do
    begin
      Result := Result + L[I];
      Swap(I);
    end;
  end;

begin
  L := A;
  Result := Sum;
end;

{ ---- more ways to the write: the loop of a nested routine, a cleanup, a handler, a reference ---- }

{ the loop of a nested routine, a routine beside it sets the length }
function LoopOfNestedGrown(const A: TIntDyn; Cnt: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  L: TIntDyn;

  procedure Grow(K: Integer);
  var
    J, Old: Integer;
  begin
    if K <> 1 then
      Exit;
    Old := Length(L);
    SetLength(L, Old + 4096);
    for J := 0 to Old - 1 do
      L[J] := L[J] + 1000;
  end;

  function Sum: Int64;
  var
    I: Integer;
  begin
    Result := 0;
    for I := 0 to Cnt - 1 do
    begin
      Result := Result + L[I];
      Grow(I);
    end;
  end;

begin
  L := Copy(A);
  Result := Sum;
end;

{ the loop of a nested routine, its own nested routine replaces the array }
function LoopOfNestedChild(const A, B: TIntDyn; Cnt: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  L: TIntDyn;

  function Sum: Int64;
  var
    I: Integer;

    procedure Swap;
    begin
      L := B;
    end;

  begin
    Result := 0;
    for I := 0 to Cnt - 1 do
    begin
      Result := Result + L[I];
      if I = 2 then
        Swap;
    end;
  end;

begin
  L := A;
  Result := Sum;
end;

{ the nested routine with the loop calls itself, the inner call replaces the array }
function LoopOfNestedItself(const A, B: TIntDyn; Cnt: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  L: TIntDyn;

  function Sum(Depth: Integer): Int64;
  var
    I: Integer;
  begin
    Result := 0;
    if Depth = 1 then
    begin
      L := B;
      Exit;
    end;
    for I := 0 to Cnt - 1 do
    begin
      Result := Result + L[I];
      if I = 3 then
        Result := Result + Sum(Depth + 1);
    end;
  end;

begin
  L := A;
  Result := Sum(0);
end;

{ the cleanup inside the loop replaces the array }
function CleanupReplaces(const A, B: TIntDyn; Cnt: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  L: TIntDyn;
  I: Integer;
  S: Int64;
begin
  L := A;
  S := 0;
  for I := 0 to Cnt - 1 do
  begin
    try
      S := S + L[I];
      Count(I);
    finally
      if I = 1 then
        L := B;
    end;
  end;
  Result := S;
end;

{ the cleanup of a nested routine replaces the array }
function NestedCleanupReplaces(const A, B: TIntDyn; Cnt: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  L: TIntDyn;
  I: Integer;
  S: Int64;

  procedure Step(K: Integer);
  begin
    try
      Count(K);
    finally
      if K = 1 then
        L := B;
    end;
  end;

begin
  L := A;
  S := 0;
  for I := 0 to Cnt - 1 do
  begin
    S := S + L[I];
    Step(I);
  end;
  Result := S;
end;

{ the cleanup of a nested routine replaces the array while an exception leaves the routine; the loop goes on }
function RaisingCleanupReplaces(const A, B: TIntDyn; Cnt: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  L: TIntDyn;
  I: Integer;
  S: Int64;

  procedure Step(K: Integer);
  begin
    try
      Fail(K);
    finally
      if K = 1 then
        L := B;
    end;
  end;

begin
  L := A;
  S := 0;
  for I := 0 to Cnt - 1 do
  begin
    S := S + L[I];
    try
      Step(I);
    except
      S := S + 100000;
    end;
  end;
  Result := S;
end;

{ the handler inside the loop calls the nested routine }
function HandlerCallsNested(const A, B: TIntDyn; Cnt: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  L: TIntDyn;
  I: Integer;
  S: Int64;

  procedure Swap;
  begin
    L := B;
  end;

begin
  L := A;
  S := 0;
  for I := 0 to Cnt - 1 do
  begin
    S := S + L[I];
    try
      Fail(I);
    except
      Swap;
    end;
  end;
  Result := S;
end;

{ by reference, from the loop }
function ByReference(const A, B: TIntDyn; Cnt: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  L: TIntDyn;
  I: Integer;
  S: Int64;
begin
  L := A;
  S := 0;
  for I := 0 to Cnt - 1 do
  begin
    S := S + L[I];
    if I = 1 then
      Replace(L, B);
  end;
  Result := S;
end;

{ by reference, from the nested routine }
function NestedByReference(const A, B: TIntDyn; Cnt: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  L: TIntDyn;
  I: Integer;
  S: Int64;

  procedure Swap;
  begin
    Replace(L, B);
  end;

begin
  L := A;
  S := 0;
  for I := 0 to Cnt - 1 do
  begin
    S := S + L[I];
    if I = 1 then
      Swap;
  end;
  Result := S;
end;

{ ---- strings ---- }

function StringReplaced(const A, B: string): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  S: string;
  I: Integer;
  R: Int64;

  procedure Swap;
  begin
    S := B;
  end;

begin
  S := A;
  R := 0;
  for I := 1 to Length(A) do
  begin
    R := R * 3 + Ord(S[I]);
    if I = 2 then
      Swap;
  end;
  Result := R;
end;

function StringWritten(const A: string): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  S, Keep: string;
  I: Integer;
  R: Int64;

  procedure Mark(K: Integer);
  begin
    S[K + 1] := 'z';
  end;

begin
  S := A;
  Keep := S;
  R := 0;
  for I := 1 to Length(A) - 1 do
  begin
    R := R * 3 + Ord(S[I]);
    Mark(I);
  end;
  Result := R * 1000 + Ord(Keep[3]);
end;

{ strings: the nested routine deletes, inserts, sets the length, appends }
function StringDeleted(const A: string): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  S: string;
  I: Integer;
  R: Int64;

  procedure Cut;
  begin
    Delete(S, 1, 1);
    S := S + '!';
  end;

begin
  S := A;
  R := 0;
  for I := 1 to Length(A) do
  begin
    R := R * 3 + Ord(S[I]);
    if I = 2 then
      Cut;
  end;
  Result := R;
end;

function StringInserted(const A: string): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  S: string;
  I: Integer;
  R: Int64;

  procedure Put;
  begin
    Insert('XYZ', S, 1);
  end;

begin
  S := A;
  R := 0;
  for I := 1 to Length(A) do
  begin
    R := R * 3 + Ord(S[I]);
    if I = 2 then
      Put;
  end;
  Result := R;
end;

function StringLength(const A: string): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  S: string;
  I: Integer;
  R: Int64;

  procedure Longer;
  var
    K: Integer;
  begin
    SetLength(S, 4000);
    for K := 1 to 6 do
      S[K] := Chr(Ord('k') + K);
  end;

begin
  S := A;
  R := 0;
  for I := 1 to Length(A) do
  begin
    R := R * 3 + Ord(S[I]);
    if I = 2 then
      Longer;
  end;
  Result := R;
end;

{ ---- no reason to give up the pointer: the nested routine reads, or writes another array ---- }

function NestedReads(const A: TRecDyn; Cnt: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  L: TRecDyn;
  I: Integer;
  S: Int64;

  procedure Show(K: Integer);
  begin
    Sink(L[K].Key);
  end;

begin
  L := A;
  S := 0;
  for I := 0 to Cnt - 1 do
  begin
    S := S + L[I].Val;
    Show(I);
  end;
  Result := S;
end;

function NestedWritesOther(const A, B: TRecDyn; Cnt: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  L, M: TRecDyn;
  I: Integer;
  S: Int64;

  procedure Swap;
  begin
    M := B;
  end;

begin
  L := A;
  M := A;
  S := 0;
  for I := 0 to Cnt - 1 do
  begin
    S := S + L[I].Val;
    if I = 1 then
      Swap;
  end;
  Result := S * 1000 + M[0].Val;
end;

{ ---- shapes: the loops of these routines are counted in the object ---- }

function ShapePlain(const A: TRecDyn; Cnt: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  L: TRecDyn;
  I: Integer;
  S: Int64;
begin
  L := A;
  S := 0;
  for I := 0 to Cnt - 1 do
  begin
    S := S + L[I].Val;
    Count(I);
  end;
  Result := S;
end;

function ShapeNestedReads(const A: TRecDyn; Cnt: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  L: TRecDyn;
  I: Integer;
  S: Int64;

  procedure Show(K: Integer);
  begin
    Sink(L[K].Key);
  end;

begin
  L := A;
  S := 0;
  for I := 0 to Cnt - 1 do
  begin
    S := S + L[I].Val;
    Count(I);
  end;
  Show(0);
  Result := S;
end;

function ShapeNestedWritesElsewhere(const A, B: TRecDyn; Cnt: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  L: TRecDyn;
  I: Integer;
  S: Int64;

  procedure Swap;
  begin
    L := B;
  end;

begin
  L := A;
  S := 0;
  for I := 0 to Cnt - 1 do
  begin
    S := S + L[I].Val;
    Count(I);
  end;
  Swap;
  Result := S + L[0].Val;
end;

function ShapeLoopOfNested(const A, B: TRecDyn; Cnt: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  L: TRecDyn;

  procedure Swap;
  begin
    L := B;
  end;

  function WalkOfNested: Int64;
  var
    I: Integer;
  begin
    Result := 0;
    for I := 0 to Cnt - 1 do
    begin
      Result := Result + L[I].Val;
      Count(I);
    end;
  end;

begin
  L := A;
  Result := WalkOfNested;
  Swap;
  Result := Result + L[0].Val;
end;

function ShapeLoopOfNestedPlain(const A: TRecDyn; Cnt: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  L: TRecDyn;

  function WalkOfNestedPlain: Int64;
  var
    I: Integer;
  begin
    Result := 0;
    for I := 0 to Cnt - 1 do
    begin
      Result := Result + L[I].Val;
      Count(I);
    end;
  end;

begin
  L := A;
  Result := WalkOfNestedPlain;
end;

{$IFDEF FPC}
function ShapeAddressOfReader(const A, B: TRecDyn; Cnt: Integer): Int64; noinline;
var
  L: TRecDyn;
  I: Integer;
  S: Int64;

  procedure Show;
  begin
    Sink(L[0].Key);
  end;

  procedure Swap;
  begin
    L := B;
  end;

begin
  L := A;
  S := 0;
  Run(Show);
  for I := 0 to Cnt - 1 do
  begin
    S := S + L[I].Val;
    Count(I);
  end;
  Swap;
  Result := S + L[0].Val;
end;
{$ENDIF}

var
  I: Integer;
  A, B: TIntDyn;
  RA, RB: TRecDyn;
begin
  SetLength(A, 8);
  SetLength(B, 8);
  SetLength(RA, 8);
  SetLength(RB, 8);
  for I := 0 to 7 do
  begin
    A[I] := I + 1;
    B[I] := (I + 1) * 100;
    RA[I].Key := I;
    RA[I].Val := I + 1;
    RB[I].Key := I;
    RB[I].Val := (I + 1) * 100;
  end;

  Check('assigned', Assigned2(A, B, 8), 3303);
  Check('assigned-records', AssignedRecords(RA, RB, 8), 3303);
  Check('grown', Grown(A, 8), 6036);
  Check('through-another', ThroughAnother(A, B, 8), 3006);
  Check('two-levels', TwoLevels(A, B, 8), 3501);
{$IFDEF FPC}
  Check('through-address', ThroughAddress(A, B, 8), 1 + 2 + 300 + 400 + 500 + 600 + 700 + 800);
{$ENDIF}
  Check('loop-of-nested', LoopOfNested(A, B, 8), 3303);
  Check('loop-of-nested-grown', LoopOfNestedGrown(A, 8), 6036);
  Check('loop-of-nested-child', LoopOfNestedChild(A, B, 8), 3006);
  Check('loop-of-nested-itself', LoopOfNestedItself(A, B, 8), 2610);
  Seen := 0;
  Check('cleanup-replaces', CleanupReplaces(A, B, 8), 3303);
  Check('cleanup-replaces seen', Seen, 28);
  Seen := 0;
  Check('nested-cleanup-replaces', NestedCleanupReplaces(A, B, 8), 3303);
  Check('nested-cleanup-replaces seen', Seen, 28);
  Check('raising-cleanup-replaces', RaisingCleanupReplaces(A, B, 8), 103303);
  Check('handler-calls-nested', HandlerCallsNested(A, B, 8), 3303);
  Check('by-reference', ByReference(A, B, 8), 3303);
  Check('nested-by-reference', NestedByReference(A, B, 8), 3303);
  Check('string-replaced', StringReplaced('abcdef', 'uvwxyz'), 36287);
  Check('string-written', StringWritten('abcdef'), 12737099);
  Check('string-deleted', StringDeleted('abcdef'), 35457);
  Check('string-inserted', StringInserted('abcdef'), 35205);
  Check('string-length', StringLength('abcdef'), 35927);
  Seen := 0;
  Check('nested-reads', NestedReads(RA, 8), 36);
  Check('nested-reads seen', Seen, 28);
  Check('nested-writes-other', NestedWritesOther(RA, RB, 8), 36100);
  Seen := 0;
  Check('shape/plain', ShapePlain(RA, 8), 36);
  Check('shape/plain seen', Seen, 28);
  Seen := 0;
  Check('shape/nested-reads', ShapeNestedReads(RA, 8), 36);
  Check('shape/nested-reads seen', Seen, 28);
  Seen := 0;
  Check('shape/nested-writes-elsewhere', ShapeNestedWritesElsewhere(RA, RB, 8), 136);
  Check('shape/nested-writes-elsewhere seen', Seen, 28);

  Seen := 0;
  Check('shape/loop-of-nested', ShapeLoopOfNested(RA, RB, 8), 136);
  Check('shape/loop-of-nested seen', Seen, 28);
  Seen := 0;
  Check('shape/loop-of-nested-plain', ShapeLoopOfNestedPlain(RA, 8), 36);
  Check('shape/loop-of-nested-plain seen', Seen, 28);
{$IFDEF FPC}
  Seen := 0;
  Check('shape/address-of-reader', ShapeAddressOfReader(RA, RB, 8), 136);
  Check('shape/address-of-reader seen', Seen, 28);
{$ENDIF}
  if Failures = 0 then
    WriteLn('NESTED_LOCAL_PASS')
  else
  begin
    WriteLn('NESTED_LOCAL_FAIL ', Failures);
    Halt(1);
  end;
end.
