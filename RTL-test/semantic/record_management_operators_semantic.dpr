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

    WriteLn('RECORD_MANAGEMENT_OPERATORS_OK');
  except
    on E: Exception do begin
      WriteLn('RECORD_MANAGEMENT_OPERATORS_FAIL ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
