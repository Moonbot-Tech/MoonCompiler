program method_value_receivers;
{$IFDEF MSWINDOWS}{$APPTYPE CONSOLE}{$ENDIF}
{$IFDEF FPC}{$mode delphi}{$H+}{$modeswitch typehelpers}{$modeswitch anonymousfunctions}{$modeswitch functionreferences}{$modeswitch inlinevars}{$ENDIF}
{ A method of a value - a record, an old-style object, the type a helper
  extends - given to a method pointer (M := R.Step): Self of the pointer is
  the address of the value, and every call through the pointer changes the
  value itself.  Delphi keeps a variable, or a part of one, in its own
  storage, and a value that is no variable (a function result, an
  expression) in a temporary of the routine, one per place in the source,
  until the routine returns.  Every form is its own routine, so that the
  optimizer may keep the value in a register there.  One source for Delphi
  12.2 and MoonCompiler: every expected number is Delphi's, and a case that
  differs prints what it got. }
uses
  SysUtils, method_value_receivers_unit;

type
  TMethodProc = procedure(Step: Integer) of object;
  TPlainProc = procedure(A: Integer);
  TProc0 = reference to procedure;
  TRec1 = record V: Byte; procedure Step(A: Integer); end;
  TRec2 = record V: Word; procedure Step(A: Integer); end;
  TRec4 = record
    V: Integer;
    constructor Create(AV: Integer);
    procedure Step(A: Integer);
    function Own: TMethodProc;
    function OwnSelf: TMethodProc;
  end;
  TRec8 = record V: Int64; procedure Step(A: Integer); end;
  TRecP = record P: PInteger; procedure Step(A: Integer); end;
  TRecD = record V: Double; procedure Step(A: Integer); end;
  TRecS = record V: Single; procedure Step(A: Integer); end;
  TPair = record A, B: Integer; procedure Step(X: Integer); end;
  TQuad = record A, B: Int64; procedure Step(X: Integer); end;
  TTriple = record A, B, C: Integer; procedure Step(X: Integer); end;
  TBig = record V: Integer; Pad: array[0..5] of Integer; procedure Step(A: Integer); end;
  TRecStr = record S: string; V: Integer; procedure Step(A: Integer); end;
  TOuter = record Inner: TRec4; end;
  TOuter8 = record Pad: Integer; Inner: TRec4; end;
  TArr2 = array[0..1] of TRec4;
  TObj = object A, B, C: Integer; procedure Step(X: Integer); end;
  TVObj = object
    V: Integer;
    constructor Init;
    procedure VStep(A: Integer); virtual;
  end;
  TVObj2 = object(TVObj)
    procedure VStep(A: Integer); virtual;
  end;
  TIntHelper = record helper for Integer procedure Bump(A: Integer); end;
  TDblHelper = record helper for Double procedure Bump(A: Integer); end;
  TSglHelper = record helper for Single procedure Bump(A: Integer); end;
  TI64Helper = record helper for Int64 procedure Bump(A: Integer); end;
  TPtrHelper = record helper for Pointer procedure Adv(A: Integer); end;
  TStrHelper = record helper for string procedure Grow(A: Integer); end;
  TColor3 = (cRed, cGreen, cBlue);
  TColorHelper = record helper for TColor3 procedure Next(A: Integer); end;
  TPairHelper = record helper for TPair procedure Bump(A: Integer); end;
  TCounter = class V: Integer; end;
  TCounterHelper = class helper for TCounter procedure Bump(A: Integer); end;
  TGen<T> = record V: Integer; Tag: T; procedure Step(A: Integer); end;
  TGen4<T> = record V: T; procedure Step(A: Integer); end;
  THolder = class
    FRec: TRec4;
    function GetRec: TRec4;
    property FieldRec: TRec4 read FRec;
    property GetterRec: TRec4 read GetRec;
  end;
  TSRec = record
    V: Integer;
    class procedure SStep(A: Integer); static;
    procedure Step(A: Integer);
  end;

var
  Last: Int64;
  LastS: string;
  SCount, Failures: Integer;
  GM: TMethodProc;

