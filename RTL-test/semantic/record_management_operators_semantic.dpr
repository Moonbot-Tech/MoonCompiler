program record_management_operators_semantic;

{ dvl-0035: Delphi declares the record management operators as
  Initialize(out Dest), Finalize(var Dest) and Assign(var Dest;
  const [ref] Src).  We rejected Initialize's out form and the Assign
  name entirely.  Both now parse: Assign maps onto the copy management
  slot with its parameter numbers swapped, so the physical convention
  keeps the runtime's (source, dest) order while the body keeps the
  user's names; the body of Initialize receives raw storage (its out
  parameter is exempt from the callee-side managed-out initialization,
  which would recurse).

  The pin checks the DCC64-measured lifecycle trace for locals with an
  assignment, finalization during exception unwinding, a nested record
  copied through Assign, and value-parameter copies: the caller builds
  the per-call temp with Initialize + the user's Assign and finalizes
  it right after the call - for a bare record, in a loop, and for an
  aggregate record whose field carries the operators.  A function
  result keeps the balance contract: every Initialize call is paired
  with exactly one Finalize (our temp path calls a few more pairs than
  DCC's in-place result, which even skips finalizing the overwritten
  value - the balance check holds on both).  Open array parameters of
  such records are a recorded pending axis and are not pinned. }

{$APPTYPE CONSOLE}

uses
  {$ifdef FPC}
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  {$endif UNIX}
  {$endif FPC}
  SysUtils;

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

procedure Locals;
var
  A, B: TRes;
begin
  A.Slot := 5;
  B := A;
  Trace := Trace + '|' + IntToStr(B.Slot) + '|';
end;

procedure ExceptionPath;
var
  E: TRes;
begin
  E.Slot := 9;
  raise Exception.Create('x');
end;

procedure Nested;
type
  TOuter = record
    Inner: TRes;
    Plain: Integer;
  end;
var
  O1, O2: TOuter;
begin
  O1.Inner.Slot := 40;
  O1.Plain := 7;
  O2 := O1;
  If (O2.Inner.Slot <> 41) or (O2.Plain <> 7) then
    raise Exception.Create('nested copy values');
  Trace := Trace + 'n' + IntToStr(O2.Inner.Slot);
end;

type
  TOuterParam = record
    Inner: TRes;
    Plain: Integer;
  end;

procedure Sink(V: TRes);
begin
  Trace := Trace + 'v' + IntToStr(V.Slot);
end;

procedure SinkOuter(V: TOuterParam);
begin
  Trace := Trace + 'v' + IntToStr(V.Inner.Slot) + ':' + IntToStr(V.Plain);
end;

procedure LoopParams;
var
  L: TRes;
  K: Integer;
begin
  L.Slot := 1;
  for K := 1 to 3 do begin
    Trace := Trace + '|';
    Sink(L);
  end;
end;

procedure OuterParam;
var
  O: TOuterParam;
begin
  O.Inner.Slot := 5;
  O.Plain := 9;
  Trace := Trace + '|';
  SinkOuter(O);
  Trace := Trace + '|';
end;

type
  TPair = array[0..1] of TRes;

  { the ONLY operator carrier is a static-array field: the aggregate bit
    must be inherited through the array wrapping at type-building time }
  THolder = record
    Arr: TPair;
    Plain: Integer;
  end;

procedure SinkHolder(V: THolder);
begin
  Trace := Trace + 'v' + IntToStr(V.Arr[0].Slot);
end;

procedure ArrayFieldHolder;
var
  A, B: THolder;
begin
  A.Arr[0].Slot := 10;
  A.Arr[1].Slot := 20;
  A.Plain := 7;
  B := A;
  Trace := Trace + '|' + IntToStr(B.Arr[0].Slot) + ':' + IntToStr(B.Arr[1].Slot) + ':' + IntToStr(B.Plain) + '|';
end;

procedure ArrayFieldParam;
var
  H: THolder;
begin
  H.Arr[0].Slot := 30;
  H.Arr[1].Slot := 40;
  H.Plain := 9;
  Trace := Trace + '|';
  SinkHolder(H);
  Trace := Trace + '|';
