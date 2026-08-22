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
  assignment, finalization during exception unwinding and a nested
  record copied through Assign.  Value-parameter copies and the array
  finalization order are a recorded pending axis (the byte copy does
  not run through Assign yet) and are deliberately not pinned. }

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

    WriteLn('RECORD_MANAGEMENT_OPERATORS_OK');
  except
    on E: Exception do begin
      WriteLn('RECORD_MANAGEMENT_OPERATORS_FAIL ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
