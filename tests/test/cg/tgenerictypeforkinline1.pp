{ %OPT=-O3 -Sen }

program tgenerictypeforkinline1;

{ A generic routine forks on its type argument: GetTypeKind, IsManagedType, in
  case and in if, alone and joined with a run-time operand.  Each
  specialization keeps one short branch, but all branches together exceed the
  inline budget of the deepest nesting level.  The decision to inline has to
  be taken on the body of the specialization, so every Eq below is inlined
  into its Use* caller for every type argument.  -Sen turns the note "not
  inlined" into a compile error; the Win64 repair gate reads the Use* bodies. }

{$mode delphi}

type
  TByteArray = array of Byte;

  TFork<T> = class
    Tag: Integer;
    { forks of the kind of T, the shape of the flat TDictionary comparer }
    function EqCase(const L, R: T): Boolean; inline;
    { the same fork written as an if chain, with a run-time operand after the
      type test }
    function EqIf(const L, R: T): Boolean; inline;
    { the managedness of T }
    function EqManaged(const L, R: T): Boolean; inline;
    function Case3(const L, R: T): Boolean; inline;
    function Case2(const L, R: T): Boolean; inline;
    function Case1(const L, R: T): Boolean; inline;
    function If3(const L, R: T): Boolean; inline;
    function If2(const L, R: T): Boolean; inline;
    function If1(const L, R: T): Boolean; inline;
    function Managed3(const L, R: T): Boolean; inline;
    function Managed2(const L, R: T): Boolean; inline;
    function Managed1(const L, R: T): Boolean; inline;
  end;

function TFork<T>.EqCase(const L, R: T): Boolean;
begin
  case GetTypeKind(T) of
    tkUString:
      Result := PUnicodeString(@L)^ = PUnicodeString(@R)^;
    tkAString:
      Result := PAnsiString(@L)^ = PAnsiString(@R)^;
    tkFloat:
      Result := PDouble(@L)^ = PDouble(@R)^;
    tkClass:
      Result := (PPointer(@L)^ = PPointer(@R)^) or
        ((PPointer(@L)^ <> nil) and (PPointer(@R)^ <> nil) and
         TObject(PPointer(@L)^).Equals(TObject(PPointer(@R)^)));
    tkInt64, tkQWord:
      Result := PQWord(@L)^ = PQWord(@R)^;
  else
    case SizeOf(T) of
      1: Result := PByte(@L)^ = PByte(@R)^;
      2: Result := PWord(@L)^ = PWord(@R)^;
      4: Result := PCardinal(@L)^ = PCardinal(@R)^;
      8: Result := PQWord(@L)^ = PQWord(@R)^;
    else
      Result := CompareByte(L, R, SizeOf(T)) = 0;
    end;
  end;
end;

function TFork<T>.EqIf(const L, R: T): Boolean;
begin
  if GetTypeKind(T) in [tkUString, tkAString] then
  begin
    if GetTypeKind(T) = tkUString then
      Result := PUnicodeString(@L)^ = PUnicodeString(@R)^
    else
      Result := PAnsiString(@L)^ = PAnsiString(@R)^;
  end
  else if GetTypeKind(T) = tkFloat then
    Result := PDouble(@L)^ = PDouble(@R)^
  else
  begin
    Result := CompareByte(L, R, SizeOf(T)) = 0;
    if (GetTypeKind(T) = tkClass) and not Result and (Tag <> 0) and
       (PPointer(@L)^ <> nil) and (PPointer(@R)^ <> nil) then
      Result := TObject(PPointer(@L)^).Equals(TObject(PPointer(@R)^));
  end;
end;

function TFork<T>.EqManaged(const L, R: T): Boolean;
begin
  if IsManagedType(T) then
  begin
    if GetTypeKind(T) = tkUString then
      Result := (Length(PUnicodeString(@L)^) = Length(PUnicodeString(@R)^)) and
        (PUnicodeString(@L)^ = PUnicodeString(@R)^)
    else if GetTypeKind(T) = tkAString then
      Result := (Length(PAnsiString(@L)^) = Length(PAnsiString(@R)^)) and
        (PAnsiString(@L)^ = PAnsiString(@R)^)
    else if GetTypeKind(T) = tkDynArray then
      Result := (PPointer(@L)^ = PPointer(@R)^) or
        ((Length(TByteArray(PPointer(@L)^)) = Length(TByteArray(PPointer(@R)^))) and
         (CompareByte(TByteArray(PPointer(@L)^)[0], TByteArray(PPointer(@R)^)[0],
            Length(TByteArray(PPointer(@L)^))) = 0))
    else
      Result := PPointer(@L)^ = PPointer(@R)^;
  end
  else
    Result := CompareByte(L, R, SizeOf(T)) = 0;
end;

{ three inline levels above each Eq: Eq is pasted at the deepest level }
function TFork<T>.Case3(const L, R: T): Boolean; begin Result := EqCase(L, R); end;
function TFork<T>.Case2(const L, R: T): Boolean; begin Result := Case3(L, R); end;
function TFork<T>.Case1(const L, R: T): Boolean; begin Result := Case2(L, R); end;
function TFork<T>.If3(const L, R: T): Boolean; begin Result := EqIf(L, R); end;
function TFork<T>.If2(const L, R: T): Boolean; begin Result := If3(L, R); end;
function TFork<T>.If1(const L, R: T): Boolean; begin Result := If2(L, R); end;
function TFork<T>.Managed3(const L, R: T): Boolean; begin Result := EqManaged(L, R); end;
function TFork<T>.Managed2(const L, R: T): Boolean; begin Result := Managed3(L, R); end;
function TFork<T>.Managed1(const L, R: T): Boolean; begin Result := Managed2(L, R); end;

type
  TKeyObject = class
    Id: Integer;
    constructor Create(AId: Integer);
    function Equals(Obj: TObject): Boolean; override;
  end;

constructor TKeyObject.Create(AId: Integer);
begin
  Id := AId;
end;

function TKeyObject.Equals(Obj: TObject): Boolean;
begin
  Result := (Obj is TKeyObject) and (TKeyObject(Obj).Id = Id);
end;

var
  FInt: TFork<Integer>;
  FQWord: TFork<QWord>;
  FStr: TFork<UnicodeString>;
  FAnsi: TFork<AnsiString>;
  FDouble: TFork<Double>;
  FObj: TFork<TObject>;
  Failures: Integer;

procedure Check(Ok: Boolean; Code: Integer);
begin
  if not Ok then
  begin
    WriteLn('failed ', Code);
    Inc(Failures);
  end;
end;

function UseInt(A, B: Integer): Integer; noinline;
begin
  Result := Ord(FInt.Case1(A, B)) + 2 * Ord(FInt.If1(A, B)) + 4 * Ord(FInt.Managed1(A, B));
end;

function UseQWord(A, B: QWord): Integer; noinline;
begin
  Result := Ord(FQWord.Case1(A, B)) + 2 * Ord(FQWord.If1(A, B)) + 4 * Ord(FQWord.Managed1(A, B));
end;

function UseStr(const A, B: UnicodeString): Integer; noinline;
begin
  Result := Ord(FStr.Case1(A, B)) + 2 * Ord(FStr.If1(A, B)) + 4 * Ord(FStr.Managed1(A, B));
end;

function UseAnsi(const A, B: AnsiString): Integer; noinline;
begin
  Result := Ord(FAnsi.Case1(A, B)) + 2 * Ord(FAnsi.If1(A, B)) + 4 * Ord(FAnsi.Managed1(A, B));
end;

function UseDouble(A, B: Double): Integer; noinline;
begin
  Result := Ord(FDouble.Case1(A, B)) + 2 * Ord(FDouble.If1(A, B)) + 4 * Ord(FDouble.Managed1(A, B));
end;

function UseObj(A, B: TObject): Integer; noinline;
begin
  Result := Ord(FObj.Case1(A, B)) + 2 * Ord(FObj.If1(A, B)) + 4 * Ord(FObj.Managed1(A, B));
end;

var
  O1, O2, O3: TKeyObject;
  S1, S2: UnicodeString;
  A1, A2: AnsiString;
begin
  Failures := 0;
  FInt := TFork<Integer>.Create;
  FQWord := TFork<QWord>.Create;
  FStr := TFork<UnicodeString>.Create;
  FAnsi := TFork<AnsiString>.Create;
  FDouble := TFork<Double>.Create;
  FObj := TFork<TObject>.Create;
  FObj.Tag := 1;

  Check(UseInt(7, 7) = 7, 1);
  Check(UseInt(7, 8) = 0, 2);
  Check(UseQWord(QWord($8000000000000001), QWord($8000000000000001)) = 7, 3);
  Check(UseQWord(QWord($8000000000000001), 1) = 0, 4);

  S1 := 'key';
  S2 := 'ke';
  S2 := S2 + 'y';
  Check(UseStr(S1, S2) = 7, 5);
  Check(UseStr(S1, 'kez') = 0, 6);
  A1 := 'abc';
  A2 := 'ab';
  A2 := A2 + 'c';
  Check(UseAnsi(A1, A2) = 7, 7);
  Check(UseAnsi(A1, 'abd') = 0, 8);

  Check(UseDouble(1.5, 1.5) = 7, 9);
  Check(UseDouble(1.5, 2.5) = 0, 10);

  O1 := TKeyObject.Create(5);
  O2 := TKeyObject.Create(5);
  O3 := TKeyObject.Create(6);
  { EqCase and EqIf ask Equals; EqManaged compares the references }
  Check(UseObj(O1, O2) = 3, 11);
  Check(UseObj(O1, O1) = 7, 12);
  Check(UseObj(O1, O3) = 0, 13);

  O1.Free;
  O2.Free;
  O3.Free;
  FInt.Free;
  FQWord.Free;
  FStr.Free;
  FAnsi.Free;
  FDouble.Free;
  FObj.Free;
  if Failures <> 0 then
    Halt(1);
  WriteLn('ok');
end.