procedure TRec1.Step(A: Integer); begin Inc(V, A); Last := V; end;
procedure TRec2.Step(A: Integer); begin Inc(V, A); Last := V; end;
constructor TRec4.Create(AV: Integer); begin V := AV; end;
procedure TRec4.Step(A: Integer); begin Inc(V, A); Last := V; end;
function TRec4.Own: TMethodProc; begin Result := Step; end;
function TRec4.OwnSelf: TMethodProc; begin Result := Self.Step; end;
procedure TRec8.Step(A: Integer); begin Inc(V, A); Last := V; end;
procedure TRecP.Step(A: Integer); begin Inc(P^, A); Last := P^; end;
procedure TRecD.Step(A: Integer); begin V := V + A; Last := Round(V); end;
procedure TRecS.Step(A: Integer); begin V := V + A; Last := Round(V); end;
procedure TPair.Step(X: Integer); begin Inc(B, X); Last := B; end;
procedure TQuad.Step(X: Integer); begin Inc(B, X); Last := B; end;
procedure TTriple.Step(X: Integer); begin Inc(B, X); Last := B; end;
procedure TBig.Step(A: Integer); begin Inc(V, A); Last := V; end;
procedure TRecStr.Step(A: Integer); begin Inc(V, A); Last := V; LastS := S; end;
procedure TObj.Step(X: Integer); begin Inc(B, X); Last := B; end;
constructor TVObj.Init; begin V := 0; end;
procedure TVObj.VStep(A: Integer); begin Inc(V, A); Last := V; end;
procedure TVObj2.VStep(A: Integer); begin Inc(V, 10 * A); Last := V; end;
procedure TIntHelper.Bump(A: Integer); begin Self := Self + A; Last := Self; end;
procedure TDblHelper.Bump(A: Integer); begin Self := Self + A; Last := Round(Self); end;
procedure TSglHelper.Bump(A: Integer); begin Self := Self + A; Last := Round(Self); end;
procedure TI64Helper.Bump(A: Integer); begin Self := Self + A; Last := Self; end;
procedure TPtrHelper.Adv(A: Integer); begin Self := PByte(Self) + A; Last := NativeInt(Self); end;
procedure TStrHelper.Grow(A: Integer); begin Self := Self + StringOfChar('x', A); LastS := Self; Last := Length(Self); end;
procedure TColorHelper.Next(A: Integer); begin Self := TColor3((Ord(Self) + A) mod 3); Last := Ord(Self); end;
procedure TPairHelper.Bump(A: Integer); begin Inc(Self.B, A); Last := Self.B; end;
procedure TCounterHelper.Bump(A: Integer); begin Inc(Self.V, A); Last := Self.V; end;
procedure TGen<T>.Step(A: Integer); begin Inc(V, A); Last := V; end;
procedure TGen4<T>.Step(A: Integer); begin PInteger(@V)^ := PInteger(@V)^ + A; Last := PInteger(@V)^; end;
function THolder.GetRec: TRec4; begin Result := FRec; end;
class procedure TSRec.SStep(A: Integer); begin Inc(SCount, A); end;
procedure TSRec.Step(A: Integer); begin Inc(V, A); Last := V; end;

function MakeRec(V: Integer): TRec4; begin Result.V := V; end;
function MakeRec8(V: Integer): TRec8; begin Result.V := V; end;
function MakeBig(V: Integer): TBig; begin Result.V := V; end;
function MakeStr(const S: string): TRecStr; begin Result.S := S; Result.V := 1; end;
function GetInt: Integer; begin Result := 1; end;
procedure CallIt(M: TMethodProc; X: Integer); begin M(X); end;

procedure Check(const Name: string; Got, Expected: Int64);
begin
  If Got <> Expected then
  begin
    WriteLn('FAIL ', Name, ': got ', Got, ', expected ', Expected);
    Inc(Failures);
  end;
end;

{ records of every size a register holds, and larger ones, in a local }

procedure Local1; var R: TRec1; M: TMethodProc;
begin R.V := 1; M := R.Step; M(2); Check('local1', R.V, 3); end;

procedure Local2; var R: TRec2; M: TMethodProc;
begin R.V := 1; M := R.Step; M(2); Check('local2', R.V, 3); end;

