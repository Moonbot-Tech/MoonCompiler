program record_fields;
{ The fields of a local record live in temps while a loop runs, the record gets them back behind the loop
  (compiler/optloop.pas, optimize_record_writes).  Whoever looks at the record before that must find the fields
  in it, so a field somebody looks at stays in the record (drop_observed_fields).

  The Check calls are the semantic matrix.  Around the loop: a handler which reads the record, the code behind a
  try..except, a finally block, with an exception and with Exit; a finally block and a handler around it, a
  handler which raises again and one further out, the loop in a handler; a call which raises and a read through
  nil; integer and floating point fields; two records.  Inside the loop: a finally block which reads the record
  and one which writes it, left by its end, by an exception, by Break, by Continue and by Exit; a handler, with a
  call which raises and with a read through nil.  A goto which leaves the loop and one which stays in it.  The
  record as the result of the function.  A custom Finalize after an exception and after Exit, and a normal loop
  in the same managed record.  An assembler block inside the loop which names a field (FPC only:
  Delphi has none in a Pascal routine).

  The Shape routines are counted in the -O3 object by run_record_fields_gate.py: nobody looks at the record
  while the loop runs, and the loop keeps the fields in registers.  ShapeCallsBudget is the loop of fcl-xml's
  ParseMarkupDecl: a loop with calls which uses Self and three locals writes a local record in a rare branch;
  its fields share the registers a call saves with them, and must not push Self out of them.

  Delphi 12.2 compiles the file as well and is the oracle of the values. }
{$IFDEF FPC}
  {$MODE DELPHI}{$H+}
  {$GOTO ON}
  {$ASMMODE INTEL}
{$ELSE}
  {$APPTYPE CONSOLE}
{$ENDIF}
{$Q-}{$R-}

uses
  SysUtils;

type
  PIntArr = ^TIntArr;
  TIntArr = array[0..15] of Integer;
  TPair = record
    A, B: Integer;
  end;
  TWide = record
    A, B: Int64;
    C: Double;
  end;
  TManaged = record
    A, B: Integer;
    class operator Initialize(out Dest: TManaged);
    class operator Finalize(var Dest: TManaged);
  end;
  TMarkLoc = record
    Line, Col: Integer;
  end;
  TMarkScanner = class
    FData: string;
    FPos, FLine: Integer;
    Reported: Int64;
    procedure SkipBlanks; {$IFDEF FPC} noinline; {$ENDIF}
    function Take(C: Char): Boolean; {$IFDEF FPC} noinline; {$ENDIF}
    procedure Report(const Where: TMarkLoc); {$IFDEF FPC} noinline; {$ENDIF}
    function ShapeCallsBudget: Integer; {$IFDEF FPC} noinline; {$ENDIF}
  end;

var
  Failures: Integer;
  Seen: Int64;
  Ints: TIntArr;
  Scanner: TMarkScanner;

class operator TManaged.Initialize(out Dest: TManaged);
begin
  Dest.A := 0;
  Dest.B := 0;
end;

class operator TManaged.Finalize(var Dest: TManaged);
begin
  Seen := Dest.A * 100 + Dest.B;
end;

procedure Check(const Name: string; Got, Want: Int64);
begin
  if Got <> Want then
  begin
    WriteLn('FAIL ', Name, ': ', Got, ' <> ', Want);
    Inc(Failures);
  end;
end;

function Get(P: PIntArr; I, Bad: Integer): Integer; {$IFDEF FPC} noinline; {$ENDIF}
begin
  if I = Bad then
    raise Exception.Create('bad');
  Result := P^[I];
end;

procedure Sink(V: Int64); {$IFDEF FPC} noinline; {$ENDIF}
begin
  Seen := Seen * 7 + V;
end;

procedure Fail; {$IFDEF FPC} noinline; {$ENDIF}
begin
  raise Exception.Create('fail');
end;

procedure ManagedException(P: PIntArr; N, Bad: Integer); {$IFDEF FPC} noinline; {$ENDIF}
var
  R: TManaged;
  I: Integer;
begin
  try
    for I := 0 to N - 1 do
    begin
      R.A := R.A + Get(P, I, Bad);
      R.B := R.B + 1;
    end;
  except
    ;
  end;
end;

