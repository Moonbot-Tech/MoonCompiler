program procvar_copied_from_routine;
{$mode objfpc}{$H+}
{$modeswitch functionreferences}
{$modeswitch inlinevars}
{ The type of @Routine is a copy of the routine's definition.  A call through
  it is an indirect call of whatever routine the variable holds, but the copy
  kept what the routine says about its own body, and calls through the type
  were compiled by it:
  - inline: the inliner read routine-only fields off the procedural type, an
    access violation (internal error 200412021 in 1.0.0), at every level for
    an explicitly inline routine and at -O3 for one that AUTOINLINE selects;
  - noreturn: every call through the type was taken for one that never
    returns, and -O3 folded the statements after it with the values from
    before the loop;
  - internconst: a constant argument was folded by an intrinsic number read
    off the procedural type (internal error 88);
  - assembler: the type of an assembler safecall routine was taken for one
    without the safecall wrapper, so a call through it did not check the
    HRESULT and the failure of another safecall routine held by the variable
    was lost.
  The indirect call and the direct call of the same routine must have the
  same effect. }

uses
  SysUtils;

type
  TDoneProc = reference to procedure(out Done: Boolean);

  TCounter = class
    Count: Integer;
    procedure Step(Amount: Integer); inline;
    { no inline directive: small enough for AUTOINLINE at -O3 }
    procedure Reached(out Done: Boolean);
    function Poll(const Check: TDoneProc): Boolean;
  end;

var
  Total: Integer;

procedure Add(Amount: Integer); inline;
begin
  Inc(Total, Amount);
end;

procedure TCounter.Step(Amount: Integer);
begin
  Inc(Count, Amount);
end;

procedure TCounter.Reached(out Done: Boolean);
begin
  Done := Count >= 5;
end;

function TCounter.Poll(const Check: TDoneProc): Boolean;
begin
  Check(Result);
end;

procedure Stop; noreturn;
begin
  Halt(3);
end;

procedure Go;
begin
end;

{ the type of Q is the type of @Stop, the call goes to Go and returns }
function SumThroughCopy(Count: Integer): Integer;
var
  I, Sum: Integer;
begin
  var Q := @Stop;
  Q := @Go;
  Sum := 0;
  for I := 1 to Count do
    begin
      Q();
      Sum := Sum + I;
    end;
  Result := Sum;
end;

{ the body in Intel syntax under its own directive: the product profile
  (-Rintel) and the gate profile (no -R) read it the same }
{$asmmode intel}
procedure SafeAsm; safecall; assembler;
asm
  xor eax, eax
end;

procedure SafeFails; safecall;
begin
  raise Exception.Create('SafeFails');
end;

{ the type of Q is the type of @SafeAsm, the call goes to SafeFails }
function SafecallFailureRaised: Boolean;
begin
  Result := False;
  var Q := @SafeAsm;
  Q();
  Q := @SafeFails;
  try
    Q();
  except
    Result := True;
  end;
end;

procedure Check(Condition: Boolean; const Name: string);
begin
  If not Condition then begin
    WriteLn('FAIL ', Name);
    Halt(1);
  end;
end;

var
  C: TCounter;
  Direct: Boolean;
begin
  Add(2);
  var AddRef := @Add;
  AddRef(3);
  Check(Total = 5, 'procedure');
  C := TCounter.Create;
  C.Step(2);
  var StepRef := @C.Step;
  StepRef(3);
  Check(C.Count = 5, 'method');
  C.Reached(Direct);
  Check(Direct and C.Poll(@C.Reached), 'reference');
  StepRef(-1);
  C.Reached(Direct);
  Check(not Direct and not C.Poll(@C.Reached), 'reference after change');
  C.Free;
  Check(SumThroughCopy(3) = 6, 'noreturn');
  var OddRef := @Odd;
  Check(OddRef(3) and not OddRef(4), 'internconst');
  Check(SafecallFailureRaised, 'assembler');
  WriteLn('PROCVAR_COPIED_FROM_ROUTINE_OK');
end.