procedure Local4; var R: TRec4; M: TMethodProc;
begin R.V := 1; M := R.Step; M(2); Check('local4', R.V, 3); end;

procedure Local8; var R: TRec8; M: TMethodProc;
begin R.V := 1; M := R.Step; M(2); Check('local8', R.V, 3); end;

procedure LocalPointerField; var R: TRecP; M: TMethodProc; X: Integer;
begin X := 1; R.P := @X; M := R.Step; M(2); Check('local-pointer-field', X, 3); end;

procedure LocalDouble; var R: TRecD; M: TMethodProc;
begin R.V := 1; M := R.Step; M(2); Check('local-double', Round(R.V), 3); end;

procedure LocalSingle; var R: TRecS; M: TMethodProc;
begin R.V := 1; M := R.Step; M(2); Check('local-single', Round(R.V), 3); end;

procedure LocalPair; var R: TPair; M: TMethodProc;
begin R.A := 0; R.B := 1; M := R.Step; M(2); Check('local-pair', R.B, 3); end;

procedure LocalQuad; var R: TQuad; M: TMethodProc;
begin R.A := 0; R.B := 1; M := R.Step; M(2); Check('local-quad', R.B, 3); end;

procedure LocalTriple; var R: TTriple; M: TMethodProc;
begin R.A := 0; R.B := 1; R.C := 0; M := R.Step; M(2); Check('local-triple', R.B, 3); end;

procedure LocalBig; var R: TBig; M: TMethodProc;
begin R.V := 1; M := R.Step; M(2); Check('local-big', R.V, 3); end;

procedure LocalManaged; var R: TRecStr; M: TMethodProc;
begin R.S := 'x'; R.V := 1; M := R.Step; M(2); Check('local-managed', R.V, 3); end;

{ the pointer points at the record itself, not at a copy }
procedure LocalTwice; var R: TRec4; M: TMethodProc;
begin R.V := 1; M := R.Step; M(2); R.V := R.V * 10; M(5); Check('local-twice', R.V, 35); end;

procedure InlineVar4;
begin
  var R: TRec4;
  R.V := 1;
  var M: TMethodProc := R.Step;
  M(2);
  Check('inline-var4', R.V, 3);
end;

procedure InlineVar8;
begin
  var R: TRec8;
  R.V := 1;
  var M: TMethodProc := R.Step;
  M(2);
  Check('inline-var8', R.V, 3);
end;