end;

procedure TakeAll(A: array of TRes);
begin
  Trace := Trace + 'y' + IntToStr(Length(A));
  If Length(A) > 0 then
    Trace := Trace + ':' + IntToStr(A[0].Slot) + ':' + IntToStr(A[High(A)].Slot);
end;

procedure TakeOuters(A: array of TOuterParam);
begin
  Trace := Trace + 'y' + IntToStr(A[0].Inner.Slot) + ':' + IntToStr(A[0].Plain);
end;

procedure TakePairs(A: array of TPair);
begin
  Trace := Trace + 'y' + IntToStr(A[0][0].Slot) + ':' + IntToStr(A[0][1].Slot);
end;

procedure TakePair(P: TPair);
begin
  Trace := Trace + 'y' + IntToStr(P[0].Slot) + ':' + IntToStr(P[1].Slot);
end;

procedure OpenArrayStatic;
var
  A: array[0..2] of TRes;
begin
  A[0].Slot := 10;
  A[1].Slot := 20;
  A[2].Slot := 30;
  Trace := Trace + '|';
  TakeAll(A);
  Trace := Trace + '|';
end;

procedure OpenArrayEmptyAndDyn;
var
  D: TArray<TRes>;
begin
  D := nil;
  TakeAll(D);
  Trace := Trace + '|';
  SetLength(D, 2);
  D[0].Slot := 7;
  D[1].Slot := 8;
  TakeAll(D);
end;

procedure OpenArraySlice;
var
  A: array[0..2] of TRes;
begin
  A[0].Slot := 1;
  A[1].Slot := 2;
  A[2].Slot := 3;
  Trace := Trace + '|';
  TakeAll(Slice(A, 2));
  Trace := Trace + '|';
end;

procedure OpenArrayOuters;
var
  O: array[0..1] of TOuterParam;
begin
  O[0].Inner.Slot := 40;
  O[0].Plain := 5;
  O[1].Inner.Slot := 50;
  O[1].Plain := 6;
  Trace := Trace + '|';
  TakeOuters(O);
  Trace := Trace + '|';
end;

procedure OpenArrayPairs;
var
  P: array[0..0] of TPair;
begin
  P[0][0].Slot := 60;
  P[0][1].Slot := 70;
  Trace := Trace + '|';
  TakePairs(P);
  Trace := Trace + '|';
end;

procedure StaticArrayParam;
var
  P: TPair;
begin
  P[0].Slot := 10;
  P[1].Slot := 20;
  Trace := Trace + '|';
  TakePair(P);
  Trace := Trace + '|';
end;

var
  Boom: Integer;

type
  TBomb = record
    Slot: Integer;
    class operator Initialize(out Dest: TBomb);
    class operator Finalize(var Dest: TBomb);
    class operator Assign(var Dest: TBomb; const [ref] Src: TBomb);
  end;

class operator TBomb.Initialize(out Dest: TBomb);
begin
  Dec(Boom);
  If Boom = 0 then begin
    Trace := Trace + 'I!';
    raise Exception.Create('boom');
  end;
  Dest.Slot := 100;
  Trace := Trace + 'i';
end;

class operator TBomb.Finalize(var Dest: TBomb);
begin
  Trace := Trace + 'f' + IntToStr(Dest.Slot);
end;

class operator TBomb.Assign(var Dest: TBomb; const [ref] Src: TBomb);
begin
  Dec(Boom);
  If Boom = 0 then begin
    Trace := Trace + 'A!';
    raise Exception.Create('boom');
  end;
  Dest.Slot := Src.Slot + 1;
  Trace := Trace + 'a';
end;

procedure TakeBombs(A: array of TBomb);
begin
  Trace := Trace + 'y' + IntToStr(A[0].Slot);
end;

procedure BombScenario;
var
  A: array[0..2] of TBomb;
begin
  A[0].Slot := 10;
  A[1].Slot := 20;
  A[2].Slot := 30;
  Trace := Trace + '|';
  TakeBombs(A);
  Trace := Trace + '|';
