program funcref_value_sources;
{$IFDEF MSWINDOWS}{$APPTYPE CONSOLE}{$ENDIF}
{$IFDEF FPC}{$mode delphi}{$H+}{$modeswitch functionreferences}{$modeswitch anonymousfunctions}{$modeswitch inlinevars}{$ENDIF}
{ A method, a procedure variable or a routine given to "reference to"
  without @, as Delphi code writes it (P := C.Step): the reference behaves
  as the anonymous method  procedure(A) begin C.Step(A) end  - the object
  and the variable are read at every call, the locals they are read from are
  captured.  One source for Delphi 12.2 and MoonCompiler: every expected
  number is Delphi's, and a case that differs prints what it got. }
uses
  SysUtils;

type
  TIntProc = reference to procedure(Step: Integer);
  TStrProc = reference to procedure(const S: string);
  TMethodProc = procedure(Step: Integer) of object;
  TPlainProc = procedure(Step: Integer);

  TCounter = class
  private
    FOnStep: TMethodProc;
  public
    Count: Integer;
    Child: TCounter;
    OnStep: TMethodProc;
    procedure Step(Amount: Integer);
    procedure VStep(Amount: Integer); virtual;
    class procedure CStep(Amount: Integer);
    procedure FromSelf;
    procedure FromField;
    function MakeFromSelf: TIntProc;
    property OnStepProp: TMethodProc read FOnStep write FOnStep;
  end;

  TDouble = class(TCounter)
    procedure VStep(Amount: Integer); override;
  end;

  TCounterClass = class of TCounter;

  { a class that is not related to TCounter holds one }
  TOwner = class
    Held: TCounter;
    procedure FromHeld;
    function MakeFromHeld: TIntProc;
  end;

  TRec = record
    Count: Integer;
    procedure Step(Amount: Integer);
  end;

  EStepper = class(Exception)
    Count: Integer;
    procedure Step(Amount: Integer);
  end;

var
  A, B: TCounter;
  GC: TCounter;
  GP: TPlainProc;
  GI, GJ, GetCalls, ClassCount, Failures: Integer;
  GS: string;

procedure TCounter.Step(Amount: Integer);
begin
  Inc(Count, Amount);
end;

procedure TCounter.VStep(Amount: Integer);
begin
  Inc(Count, Amount);
end;

procedure TDouble.VStep(Amount: Integer);
begin
  Inc(Count, 2 * Amount);
end;

class procedure TCounter.CStep(Amount: Integer);
begin
  Inc(ClassCount, Amount);
end;

procedure TCounter.FromSelf;
var
  P: TIntProc;
begin
  P := Step;
  P(1);
end;

procedure TCounter.FromField;
var
  P: TIntProc;
begin
  Child := A;
  P := Child.Step;
  Child := B;
  P(1);
end;

function TCounter.MakeFromSelf: TIntProc;
begin
  Result := Step;
end;

procedure TOwner.FromHeld;
var
  P: TIntProc;
begin
  Held := A;
  P := Held.Step;
  Held := B;
  P(1);
end;

function TOwner.MakeFromHeld: TIntProc;
begin
  Result := Held.Step;
end;

procedure TRec.Step(Amount: Integer);
begin
  Inc(Count, Amount);
end;

procedure EStepper.Step(Amount: Integer);
begin
  Inc(Count, Amount);
end;

procedure PlainI(Step: Integer);
begin
  Inc(GI, Step);
end;

procedure PlainJ(Step: Integer);
begin
  Inc(GJ, Step);
end;

procedure Put(A: Integer); overload;
begin
  Inc(GI, A);
end;

procedure Put(const S: string); overload;
begin
  GS := GS + S;
end;

function GetObj: TCounter;
begin
  Inc(GetCalls);
  Result := A;
end;

function GetHandler: TMethodProc;
begin
  Inc(GetCalls);
  Result := A.Step;
end;

procedure Call(const P: TIntProc; V: Integer);
begin
  P(V);
end;

procedure Check(const Name: string; Got, Want: Integer);
begin
  If Got <> Want then begin
    WriteLn('FAIL ', Name, ': got ', Got, ', Delphi gives ', Want);
    Inc(Failures);
  end;
end;

{ A and B by digits: A*100 + B, then both are reset }
function AB: Integer;
begin
  Result := A.Count * 100 + B.Count;
  A.Count := 0;
  B.Count := 0;
end;

procedure FromLocal;
var
  C: TCounter;
  P: TIntProc;
begin
  C := A;
  P := C.Step;
  P(1);
  C := B;
  P(2);
end;

procedure FromParam(C: TCounter);
var
  P: TIntProc;
begin
  P := C.Step;
  P(1);
  C := B;
  P(2);
end;

procedure FromConstParam(const C: TCounter);
var
  P: TIntProc;
begin
  P := C.Step;
  P(3);
end;

function MakeFromParam(C: TCounter): TIntProc;
begin
  Result := C.Step;
end;

procedure FromGlobal;
var
  P: TIntProc;
begin
  GC := A;
  P := GC.Step;
  GC := B;
  P(1);
end;

procedure TwoLocals;
var
  C, D: TCounter;
  P, Q: TIntProc;
begin
  C := A;
  D := B;
  P := C.Step;
  Q := D.Step;
  P(1);
  Q(1);
end;

procedure TwoGlobals;
var
  P, Q: TIntProc;
begin
  P := A.Step;
  Q := B.Step;
  P(1);
  Q(2);
end;

procedure FromFunctionResult;
var
  P: TIntProc;
begin
  GetCalls := 0;
  P := GetObj.Step;
  P(1);
  P(1);
end;

procedure FromArrayElement;
var
  Objs: array[0..1] of TCounter;
  I: Integer;
  P: TIntProc;
begin
  Objs[0] := A;
  Objs[1] := B;
  I := 0;
  P := Objs[I].Step;
  I := 1;
  P(1);
end;

procedure FromArrayInWhile;
var
  Objs: array[0..1] of TCounter;
  Arr: array[0..1] of TIntProc;
  I: Integer;
begin
  Objs[0] := A;
  Objs[1] := B;
  I := 0;
  while I < 2 do begin
    Arr[I] := Objs[I].Step;
    Inc(I);
  end;
  I := 1;
  Arr[0](1);
  Arr[1](2);
end;

procedure FromRecord(out Count: Integer);
var
  R: TRec;
  P: TIntProc;
begin
  R.Count := 5;
  P := R.Step;
  P(1);
  P(1);
  Count := R.Count;
end;

procedure FromInlineVar;
begin
  var C := A;
  var P: TIntProc := C.Step;
  C := B;
  P(1);
end;

procedure FromAbsolute;
var
  C: TCounter;
  X: TCounter absolute C;
  P: TIntProc;
begin
  C := A;
  P := X.Step;
  C := B;
  P(1);
end;

procedure FromWith;
var
  C: TCounter;
  P: TIntProc;
begin
  C := A;
  with C do
    P := Step;
  P(1);
end;

procedure FromAnonymous;
var
  C: TCounter;
  Outer: TProc;
  P: TIntProc;
begin
  C := A;
  Outer := procedure
    begin
      P := C.Step;
    end;
  Outer();
  C := B;
  P(1);
end;

procedure FromNested;
var
  C: TCounter;
  P: TIntProc;

  procedure Take;
  begin
    P := C.Step;
  end;

begin
  C := A;
  Take;
  C := B;
  P(1);
end;

procedure FromNestedOwn;
var
  P: TIntProc;

  procedure Take;
  var
    C: TCounter;
  begin
    C := A;
    P := C.Step;
  end;

begin
  Take;
  P(1);
end;

procedure FromArgument;
var
  C: TCounter;
begin
  C := B;
  Call(C.Step, 1);
end;

procedure FromVirtual;
var
  C: TCounter;
  X: TDouble;
  P: TIntProc;
begin
  X := TDouble.Create;
  C := X;
  P := C.VStep;
  P(1);
  C := A;
  P(1);
  Check('virtual-TDouble', X.Count, 2);
  X.Free;
end;

procedure FromClassMethod;
var
  C: TCounter;
  CR: TCounterClass;
  P: TIntProc;
begin
  ClassCount := 0;
  C := A;
  P := C.CStep;
  P(1);
  CR := TCounter;
  P := CR.CStep;
  P(10);
  P := TCounter.CStep;
  P(100);
end;

procedure FromException;
var
  P: TIntProc;
  Count: Integer;
begin
  Count := -1;
  try
    raise EStepper.Create('step');
  except
    on E: EStepper do begin
      P := E.Step;
      P(4);
      Count := E.Count;
    end;
  end;
  Check('exception-object', Count, 4);
end;

procedure Overloads;
var
  P: TIntProc;
  Q: TStrProc;
begin
  GI := 0;
  GS := '';
  P := Put;
  Q := Put;
  P(5);
  Q('abc');
end;

procedure MethodVariable;
var
  MP: TMethodProc;
  F, H: TIntProc;
begin
  MP := A.Step;
  F := MP;
  MP := B.Step;
  H := MP;
  F(1);
  H(2);
end;

procedure MethodParameter(MP: TMethodProc);
var
  F: TIntProc;
begin
  F := MP;
  MP := B.Step;
  F(1);
end;

procedure EventField;
var
  F: TIntProc;
begin
  A.OnStep := A.Step;
  F := A.OnStep;
  A.OnStep := B.Step;
  F(1);
end;

procedure EventProperty;
var
  F: TIntProc;
begin
  A.OnStepProp := A.Step;
  F := A.OnStepProp;
  A.OnStepProp := B.Step;
  F(1);
end;

procedure HandlerResult;
var
  F: TIntProc;
begin
  GetCalls := 0;
  F := GetHandler();
  F(1);
  F(1);
end;

procedure PlainVariables;
var
  PV: TPlainProc;
  F, G: TIntProc;
begin
  GI := 0;
  GJ := 0;
  PV := PlainI;
  F := PV;
  PV := PlainJ;
  F(1);
  GP := PlainI;
  G := GP;
  GP := PlainJ;
  G(10);
end;

var
  Owner: TOwner;
  H: TCounter;
  P: TIntProc;
  N: Integer;
begin
  Failures := 0;
  A := TCounter.Create;
  B := TCounter.Create;

  FromLocal;             Check('local', AB, 102);
  FromParam(A);          Check('param', AB, 102);
  FromConstParam(A);     Check('const-param', AB, 300);
  P := MakeFromParam(B); P(7); P := nil;
                         Check('param-outlives-routine', AB, 7);
  FromGlobal;            Check('global', AB, 1);
  A.FromSelf;            Check('self', AB, 100);
  H := TCounter.Create;
  H.FromField;           Check('self-field', AB, 1);
  P := A.MakeFromSelf();   P(3); P := nil;
                         Check('self-outlives-routine', AB, 300);
  Owner := TOwner.Create;
  Owner.FromHeld;        Check('unrelated-self-field', AB, 1);
  Owner.Held := B;
  P := Owner.MakeFromHeld(); Owner.Held := A; P(4); P := nil;
                         Check('unrelated-self-field-outlives', AB, 400);
  TwoLocals;             Check('two-locals', AB, 101);
  TwoGlobals;            Check('two-globals', AB, 102);
  FromFunctionResult;    Check('function-result', AB, 200);
                         Check('function-result-calls', GetCalls, 2);
  FromArrayElement;      Check('array-element', AB, 1);
  FromArrayInWhile;      Check('array-in-while', AB, 3);
  FromRecord(N);         Check('record-local', N, 7);
  FromInlineVar;         Check('inline-var', AB, 1);
  FromAbsolute;          Check('absolute', AB, 1);
  FromWith;              Check('with', AB, 100);
  FromAnonymous;         Check('inside-anonymous', AB, 1);
  FromNested;            Check('nested-parent-local', AB, 1);
  FromNestedOwn;         Check('nested-own-local', AB, 100);
  FromArgument;          Check('argument', AB, 1);
  FromVirtual;           Check('virtual', AB, 100);
  FromClassMethod;       Check('class-method', ClassCount, 111);
  FromException;
  Overloads;             Check('overload-int', GI, 5);
                         Check('overload-str', Length(GS), 3);
  MethodVariable;        Check('method-variable', AB, 3);
  MethodParameter(A.Step); Check('method-parameter', AB, 1);
  EventField;            Check('event-field', AB, 1);
  EventProperty;         Check('event-property', AB, 1);
  HandlerResult;         Check('handler-result', AB, 200);
                         Check('handler-result-calls', GetCalls, 2);
  PlainVariables;        Check('plain-variables-I', GI, 0);
                         Check('plain-variables-J', GJ, 11);

  If Failures = 0 then
    WriteLn('FUNCREF_VALUE_SOURCES_OK')
  else begin
    WriteLn('FUNCREF_VALUE_SOURCES_FAILED ', Failures);
    Halt(1);
  end;
end.
