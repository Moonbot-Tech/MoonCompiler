program inline_const_alias_semantic;

{ The const-parameter inliner gate distinguishes storage owned by the callee
  from captured/non-local storage.  Pure readers over a global are admitted;
  a nested routine which writes the argument's source must preserve the real
  call's value, whether by retaining the call or by materializing a safe temp.
  This matters for both ABI forms: Win64 aliases this record through a const
  reference, while Linux x86-64 passes its snapshot by value.

  An actual only the caller reaches - a constant, a local nobody holds the
  address of and no nested routine sees - goes into a writing body directly.
  The body can still change such a local through the same call: a var or out
  parameter naming it or its absolute twin, the Self of a record method, the
  result assigned to it, a pointer to it.  Each of these keeps the value the
  real call would pass. }

{$APPTYPE CONSOLE}

uses
  {$ifdef FPC}
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  {$endif UNIX}
  {$endif FPC}
  SysUtils;

type
  TBig = record
    A, B, C, D: Integer;
  end;

  TPair = record
    A, B: Integer;
    procedure BumpA(const V: Integer); inline;
  end;

  TNamed = record
    Name: string;
    procedure Append(const V: string); inline;
  end;
  PString = ^string;

var
  GBig: TBig;
  GSeen, GSeen2, GX: Integer;
  GText, GText2: string;

function SumBig(const V: TBig): Integer; inline;
begin
  Result := V.A + V.B + V.C + V.D;
end;

procedure PureGlobalRead;
begin
  GBig.A := 10;
  GBig.B := 20;
  GBig.C := 30;
  GBig.D := 40;
  If SumBig(GBig) <> 100 then
    raise Exception.Create('pure global read');
end;

procedure CapturedAlias;
var
  X: TBig;
  Actual: Integer;

  function ReadAfterWrite(const V: TBig): Integer; inline;
  begin
    X.A := X.A + 1;
    Result := V.A;
  end;

begin
  X.A := 41;
  Actual := ReadAfterWrite(X);
  {$ifdef WINDOWS}
  If Actual <> 42 then
  {$else WINDOWS}
  If Actual <> 41 then
  {$endif WINDOWS}
    raise Exception.CreateFmt('captured const record: result=%d, source=%d',
      [Actual, X.A]);
  If X.A <> 42 then
    raise Exception.CreateFmt('captured record mutation: result=%d, source=%d',
      [Actual, X.A]);
end;

procedure CapturedScalar;
var
  X: Integer;
  Actual: Integer;

  function ReadScalarAfterWrite(const V: Integer): Integer; inline;
  begin
    X := X + 1;
    Result := V;
  end;

begin
  X := 41;
  Actual := ReadScalarAfterWrite(X);
  If Actual <> 41 then
    raise Exception.CreateFmt('captured const scalar: result=%d, source=%d',
      [Actual, X]);
  If X <> 42 then
    raise Exception.CreateFmt('captured scalar mutation: result=%d, source=%d',
      [Actual, X]);
end;

procedure BumpAndSee(var A: Integer; const B: Integer); inline;
begin
  A := A + 1;
  GSeen := B;
end;

procedure Check(Ok: Boolean; const What: string; Actual, Expected: Integer);
begin
  If not Ok then
    raise Exception.CreateFmt('%s: %d, expected %d', [What, Actual, Expected]);
end;

procedure SameLocalVarAndConst;
var
  X: Integer;
begin
  X := 41;
  BumpAndSee(X, X);
  Check(GSeen = 41, 'one local as var and const', GSeen, 41);
  Check(X = 42, 'one local as var and const, the var', X, 42);
end;

procedure AbsoluteTwin;
var
  X: Integer;
  Y: Integer absolute X;
begin
  X := 41;
  BumpAndSee(Y, X);
  Check(GSeen = 41, 'absolute twin as var', GSeen, 41);
  Check(X = 42, 'absolute twin as var, the var', X, 42);
end;

procedure TPair.BumpA(const V: Integer);
begin
  A := A + 1;
  GSeen := V;
end;

procedure RecordSelf;
var
  R: TPair;
begin
  R.A := 41;
  R.B := 0;
  R.BumpA(R.A);
  Check(GSeen = 41, 'field of the record Self', GSeen, 41);
  Check(R.A = 42, 'field of the record Self, the field', R.A, 42);
end;

function SevenThenValue(const V: Integer): Integer; inline;
begin
  Result := 7;
  GSeen := V;
  Result := Result + V;
end;

procedure ResultIsActual;
var
  X: Integer;
begin
  X := 41;
  X := SevenThenValue(X);
  Check(GSeen = 41, 'the result assigned to the actual', GSeen, 41);
  Check(X = 48, 'the result assigned to the actual, the result', X, 48);
end;

function Bracket(const S: string): string; inline;
begin
  Result := '<';
  GText := S;
  Result := Result + S + '>';
end;

procedure StringResultIsActual;
var
  S: string;
begin
  S := Copy('xabc', 2, 3);
  S := Bracket(S);
  If (S <> '<abc>') or (GText <> 'abc') then
    raise Exception.CreateFmt('the string result assigned to the actual: %s, %s', [S, GText]);
end;

{ Delphi 12.2 substitutes the actual of these two forms (a local behind a
  pointer, a global the body writes) and reads it after the body's write:
  42.  The value is the one of the real call, 41. }