procedure ManagedExit(P: PIntArr; N: Integer); {$IFDEF FPC} noinline; {$ENDIF}
var
  R: TManaged;
  I: Integer;
begin
  for I := 0 to N - 1 do
  begin
    R.A := R.A + P^[I];
    R.B := R.B + 1;
    if I = 5 then
      Exit;
  end;
end;

procedure ShapeManagedNoTrap(N: Integer); {$IFDEF FPC} noinline; {$ENDIF}
var
  R: TManaged;
  I: Integer;
begin
  for I := 0 to N - 1 do
  begin
    R.A := R.A + I;
    R.B := R.B + 1;
  end;
end;

{ ---- the try statement around the loop ---- }

function InHandler(P: PIntArr; N, Bad: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  R: TWide;
  I: Integer;
begin
  R.A := 0;
  R.B := 0;
  R.C := 0;
  try
    for I := 0 to N - 1 do
    begin
      R.A := R.A + Get(P, I, Bad);
      R.B := R.B + 1;
    end;
  except
    R.B := R.B + 100;
  end;
  Result := R.A * 1000 + R.B;
end;

function BehindTry(P: PIntArr; N, Bad: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  R: TWide;
  I: Integer;
begin
  R.A := 0;
  R.B := 0;
  R.C := 0;
  try
    I := 0;
    while I < N do
    begin
      R.A := R.A + Get(P, I, Bad);
      R.B := R.B + 1;
      Inc(I);
    end;
  except
    Sink(1);
  end;
  Result := R.A * 1000 + R.B;
end;

function BehindTryRepeat(P: PIntArr; N, Bad: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  R: TWide;
  I: Integer;
begin
  R.A := 0;
  R.B := 0;
  R.C := 0;
  try
    I := 0;
    repeat
      R.A := R.A + Get(P, I, Bad);
      R.B := R.B + 1;
      Inc(I);
    until I >= N;
  except
    Sink(1);
  end;
  Result := R.A * 1000 + R.B;
end;

function InCleanup(P: PIntArr; N, Bad: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  R: TWide;
  I: Integer;
begin
  R.A := 0;
  R.B := 0;
  R.C := 0;
  Result := -1;
  try
    try
      for I := 0 to N - 1 do
      begin
        R.A := R.A + Get(P, I, Bad);
        R.B := R.B + 1;
      end;
    finally
      Sink(R.A * 1000 + R.B);
    end;
    Result := R.A;
  except
    Result := -2;
  end;
end;

function ExitThroughCleanup(P: PIntArr; N, Stop: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  R: TWide;
  I: Integer;
begin
  R.A := 0;
  R.B := 0;
  R.C := 0;
  Result := -1;
  try
    for I := 0 to N - 1 do
    begin
      R.A := R.A + P^[I];
      R.B := R.B + 1;
      if P^[I] = Stop then
        Exit(R.A);
    end;
  finally
    Sink(R.A * 1000 + R.B);
  end;
  Result := R.A + 1;
end;

function CleanupThenHandler(P: PIntArr; N, Bad: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  R: TWide;
  I: Integer;
begin
  R.A := 0;
  R.B := 0;
  R.C := 0;
  try
    try
      for I := 0 to N - 1 do
      begin
        R.A := R.A + Get(P, I, Bad);
        R.B := R.B + 1;
      end;
    finally
      Sink(1);
    end;
  except
    R.B := R.B + 100;
  end;
  Result := R.A * 1000 + R.B;
end;

function Reraised(P: PIntArr; N, Bad: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  R: TWide;
  I: Integer;
begin
  R.A := 0;
  R.B := 0;
  R.C := 0;
  try
    try
      for I := 0 to N - 1 do
      begin
        R.A := R.A + Get(P, I, Bad);
        R.B := R.B + 1;
      end;
    except
      Sink(1);
      raise;
    end;
  except
    R.B := R.B + 100;
  end;
  Result := R.A * 1000 + R.B;
end;

function LoopInHandler(P: PIntArr; N, Bad: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  R: TWide;
  I: Integer;
begin
  R.A := 0;
  R.B := 0;
  R.C := 0;
  try
    try
      Fail;
    except
      for I := 0 to N - 1 do
      begin
        R.A := R.A + Get(P, I, Bad);
        R.B := R.B + 1;
      end;
    end;
  except
    R.B := R.B + 100;
  end;
  Result := R.A * 1000 + R.B;
end;

function Fault(P: PIntArr; N: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  R: TWide;
  I: Integer;
  Q: PIntArr;
begin
  R.A := 0;
  R.B := 0;
  R.C := 0;
  try
    for I := 0 to N - 1 do
    begin
      if I = 3 then
        Q := nil
      else
        Q := P;
      R.A := R.A + Q^[I];
      R.B := R.B + 1;
    end;
  except
    R.B := R.B + 100;
  end;
  Result := R.A * 1000 + R.B;
end;

function Doubles(P: PIntArr; N, Bad: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  R: TWide;
  I: Integer;
begin
  R.A := 0;
  R.B := 0;
  R.C := 0.5;
  try
    for I := 0 to N - 1 do
    begin
      R.C := R.C + Get(P, I, Bad) * 0.25;
      R.A := R.A + 1;
    end;
  except
    R.C := R.C + 1000;
  end;
  Result := Trunc(R.C * 100) * 100 + R.A;
end;

function TwoRecords(P: PIntArr; N, Bad: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  R, Q: TWide;
  I: Integer;
begin
  R.A := 0;
  R.B := 0;
  R.C := 0;
  Q.A := 0;
  Q.B := 0;
  Q.C := 0;
  Result := 0;
  try
    for I := 0 to N - 1 do
    begin
      Q.A := Q.A + I;
      Q.B := Q.B + Q.A;
      R.A := R.A + Get(P, I, Bad);
      R.B := R.B + 1;
    end;
    Result := Q.A + Q.B;
  except
    R.B := R.B + 100;
  end;
  Result := Result * 1000000 + R.A * 1000 + R.B;
end;

{ ---- the record is the result of the function ---- }

function ResultRecord(P: PIntArr; N, Stop: Integer): TPair; {$IFDEF FPC} noinline; {$ENDIF}
var
  I: Integer;
begin
  Result.A := 0;
  Result.B := 0;
  for I := 0 to N - 1 do
  begin
    Result.A := Result.A + P^[I];
    Result.B := Result.B + 1;
    if P^[I] = Stop then
      Exit;
  end;
  Result.B := Result.B + 1000;
end;

function ResultWide(P: PIntArr; N, Stop: Integer): TWide; {$IFDEF FPC} noinline; {$ENDIF}
var
  I: Integer;
begin
  Result.A := 0;
  Result.B := 0;
  Result.C := 0;
  I := 0;
  while I < N do
  begin
    Result.A := Result.A + P^[I];
    Result.B := Result.B + 1;
    if P^[I] = Stop then
      Exit;
    Inc(I);
  end;
  Result.B := Result.B + 1000;
end;

{ ---- goto ---- }

function GotoOut(P: PIntArr; N, Stop: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
label
  Out;
var
  R: TWide;
  I: Integer;
begin
  R.A := 0;
  R.B := 0;
  R.C := 0;
  I := 0;
  while I < N do
  begin
    R.A := R.A + P^[I];
    R.B := R.B + 1;
    if P^[I] = Stop then
      goto Out;
    Inc(I);
  end;
  R.B := R.B + 1000;
Out:
  Result := R.A * 10000 + R.B;
end;

function GotoInside(P: PIntArr; N, Skip: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
label
  Next;
var
  R: TWide;
  I: Integer;
begin
  R.A := 0;
  R.B := 0;
  R.C := 0;
  I := 0;
  while I < N do
  begin
    R.B := R.B + 1;
    if P^[I] = Skip then
      goto Next;
    R.A := R.A + P^[I];
  Next:
    Inc(I);
  end;
  Result := R.A * 10000 + R.B;
end;

{ ---- the try statement inside the loop ---- }

function CleanupInside(P: PIntArr; N, Bad: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  R: TWide;
  I: Integer;
begin
  R.A := 0;
  R.B := 0;
  R.C := 0;
  try
    for I := 0 to N - 1 do
    begin
      try
        R.A := R.A + Get(P, I, Bad);
      finally
        R.B := R.B + R.A;
      end;
    end;
  except
    R.B := R.B + 1;
  end;
  Result := R.A * 100000 + R.B;
end;

function CleanupInsideWrites(P: PIntArr; N, Bad: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  R: TWide;
  I: Integer;
begin
  R.A := 0;
  R.B := 0;
  R.C := 0;
  try
    for I := 0 to N - 1 do
    begin
      try
        R.A := R.A + Get(P, I, Bad);
      finally
        R.B := 7 * I + 1;
      end;
      R.A := R.A + R.B;
    end;
  except
    R.A := R.A + 1000000;
  end;
  Result := R.A * 1000 + R.B;
end;

function BreakThroughCleanup(P: PIntArr; N, Stop: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  R: TWide;
  I: Integer;
begin
  R.A := 0;
  R.B := 0;
  R.C := 0;
  for I := 0 to N - 1 do
  begin
    try
      R.A := R.A + P^[I];
      R.B := R.B + 1;
      if P^[I] = Stop then
        Break;
    finally
      Sink(R.A * 1000 + R.B);
    end;
  end;
  Result := R.A * 1000 + R.B;
end;

function ContinueThroughCleanup(P: PIntArr; N, Skip: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  R: TWide;
  I: Integer;
begin
  R.A := 0;
  R.B := 0;
  R.C := 0;
  for I := 0 to N - 1 do
  begin
    try
      R.B := R.B + 1;
      if P^[I] = Skip then
        Continue;
      R.A := R.A + P^[I];
    finally
      Sink(R.A * 1000 + R.B);
    end;
  end;
  Result := R.A * 1000 + R.B;
end;

function ExitThroughCleanupInside(P: PIntArr; N, Stop: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  R: TWide;
  I: Integer;
begin
  R.A := 0;
  R.B := 0;
  R.C := 0;
  for I := 0 to N - 1 do
  begin
    try
      R.A := R.A + P^[I];
      R.B := R.B + 1;
      if P^[I] = Stop then
        Exit(R.A * 1000 + R.B);
    finally
      Sink(R.A * 1000 + R.B);
    end;
  end;
  Result := -(R.A * 1000 + R.B);
end;

function HandlerInside(P: PIntArr; N, Bad: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  R: TWide;
  I: Integer;
begin
  R.A := 0;
  R.B := 0;
  R.C := 0;
  for I := 0 to N - 1 do
  begin
    try
      R.A := R.A + Get(P, I, Bad);
      R.B := R.B + 1;
    except
      R.B := R.B + R.A * 10;
    end;
  end;
  Result := R.A * 100000 + R.B;
end;

function FaultInside(P: PIntArr; N: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  R: TWide;
  I: Integer;
  Q: PIntArr;
begin
  R.A := 0;
  R.B := 0;
  R.C := 0;
  for I := 0 to N - 1 do
  begin
    try
      if I = 3 then
        Q := nil
      else
        Q := P;
      R.A := R.A + Q^[I];
      R.B := R.B + 1;
    except
      R.B := R.B + R.A * 10;
    end;
  end;
  Result := R.A * 100000 + R.B;
end;

{$IFDEF FPC}
{ ---- an assembler block inside the loop names the field (Delphi has none in a Pascal routine) ---- }

function AsmReads(P: PIntArr; N: Integer): Int64; noinline;
var
  R: TWide;
  I: Integer;
  Last: Int64;
begin
  R.A := 0;
  R.B := 0;
  R.C := 0;
  Last := 0;
  for I := 0 to N - 1 do
  begin
    R.A := R.A + P^[I];
    asm
      mov rax, R.A
      mov Last, rax
    end;
    R.B := R.B + Last;
  end;
  Result := R.A * 1000 + R.B;
end;

function AsmWrites(P: PIntArr; N: Integer): Int64; noinline;
var
  R: TWide;
  I: Integer;
begin
  R.A := 0;
  R.B := 0;
  R.C := 0;
  for I := 0 to N - 1 do
  begin
    R.A := R.A + P^[I];
    asm
      mov rax, R.B
      add rax, 5
      mov R.B, rax
    end;
  end;
  Result := R.A * 1000 + R.B;
end;
{$ENDIF}

{ ---- nobody looks: the fields may stay in registers ---- }

procedure TMarkScanner.SkipBlanks;
begin
  while (FPos <= Length(FData)) and (FData[FPos] = ' ') do
    Inc(FPos);
end;

function TMarkScanner.Take(C: Char): Boolean;
begin
  Result := (FPos <= Length(FData)) and (FData[FPos] = C);
  if Result then
  begin
    if C = '<' then
      Inc(FLine);
    Inc(FPos);
  end;
end;

procedure TMarkScanner.Report(const Where: TMarkLoc);
begin
  Reported := Reported * 31 + Where.Line * 1000 + Where.Col;
end;

function TMarkScanner.ShapeCallsBudget: Integer;
var
  Level, Count, Mark: Integer;
  Loc: TMarkLoc;
begin
  Level := 0;
  Count := 0;
  Loc.Line := 0;
  Loc.Col := 0;
  repeat
    SkipBlanks;
    if Take(']') then
    begin
      if Level > 0 then
        Dec(Level);
      Continue;
    end;
    if not Take('<') then
      Break;
    Mark := FPos;
    if Take('[') then
    begin
      if Level = 0 then
      begin
        Loc.Line := FLine;
        Loc.Col := Mark;
      end;
      Inc(Level);
    end
    else
      Inc(Count, Mark);
  until False;
  if Level > 0 then
    Report(Loc);
  Result := Count;
end;

function ShapePlain(P: PIntArr; N: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  R: TWide;
  I: Integer;
begin
  R.A := 0;
  R.B := 0;
  R.C := 0;
  for I := 0 to N - 1 do
  begin
    R.A := R.A + P^[I];
    R.B := R.B + R.A;
  end;
  Result := R.A * 1000 + R.B;
end;

function ShapeGuardedUnread(P: PIntArr; N, Bad: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  R: TWide;
  I: Integer;
begin
  R.A := 0;
  R.B := 0;
  R.C := 0;
  try
    for I := 0 to N - 1 do
    begin
      R.A := R.A + Get(P, I, Bad);
      R.B := R.B + R.A;
    end;
    Result := R.A * 1000 + R.B;
  except
    Result := -1;
  end;
end;

function ShapeBeforeGuardRead(P: PIntArr; N, Bad: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  R: TWide;
  I: Integer;
begin
  R.A := 0;
  R.B := 0;
  R.C := 0;
  Sink(R.A);
  try
    for I := 0 to N - 1 do
    begin
      R.A := R.A + Get(P, I, Bad);
      R.B := R.B + R.A;
    end;
    Result := R.A * 1000 + R.B;
  except
    Result := -1;
  end;
end;

function BeforeGuardReentered(P: PIntArr; N, Bad: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  R: TWide;
  I, J: Integer;
begin
  R.A := 0;
  R.B := 0;
  R.C := 0;
  Result := 0;
  for J := 1 to 2 do
  begin
    Result := Result * 100 + R.A;
    try
      for I := 0 to N - 1 do
      begin
        R.A := R.A + Get(P, I, Bad);
        R.B := R.B + 1;
      end;
    except
      ;
    end;
  end;
end;

function ShapeCleanupUnread(P: PIntArr; N, Bad: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  R: TWide;
  I: Integer;
begin
  R.A := 0;
  R.B := 0;
  R.C := 0;
  try
    for I := 0 to N - 1 do
    begin
      R.A := R.A + Get(P, I, Bad);
      R.B := R.B + R.A;
    end;
  finally
    Sink(N);
  end;
  Result := R.A * 1000 + R.B;
end;

function ShapeOtherField(P: PIntArr; N, Bad: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  R: TWide;
  I: Integer;
begin
  R.A := 0;
  R.B := 0;
  R.C := 2;
  try
    for I := 0 to N - 1 do
    begin
      R.A := R.A + Get(P, I, Bad);
      R.B := R.B + R.A;
    end;
    Result := R.A * 1000 + R.B;
  except
    Result := -Trunc(R.C);
  end;
end;

function ShapeNoTrap(N: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
var
  R: TWide;
  I: Integer;
begin
  R.A := 0;
  R.B := 0;
  R.C := 0;
  try
    for I := 0 to N - 1 do
    begin
      R.A := R.A + I;
      R.B := R.B xor (R.A * 3);
    end;
    Sink(N);
  except
    R.B := R.B + 100;
  end;
  Result := R.A * 1000 + R.B;
end;

function Wrapped(P: PIntArr; N, Bad: Integer): Int64; {$IFDEF FPC} noinline; {$ENDIF}
begin
  try
    Result := ShapeCleanupUnread(P, N, Bad);
  except
    Result := -3;
  end;
end;

var
  I: Integer;
  Pair: TPair;
  Wide: TWide;
begin
  for I := 0 to 15 do
    Ints[I] := I * 3 + 1;
  Check('in-handler/none', InHandler(@Ints, 8, -1), 92008);
  Check('in-handler/at5', InHandler(@Ints, 8, 5), 35105);
  Check('behind-try/none', BehindTry(@Ints, 8, -1), 92008);
  Check('behind-try/at5', BehindTry(@Ints, 8, 5), 35005);
  Check('behind-try-repeat/none', BehindTryRepeat(@Ints, 8, -1), 92008);
  Check('behind-try-repeat/at5', BehindTryRepeat(@Ints, 8, 5), 35005);
  Seen := 0;
  Check('in-cleanup/none', InCleanup(@Ints, 8, -1), 92);
  Check('in-cleanup/none seen', Seen, 92008);
  Seen := 0;
  Check('in-cleanup/at5', InCleanup(@Ints, 8, 5), -2);
  Check('in-cleanup/at5 seen', Seen, 35005);
  Seen := 0;
  Check('exit-through-cleanup/found', ExitThroughCleanup(@Ints, 8, 10), 22);
  Check('exit-through-cleanup/found seen', Seen, 22004);
  Seen := 0;
  Check('exit-through-cleanup/none', ExitThroughCleanup(@Ints, 8, -1), 93);
  Check('exit-through-cleanup/none seen', Seen, 92008);
  Check('cleanup-then-handler/none', CleanupThenHandler(@Ints, 8, -1), 92008);
  Check('cleanup-then-handler/at5', CleanupThenHandler(@Ints, 8, 5), 35105);
  Check('reraised/none', Reraised(@Ints, 8, -1), 92008);
  Check('reraised/at5', Reraised(@Ints, 8, 5), 35105);
  Check('loop-in-handler/none', LoopInHandler(@Ints, 8, -1), 92008);
  Check('loop-in-handler/at5', LoopInHandler(@Ints, 8, 5), 35105);
  Check('fault', Fault(@Ints, 8), 12103);
  Check('doubles/none', Doubles(@Ints, 8, -1), 235008);
  Check('doubles/at5', Doubles(@Ints, 8, 5), 10092505);
  Check('two-records/none', TwoRecords(@Ints, 8, -1), 112092008);
  Check('two-records/at5', TwoRecords(@Ints, 8, 5), 35105);
  Pair := ResultRecord(@Ints, 8, 10);
  Check('result-record/found a', Pair.A, 22);
  Check('result-record/found b', Pair.B, 4);
  Pair := ResultRecord(@Ints, 8, -1);
  Check('result-record/none a', Pair.A, 92);
  Check('result-record/none b', Pair.B, 1008);
  Wide := ResultWide(@Ints, 8, 10);
  Check('result-wide/found a', Wide.A, 22);
  Check('result-wide/found b', Wide.B, 4);
  Wide := ResultWide(@Ints, 8, -1);
  Check('result-wide/none a', Wide.A, 92);
  Check('result-wide/none b', Wide.B, 1008);
  Check('goto-out/found', GotoOut(@Ints, 8, 10), 220004);
  Check('goto-out/none', GotoOut(@Ints, 8, -1), 921008);
  Check('goto-inside/found', GotoInside(@Ints, 8, 10), 820008);
  Check('goto-inside/none', GotoInside(@Ints, 8, -1), 920008);
  Check('cleanup-inside/none', CleanupInside(@Ints, 8, -1), 9200288);
  Check('cleanup-inside/at5', CleanupInside(@Ints, 8, 5), 3500111);
  Check('cleanup-inside-writes/none', CleanupInsideWrites(@Ints, 8, -1), 296050);
  Check('cleanup-inside-writes/at5', CleanupInsideWrites(@Ints, 8, 5), 1000110036);
  Seen := 0;
  Check('break-through-cleanup/found', BreakThroughCleanup(@Ints, 8, 10), 22004);
  Check('break-through-cleanup/found seen', Seen, 694466);
  Seen := 0;
  Check('break-through-cleanup/none', BreakThroughCleanup(@Ints, 8, -1), 92008);
  Check('break-through-cleanup/none seen', Seen, 1682500932);
  Seen := 0;
  Check('continue-through-cleanup/found', ContinueThroughCleanup(@Ints, 8, 10), 82008);
  Check('continue-through-cleanup/found seen', Seen, 1654490932);
  Seen := 0;
  Check('exit-through-cleanup-inside/found', ExitThroughCleanupInside(@Ints, 8, 10), 22004);
  Check('exit-through-cleanup-inside/found seen', Seen, 694466);
  Seen := 0;
  Check('exit-through-cleanup-inside/none', ExitThroughCleanupInside(@Ints, 8, -1), -92008);
  Check('exit-through-cleanup-inside/none seen', Seen, 1682500932);
  Check('handler-inside/none', HandlerInside(@Ints, 8, -1), 9200008);
  Check('handler-inside/at5', HandlerInside(@Ints, 8, 5), 7600357);
  Check('fault-inside', FaultInside(@Ints, 8), 8200127);
  Seen := -1;
  ManagedException(@Ints, 8, -1);
  Check('managed-exception/none', Seen, 9208);
  Seen := -1;
  ManagedException(@Ints, 8, 5);
  Check('managed-exception/at5', Seen, 3505);
  Seen := -1;
  ManagedExit(@Ints, 8);
  Check('managed-exit', Seen, 5106);
  Seen := -1;
  ShapeManagedNoTrap(8);
  Check('shape/managed-no-trap', Seen, 2808);
{$IFDEF FPC}
  Check('asm-reads', AsmReads(@Ints, 8), 92288);
{$ENDIF}
{$IFDEF FPC}
  Check('asm-writes', AsmWrites(@Ints, 8), 92040);
{$ENDIF}
  Check('shape/plain', ShapePlain(@Ints, 8), 92288);
  Check('shape/guarded-unread/none', ShapeGuardedUnread(@Ints, 8, -1), 92288);
  Check('shape/guarded-unread/at5', ShapeGuardedUnread(@Ints, 8, 5), -1);
  Seen := 0;
  Check('shape/before-guard-read/none', ShapeBeforeGuardRead(@Ints, 8, -1), 92288);
  Check('shape/before-guard-read/none seen', Seen, 0);
  Seen := 0;
  Check('shape/before-guard-read/at5', ShapeBeforeGuardRead(@Ints, 8, 5), -1);
  Check('shape/before-guard-read/at5 seen', Seen, 0);
  Check('before-guard-reentered/none', BeforeGuardReentered(@Ints, 8, -1), 92);
  Check('before-guard-reentered/at5', BeforeGuardReentered(@Ints, 8, 5), 35);
  Seen := 0;
  Check('shape/cleanup-unread/none', Wrapped(@Ints, 8, -1), 92288);
  Check('shape/cleanup-unread/none seen', Seen, 8);
  Seen := 0;
  Check('shape/cleanup-unread/at5', Wrapped(@Ints, 8, 5), -3);
  Check('shape/cleanup-unread/at5 seen', Seen, 8);
  Check('shape/other-field/none', ShapeOtherField(@Ints, 8, -1), 92288);
  Check('shape/other-field/at5', ShapeOtherField(@Ints, 8, 5), -2);
  Seen := 0;
  Check('shape/no-trap', ShapeNoTrap(8), 28064);
  Check('shape/no-trap seen', Seen, 8);
  Scanner := TMarkScanner.Create;
  Scanner.FData := '< <[ < <[ < ] < ]';
  Scanner.FPos := 1;
  Check('shape/calls-budget', Scanner.ShapeCallsBudget, 37);
  Check('shape/calls-budget reported', Scanner.Reported, 0);
  Scanner.FData := '< <[ < <[ < ] <';
  Scanner.FPos := 1;
  Scanner.FLine := 0;
  Check('shape/calls-budget open', Scanner.ShapeCallsBudget, 37);
  Check('shape/calls-budget open reported', Scanner.Reported, 2004);
  Scanner.Free;

  if Failures = 0 then
    WriteLn('RECORD_FIELDS_PASS')
  else
  begin
    WriteLn('RECORD_FIELDS_FAIL ', Failures);
    Halt(1);
  end;
end.