end;

procedure SinkRaising(V: TRes);
begin
  Trace := Trace + 'v' + IntToStr(V.Slot);
  raise Exception.Create('x');
end;

{ inline calls carry the same operator copy with the same ownership:
  the body is expanded, yet Initialize + the user's Assign still run at
  the call point and the copy still dies at the return point and during
  unwinding (dvl-0057) }
procedure SinkInlined(V: TRes); inline;
begin
  V.Slot := V.Slot + 500;
  Trace := Trace + 'v' + IntToStr(V.Slot);
end;

procedure InlinedParam;
var
  L: TRes;
begin
  L.Slot := 5;
  Trace := Trace + '|';
  SinkInlined(L);
  Trace := Trace + '|' + IntToStr(L.Slot) + '|';
end;

procedure SinkInlinedRaise(V: TRes); inline;
begin
  Trace := Trace + 'v' + IntToStr(V.Slot);
  raise Exception.Create('x');
end;

procedure InlinedRaise;
var
  L: TRes;
begin
  L.Slot := 5;
  Trace := Trace + '|';
  SinkInlinedRaise(L);
end;

{ the callee buries the parameter copy: its Finalize must run during
  unwinding too, not only on the normal path (dvl-0057) }
procedure RaisingBody;
var
  L: TRes;
begin
  L.Slot := 5;
  Trace := Trace + '|';
  SinkRaising(L);
end;

procedure SinkTwoBombs(A, B: TBomb);
begin
  Trace := Trace + 'v' + IntToStr(A.Slot) + ':' + IntToStr(B.Slot);
end;

{ a raising Assign of the SECOND copy before the call happens: everything
  built so far on the caller side leaks, exactly like DCC64 }
procedure TwoBombs;
var
  X, Y: TBomb;
begin
  X.Slot := 10;
  Y.Slot := 20;
  Trace := Trace + '|';
  SinkTwoBombs(X, Y);
  Trace := Trace + '|';
end;