{ parameters: a value parameter is the callee's own copy }

procedure Value4(R: TRec4); var M: TMethodProc;
begin M := R.Step; M(2); Check('value4', R.V, 3); end;

procedure Value8(R: TRec8); var M: TMethodProc;
begin M := R.Step; M(2); Check('value8', R.V, 3); end;

procedure ValuePair(R: TPair); var M: TMethodProc;
begin M := R.Step; M(2); Check('value-pair', R.B, 3); end;

procedure ValueQuad(R: TQuad); var M: TMethodProc;
begin M := R.Step; M(2); Check('value-quad', R.B, 3); end;

procedure ValueBig(R: TBig); var M: TMethodProc;
begin M := R.Step; M(2); Check('value-big', R.V, 3); end;

procedure Const4(const R: TRec4); var M: TMethodProc;
begin M := R.Step; M(2); Check('const4', R.V, 3); end;

procedure ConstPair(const R: TPair); var M: TMethodProc;
begin M := R.Step; M(2); Check('const-pair', R.B, 3); end;

procedure ConstBig(const R: TBig); var M: TMethodProc;
begin M := R.Step; M(2); Check('const-big', R.V, 3); end;

procedure Var4(var R: TRec4); var M: TMethodProc;
begin M := R.Step; M(2); end;

procedure Out4(out R: TRec4); var M: TMethodProc;
begin R.V := 1; M := R.Step; M(2); end;

procedure Ref4(const [ref] R: TRec4); var M: TMethodProc;
begin M := R.Step; M(2); end;

procedure IntParam(I: Integer); var M: TMethodProc;
begin M := I.Bump; M(2); Check('int-param', I, 3); end;

procedure Parameters;
var R4: TRec4; R8: TRec8; RA: TPair; RQ: TQuad; RB: TBig;
begin
  R4.V := 1; Value4(R4); Check('value4-caller', R4.V, 1);
  R8.V := 1; Value8(R8); Check('value8-caller', R8.V, 1);
  RA.A := 0; RA.B := 1; ValuePair(RA); Check('value-pair-caller', RA.B, 1);
  RQ.A := 0; RQ.B := 1; ValueQuad(RQ); Check('value-quad-caller', RQ.B, 1);
  RB.V := 1; ValueBig(RB); Check('value-big-caller', RB.V, 1);
  R4.V := 1; Const4(R4);
  RA.B := 1; ConstPair(RA);
  RB.V := 1; ConstBig(RB);
  R4.V := 1; Var4(R4); Check('var4', R4.V, 3);
  Out4(R4); Check('out4', R4.V, 3);
  R4.V := 1; Ref4(R4); Check('ref4', R4.V, 3);
  IntParam(1);
end;

{ a part of a value: a field of a record in a record, an element of a static
  array, the target of with, a record typecast of a variable, a field of a
  class and a property read from it (memory - controls) }

procedure NestedField; var O: TOuter; M: TMethodProc;
begin O.Inner.V := 1; M := O.Inner.Step; M(2); Check('nested-field', O.Inner.V, 3); end;

procedure NestedField8; var O: TOuter8; M: TMethodProc;
begin O.Pad := 0; O.Inner.V := 1; M := O.Inner.Step; M(2); Check('nested-field8', O.Inner.V, 3); end;

procedure ElementConst; var A: TArr2; M: TMethodProc;
begin A[0].V := 0; A[1].V := 1; M := A[1].Step; M(2); Check('element-const', A[1].V, 3); end;

procedure ElementVar(I: Integer); var A: TArr2; M: TMethodProc;
begin A[0].V := 0; A[1].V := 1; M := A[I].Step; M(2); Check('element-var', A[1].V, 3); end;

procedure WithRecord; var R: TRec4; M: TMethodProc;
begin R.V := 1; with R do M := Step; M(2); Check('with', R.V, 3); end;

procedure WithField; var O: TOuter; M: TMethodProc;
begin O.Inner.V := 1; with O.Inner do M := Step; M(2); Check('with-field', O.Inner.V, 3); end;

procedure CastInteger; var X: Integer; M: TMethodProc;
begin X := 1; M := TRec4(X).Step; M(2); Check('cast-integer', X, 3); end;

procedure ClassFields; var H: THolder; M: TMethodProc;
begin
  H := THolder.Create;
  H.FRec.V := 1; M := H.FRec.Step; M(2); Check('class-field', H.FRec.V, 3);
  H.FRec.V := 1; M := H.FieldRec.Step; M(2); Check('property-field', H.FRec.V, 3);
  { a getter returns a copy }
  H.FRec.V := 1; M := H.GetterRec.Step; M(2); Check('property-getter', Last * 10 + H.FRec.V, 31);
  H.Free;
end;

{ a value that is no variable lives in a temporary of the routine: it keeps
  what the calls did to it, one per place in the source }

procedure FuncSmall; var M: TMethodProc;
begin M := MakeRec(1).Step; M(2); M(3); Check('function-small', Last, 6); end;

procedure Func8; var M: TMethodProc;
begin M := MakeRec8(1).Step; M(2); M(3); Check('function-8', Last, 6); end;

procedure FuncBig; var M: TMethodProc;
begin M := MakeBig(1).Step; M(2); M(3); Check('function-big', Last, 6); end;

procedure FuncManaged; var M: TMethodProc;
begin
  Last := 0;
  M := MakeStr('abc' + IntToStr(Last)).Step; M(2);
  Check('function-managed', Last * 1000 + Length(LastS), 3004);
end;

procedure FuncThenOther; var M: TMethodProc; X: Integer;
begin M := MakeRec(1).Step; X := MakeRec(7).V; M(2); Check('function-then-other', Last * 10 + X, 37); end;

procedure BigThenOther; var M: TMethodProc; X: Integer;
begin M := MakeBig(1).Step; X := MakeBig(7).V; M(2); Check('big-then-other', Last * 10 + X, 37); end;

procedure FuncLoop; var M: array[0..2] of TMethodProc; I: Integer;
begin for I := 0 to 2 do M[I] := MakeBig(I * 10).Step; M[0](1); M[2](1); Check('function-loop', Last, 22); end;

procedure RecordConstructor; var M: TMethodProc;
begin M := TRec4.Create(1).Step; M(2); M(3); Check('record-constructor', Last, 6); end;

procedure HelperOnCall; var M: TMethodProc;
begin M := GetInt.Bump; M(2); M(3); Check('helper-on-call', Last, 6); end;

procedure HelperOnExpression; var M: TMethodProc; I: Integer;
begin I := 0; M := (I + 1).Bump; M(2); M(3); Check('helper-on-expression', Last * 10 + I, 60); end;

procedure StringExpression; var S: string; M: TMethodProc;
begin S := ''; M := (S + 'ab').Grow; M(2); M(1); Check('string-expression', Last * 10 + Length(S), 50); end;

procedure WithFunction; var M: TMethodProc; X: Integer;
begin with MakeBig(1) do M := Step; X := MakeBig(7).V; M(2); Check('with-function', Last * 10 + X, 37); end;

procedure ManagedException; var M: TMethodProc;
begin
  try
    M := MakeStr('abcd').Step;
    M(2);
    raise Exception.Create('x');
  except
    Check('managed-exception', Last * 1000 + Length(LastS), 3004);
  end;
end;

{ old-style objects }

procedure ObjectLocal; var O: TObj; M: TMethodProc;
begin O.B := 1; M := O.Step; M(2); Check('object-local', O.B, 3); end;

procedure ObjectVirtual; var O: TVObj2; M: TMethodProc;
begin O.Init; O.V := 1; M := O.VStep; M(2); Check('object-virtual', O.V, 21); end;

procedure ObjectValue(O: TObj); var M: TMethodProc;
begin M := O.Step; M(2); Check('object-value', O.B, 3); end;

{ helpers: Self is the variable of the extended type }

procedure Helpers;
var I: Integer; D: Double; SG: Single; I64: Int64; P: Pointer; S: string; C: TColor3;
  R: TPair; CO: TCounter; M: TMethodProc;
begin
  I := 1; M := I.Bump; M(2); Check('integer-helper', I, 3);
  D := 1; M := D.Bump; M(2); Check('double-helper', Round(D), 3);
  SG := 1; M := SG.Bump; M(2); Check('single-helper', Round(SG), 3);
  I64 := 1; M := I64.Bump; M(2); Check('int64-helper', I64, 3);
  P := nil; M := P.Adv; M(8); Check('pointer-helper', NativeInt(P), 8);
  S := 'ab'; M := S.Grow; M(2); Check('string-helper', Length(S), 4);
  C := cRed; M := C.Next; M(2); Check('enum-helper', Ord(C), 2);
  R.A := 0; R.B := 1; M := R.Bump; M(2); Check('record-helper', R.B, 3);
  CO := TCounter.Create; CO.V := 1; M := CO.Bump; M(2); Check('class-helper', CO.V, 3); CO.Free;
end;

procedure IntegerHelperAlone; var I: Integer; M: TMethodProc;
begin I := 1; M := I.Bump; M(2); Check('integer-helper-alone', I, 3); end;

procedure DoubleHelperAlone; var D: Double; M: TMethodProc;
begin D := 1; M := D.Bump; M(2); Check('double-helper-alone', Round(D), 3); end;

{ other places of the form }

const
  RC: TRec4 = (V: 1);

procedure TypedConstant; var M: TMethodProc;
begin M := RC.Step; M(2); Check('typed-constant', RC.V, 3); end;

procedure Argument; var R: TRec4;
begin R.V := 1; CallIt(R.Step, 2); Check('argument', R.V, 3); end;

procedure InsideMethod; var R: TRec4; M: TMethodProc;
begin R.V := 1; M := R.Own(); M(2); M := R.OwnSelf(); M(3); Check('inside-method', R.V, 6); end;

procedure Generic; var R: TGen<Byte>; M: TMethodProc;
begin R.V := 1; R.Tag := 0; M := R.Step; M(2); Check('generic', R.V, 3); end;

procedure Generic4; var R: TGen4<Integer>; M: TMethodProc;
begin R.V := 1; M := R.Step; M(2); Check('generic4', R.V, 3); end;

procedure AnonymousOwn; var P: TProc0;
begin
  P := procedure
    var R: TRec4; M: TMethodProc;
    begin
      R.V := 1; M := R.Step; M(2); Check('anonymous-own', R.V, 3);
    end;
  P();
end;

procedure AnonymousCaptured; var R: TRec4; P: TProc0;
begin
  R.V := 1;
  P := procedure
    var M: TMethodProc;
    begin
      M := R.Step; M(2);
    end;
  P();
  Check('anonymous-captured', R.V, 3);
end;

procedure NestedParent;
var R: TRec4;
  procedure Inner;
  var M: TMethodProc;
  begin
    M := R.Step; M(2);
  end;
begin
  R.V := 1; Inner; Check('nested-parent', R.V, 3);
end;

procedure TryFinally; var R: TRec4; M: TMethodProc;
begin
  R.V := 1;
  try
    M := R.Step; M(2);
  finally
    Check('try-finally', R.V, 3);
  end;
end;

procedure TryExcept; var R: TRec4; M: TMethodProc;
begin
  R.V := 1;
  try
    M := R.Step; M(2);
    raise Exception.Create('x');
  except
    Check('try-except', R.V, 3);
  end;
end;

{ the for-in variable is a copy of the element }
procedure ForIn; var A: array[0..2] of TRec4; R: TRec4; M: TMethodProc; S: Integer;
begin
  A[0].V := 1; A[1].V := 2; A[2].V := 3; S := 0;
  for R in A do
  begin
    M := R.Step; M(10); S := S + R.V;
  end;
  Check('for-in', S * 10 + A[0].V, 361);
end;

function ViaResult: TRec4; var M: TMethodProc;
begin Result.V := 1; M := Result.Step; M(2); end;

procedure SetGlobal(var R: TRec4); inline;
begin GM := R.Step; end;

function OwnLocal: Integer; inline; var R: TRec4; M: TMethodProc;
begin R.V := 1; M := R.Step; M(2); Result := R.V; end;

{ the value parameter of an inlined routine stays a copy }
function Twice(R: TRec4): Integer; inline; var M: TMethodProc;
begin M := R.Step; M(2); Result := R.V; end;

procedure Inlined; var R: TRec4;
begin
  R.V := 1; SetGlobal(R); GM(2); Check('inline-var-param', R.V, 3);
  Check('inline-own-local', OwnLocal, 3);
  Check('result', ViaResult.V, 3);
end;

{ alone in its routine: an address of R taken elsewhere here would make the
  inlining copy R anyway }
procedure InlinedValueParam; var R: TRec4;
begin R.V := 1; Check('inline-value-param', Twice(R) * 10 + R.V, 31); end;

{ a static method takes no Self }
procedure StaticViaInstance; var R: TSRec; P: TPlainProc;
begin R.V := 1; SCount := 0; P := R.SStep; P(5); Check('static-via-instance', SCount * 10 + R.V, 51); end;

{ the address escapes into the pointer: a read after a call through it sees
  the change - in a loop and after a store made before the call }

procedure TripleLoop; var R: TTriple; M: TMethodProc; I, S: Integer;
begin
  R.A := 0; R.B := 1; R.C := 0; S := 0; M := R.Step;
  for I := 1 to 3 do begin M(1); S := S + R.B; end;
  Check('triple-loop', S, 9);
end;

procedure TripleStore; var R: TTriple; M: TMethodProc;
begin R.A := 0; R.C := 0; M := R.Step; R.B := 5; CallIt(M, 2); Check('triple-store', R.B, 7); end;

procedure ObjectLoop; var O: TObj; M: TMethodProc; I, S: Integer;
begin
  O.A := 0; O.B := 1; O.C := 0; S := 0; M := O.Step;
  for I := 1 to 3 do begin M(1); S := S + O.B; end;
  Check('object-loop', S, 9);
end;

procedure Rec4Loop; var R: TRec4; M: TMethodProc; I, S: Integer;
begin
  R.V := 1; S := 0; M := R.Step;
  for I := 1 to 3 do begin M(1); S := S + R.V; end;
  Check('rec4-loop', S, 9);
end;

procedure IntegerLoop; var X: Integer; M: TMethodProc; I, S: Integer;
begin
  X := 1; S := 0; M := X.Bump;
  for I := 1 to 3 do begin M(1); S := S + X; end;
  Check('integer-loop', S, 9);
end;

procedure Rec4Store; var R: TRec4; M: TMethodProc;
begin M := R.Step; R.V := 5; CallIt(M, 2); Check('rec4-store', R.V, 7); end;

var
  G1: TRec1;
  G4: TRec4;
  G8: TRec8;
  GD: TRecD;
  GPair: TPair;
  GOuter: TOuter;
  GArr: TArr2;
  GInt: Integer;
  GObj: TObj;
  M1, M4, M8, MD, MPair, MOuter, MArr, MInt, MFunc, MManaged, MObj: TMethodProc;
begin
  Failures := 0;
  Local1; Local2; Local4; Local8; LocalPointerField; LocalDouble; LocalSingle;
  LocalPair; LocalQuad; LocalTriple; LocalBig; LocalManaged; LocalTwice;
  InlineVar4; InlineVar8;
  Parameters;
  NestedField; NestedField8; ElementConst; ElementVar(1); WithRecord; WithField;
  CastInteger; ClassFields;
  FuncSmall; Func8; FuncBig; FuncManaged; FuncThenOther; BigThenOther; FuncLoop;
  RecordConstructor; HelperOnCall; HelperOnExpression; StringExpression;
  WithFunction; ManagedException;
  ObjectLocal; ObjectVirtual;
  GObj.B := 1; ObjectValue(GObj); Check('object-value-caller', GObj.B, 1);
  Helpers; IntegerHelperAlone; DoubleHelperAlone;
  TypedConstant; Argument; InsideMethod; Generic; Generic4;
  AnonymousOwn; AnonymousCaptured; NestedParent; TryFinally; TryExcept; ForIn;
  Inlined; InlinedValueParam; StaticViaInstance;
  TripleLoop; TripleStore; ObjectLoop; Rec4Loop; IntegerLoop; Rec4Store;

  { the main block of the program: its variables are read by nothing else }
  G1.V := 1; M1 := G1.Step; M1(2); Check('main1', G1.V, 3);
  G4.V := 1; M4 := G4.Step; M4(2); Check('main4', G4.V, 3);
  G8.V := 1; M8 := G8.Step; M8(2); Check('main8', G8.V, 3);
  GD.V := 1; MD := GD.Step; MD(2); Check('main-double', Round(GD.V), 3);
  GPair.A := 0; GPair.B := 1; MPair := GPair.Step; MPair(2); Check('main-pair', GPair.B, 3);
  GOuter.Inner.V := 1; MOuter := GOuter.Inner.Step; MOuter(2); Check('main-nested-field', GOuter.Inner.V, 3);
  GArr[0].V := 0; GArr[1].V := 1; MArr := GArr[1].Step; MArr(2); Check('main-element', GArr[1].V, 3);
  GInt := 1; MInt := GInt.Bump; MInt(2); Check('main-integer-helper', GInt, 3);
  MFunc := MakeRec(1).Step; MFunc(2); MFunc(3); Check('main-function', Last, 6);
  MManaged := MakeStr('abc').Step; MManaged(2); Check('main-function-managed', Last * 1000 + Length(LastS), 3003);
  GObj.B := 1; MObj := GObj.Step; MObj(2); Check('main-object', GObj.B, 3);

  { the initialization of a unit }
  Check('unit-initialization', InitRecord, 3);
  Check('unit-initialization-managed', InitManaged, 3005);

  If Failures = 0 then
    WriteLn('METHOD_VALUE_RECEIVERS_OK')
  else begin
    WriteLn('METHOD_VALUE_RECEIVERS_FAILED ', Failures);
    Halt(1);
  end;
end.