procedure ThroughPointer(P: PInteger; const V: Integer); inline;
begin
  P^ := P^ + 1;
  GSeen := V;
end;

procedure AddressTaken;
var
  X: Integer;
  P: PInteger;
begin
  X := 41;
  P := @X;
  ThroughPointer(P, X);
  Check(GSeen = 41, 'a local whose address is held', GSeen, 41);
  Check(X = 42, 'a local whose address is held, the local', X, 42);
end;

procedure BumpGlobalAndSee(const V: Integer); inline;
begin
  Inc(GX);
  GSeen := V;
end;

procedure GlobalActual;
begin
  GX := 41;
  BumpGlobalAndSee(GX);
  Check(GSeen = 41, 'a global the body writes', GSeen, 41);
  Check(GX = 42, 'a global the body writes, the global', GX, 42);
end;

procedure LocalOfInlined(const V: Integer); inline;
var
  L: Integer;
begin
  L := V;
  BumpAndSee(L, L);
  GSeen2 := L;
end;

procedure TempOfOuterInline;
var
  X: Integer;
begin
  X := 41;
  LocalOfInlined(X);
  Check(GSeen = 41, 'a temp of the outer inline as var and const', GSeen, 41);
  Check(GSeen2 = 42, 'a temp of the outer inline, the var', GSeen2, 42);
end;

{ The same forms over strings: the temp of a string is a cell of the frame,
  so an actual only the caller reaches goes in directly at every level and
  the forms above hold the exceptions to that at -O2 and -O3 as well.  Each
  form keeps a second reference to the string (Keep): a const string is a
  pointer without a reference of its own, and with the count at one the
  real call's concatenation grows the block in place (the const parameter
  then reads the new text) or moves it (and the parameter reads a freed
  block) - the real call has no value to compare with.  With the second
  reference the concatenation makes a new string, the old one stays alive,
  and the real call passes the old text. }
procedure AppendAndSee(var A: string; const B: string); inline;
begin
  A := A + 'x';
  GText := B;
end;

procedure CheckText(const Actual, Expected, What: string);
begin
  If Actual <> Expected then
    raise Exception.CreateFmt('%s: %s, expected %s', [What, Actual, Expected]);
end;

procedure SameStringVarAndConst;
var
  S, Keep: string;
begin
  S := Copy('_abc', 2, 3);
  Keep := S;
  AppendAndSee(S, S);
  CheckText(GText, 'abc', 'one string as var and const');
  CheckText(S, 'abcx', 'one string as var and const, the var');
  CheckText(Keep, 'abc', 'one string as var and const, the kept reference');
end;

procedure AbsoluteStringTwin;
var
  S, Keep: string;
  T: string absolute S;
begin
  S := Copy('_abc', 2, 3);
  Keep := S;
  AppendAndSee(T, S);
  CheckText(GText, 'abc', 'absolute string twin as var');
  CheckText(S, 'abcx', 'absolute string twin as var, the var');
  CheckText(Keep, 'abc', 'absolute string twin as var, the kept reference');
end;

procedure TNamed.Append(const V: string);
begin
  Name := Name + 'x';
  GText := V;
end;

procedure RecordSelfString;
var
  R: TNamed;
  Keep: string;
begin
  R.Name := Copy('_abc', 2, 3);
  Keep := R.Name;
  R.Append(R.Name);
  CheckText(GText, 'abc', 'string field of the record Self');
  CheckText(R.Name, 'abcx', 'string field of the record Self, the field');
  CheckText(Keep, 'abc', 'string field of the record Self, the kept reference');
end;

procedure AppendThroughPointer(P: PString; const V: string); inline;
begin
  P^ := P^ + 'x';
  GText := V;
end;

procedure StringAddressTaken;
var
  S, Keep: string;
  P: PString;
begin
  S := Copy('_abc', 2, 3);
  Keep := S;
  P := @S;
  AppendThroughPointer(P, S);
  CheckText(GText, 'abc', 'a string whose address is held');
  CheckText(S, 'abcx', 'a string whose address is held, the string');
  CheckText(Keep, 'abc', 'a string whose address is held, the kept reference');
end;

procedure LocalStringOfInlined(const V: string); inline;
var
  L: string;
begin
  L := V;
  AppendAndSee(L, L);
  GText2 := L;
end;

procedure StringTempOfOuterInline;
var
  S: string;
begin
  S := Copy('_abc', 2, 3);
  LocalStringOfInlined(S);
  CheckText(GText, 'abc', 'a string temp of the outer inline as var and const');
  CheckText(GText2, 'abcx', 'a string temp of the outer inline, the var');
end;

begin
  try
    PureGlobalRead;
    CapturedAlias;
    CapturedScalar;
    SameLocalVarAndConst;
    AbsoluteTwin;
    RecordSelf;
    ResultIsActual;
    StringResultIsActual;
    AddressTaken;
    GlobalActual;
    TempOfOuterInline;
    SameStringVarAndConst;
    AbsoluteStringTwin;
    RecordSelfString;
    StringAddressTaken;
    StringTempOfOuterInline;
    WriteLn('INLINE_CONST_ALIAS_OK');
  except
    on E: Exception do begin
      WriteLn('INLINE_CONST_ALIAS_FAIL ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