{ a custom-Initialize LOCAL no longer blocks inlining; the frame follows
  the DCC64 model: Init of every copy, then Init of every local, then the
  user's Assigns; locals die first (reverse), then the copies (reverse) }
procedure SinkMixIn(V: TRes); inline;
var
  M: TRes;
begin
  M.Slot := V.Slot + 50;
  Trace := Trace + 'v' + IntToStr(M.Slot);
end;

procedure InlinedMix;
var
  L: TRes;
begin
  L.Slot := 5;
  Trace := Trace + '|';
  SinkMixIn(L);
  Trace := Trace + '|';
end;

procedure SinkTwoMixIn(A, B: TRes); inline;
var
  M: TRes;
begin
  M.Slot := A.Slot + B.Slot;
  Trace := Trace + 'v' + IntToStr(M.Slot);
end;

procedure InlinedTwoMix;
var
  X, Y: TRes;
begin
  X.Slot := 10;
  Y.Slot := 20;
  Trace := Trace + '|';
  SinkTwoMixIn(X, Y);
  Trace := Trace + '|';
end;

type
  { class fields carry the operators through the mop-offset init table:
    a static-array field contributes one entry per element - it used to be
    skipped entirely, so array elements were never Initialize'd while
    CleanupInstance still Finalize'd them (dvl-0058) }
  TBox = class
  public
    Direct: TRes;
    Arr: TPair;
    Plain: Integer;
  end;

procedure ClassFields;
var
  B: TBox;
begin
  Trace := Trace + '|';
  B := TBox.Create;
  Trace := Trace + '|' + IntToStr(B.Direct.Slot) + ':' + IntToStr(B.Arr[0].Slot) + ':' + IntToStr(B.Arr[1].Slot) + '|';
  B.Free;
  Trace := Trace + '|';
end;

function MakeRes: TRes;
begin
  Result.Slot := 7;
end;

procedure ResultBalance;
var
  L: TRes;
begin
  L.Slot := 3;
  L := MakeRes;
  If L.Slot <> 7 then
    raise Exception.Create('result value');
end;

procedure CheckBalance(const Name: string);
var
  K, Inits, Fins: Integer;
begin
  Inits := 0;
  Fins := 0;
  for K := 1 to Length(Trace) do
    case Trace[K] of
      'i': Inc(Inits);
      'f': Inc(Fins);
    end;
  If Inits <> Fins then
    raise Exception.CreateFmt('%s: %d Initialize vs %d Finalize',
      [Name, Inits, Fins]);
  Trace := '';
end;

begin
  try
    Trace := '';
    Locals;
    Check('locals', 'iia|6|f6f5');

    Trace := '';
    try
      ExceptionPath;
    except
      Trace := Trace + 'X';
    end;
    Check('except', 'if9X');

    Trace := '';
    Nested;
    Check('nested', 'iian41f41f40');

    Trace := '';
    LoopParams;
    Check('loop params', 'i|iav2f2|iav2f2|iav2f2f1');

    Trace := '';
    OuterParam;
    Check('outer param', 'i|iav6:9f6|f5');

    Trace := '';
    ResultBalance;
    CheckBalance('result balance');

    Trace := '';
    ArrayFieldHolder;
    Check('array field locals', 'iiiiaa|11:21:7|f11f21f10f20');

    Trace := '';
    ArrayFieldParam;
    Check('array field param', 'ii|iiaav31f31f41|f30f40');

    Trace := '';
    OpenArrayStatic;
    Check('open array static', 'iii|iiiaaay3:11:31f11f21f31|f10f20f30');

    Trace := '';
    OpenArrayEmptyAndDyn;
    Check('open array empty+dyn', 'y0|iiiiaay2:8:9f8f9f7f8');

    Trace := '';
    OpenArraySlice;
    Check('open array slice', 'iii|iiaay2:2:3f2f3|f1f2f3');

    Trace := '';
    OpenArrayOuters;
    Check('open array outers', 'ii|iiaay41:5f41f51|f40f50');

    Trace := '';
    OpenArrayPairs;
    Check('open array pairs', 'ii|iiaay61:71f61f71|f60f70');

    Trace := '';
    StaticArrayParam;
    Check('static array param', 'ii|iiaay11:21f11f21|f10f20');

    { the copy of an open array parameter leaks when a user operator
      raises mid-copy, exactly like DCC64: a raising Assign leaves the
      whole copy unfinalized, a raising Initialize finalizes only the
      initialized prefix (the balance check does not apply here) }
    Trace := '';
    Boom := 8;
    try
      BombScenario;
    except
      Trace := Trace + 'X';
    end;
    Check('open array assign raise', 'iii|iiiaA!f10f20f30X');

    Trace := '';
    Boom := 5;
    try
      BombScenario;
    except
      Trace := Trace + 'X';
    end;
    Check('open array initialize raise', 'iii|iI!f100f10f20f30X');

    Trace := '';
    try
      RaisingBody;
    except
      Trace := Trace + 'X';
    end;
    Check('raising body param', 'i|iav6f6f5X');

    Trace := '';
    InlinedParam;
    Check('inlined param', 'i|iav506f506|5|f5');

    Trace := '';
    try
      InlinedRaise;
    except
      Trace := Trace + 'X';
    end;
    Check('inlined raising body', 'i|iav6f6f5X');

    Trace := '';
    InlinedMix;
    Check('inlined custom-init local', 'i|iiav56f56f6|f5');

    Trace := '';
    InlinedTwoMix;
    Check('inlined frame phases', 'ii|iiiaav32f32f21f11|f20f10');

    Trace := '';
    ClassFields;
    Check('class array field init', '|iii|100:100:100|f100f100f100|');

    Trace := '';
    Boom := 6;
    try
      TwoBombs;
    except
      Trace := Trace + 'X';
    end;
    Check('second copy assign raise', 'ii|iaiA!f20f10X');

    WriteLn('RECORD_MANAGEMENT_OPERATORS_OK');
  except
    on E: Exception do begin
      WriteLn('RECORD_MANAGEMENT_OPERATORS_FAIL ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
