program value_in_register;

{ A value the program has just put into a register, or has in a register
  anyway, is not read back from memory:
  - StoreReload, StoreOther: an element written from a register and the
    element of the inlined update behind it (Pulse loops/aliased-update and
    loops/nonaliased-update): a 32-bit index whose upper half is already
    clear is not extended once more between the write and the read;
  - StoreThenAdd: the element written is an operand of the arithmetic of the
    next statement;
  - ContainsMiss: a global object is read for the call and for its table of
    methods, with the argument loaded in between (Pulse
    hot-rtl/list-int-contains-miss);
  - CleanName: a string parameter and two constants go through the inlined
    StringReplace wrappers into the call of the worker (Pulse
    product-forms/market-by-int-name);
  - CheckAll: the inlined assertion of TSynTestCase tests its constant
    empty message before it logs;
  - KidAt (fcl-pdf's TPDFDocument.GetPageNode): a local in the frame
    (absolute) is stored and compared with nil twice, the second time
    behind the conditional jump of the first - both compares read the
    register, and the second goes;
  - ToByte (the VariantTo* of varutils): the inlined VariantTypeMismatch
    reads neither of its two parameters - the constant keeps its move, and
    the dead read of the other one under it goes;
  - FlipSheet (fcl-report's TFPReportExportPDF.DoExecute): a real constant
    for a field of the record Self is read once in front of the inlined
    body, and the address of the field folds into the store.
  The program prints VALUE_IN_REGISTER_PASS when every value is the one of
  the text; run_value_in_register_gate.py counts the routines in the -O3
  object. }

{$ifdef FPC}
  {$mode delphi}{$H+}
{$endif}
{$APPTYPE CONSOLE}
{$Q-}{$R-}

uses
  SysUtils;

const
  Count = 1024;
  Inner = 64;

type
  TBox = class
    Items: array[0..7] of Integer;
    function IndexOf(Value: Integer): Integer; virtual;
    function Contains(const Value: Integer): Boolean; inline;
  end;

  { the assertion of mormot.core.test's TSynTestCase }
  TChecker = class
    Checks, Failed: Integer;
    Log: Boolean;
    procedure Note(Cond: Boolean; const Msg: string);
    procedure Fail(const Msg: string);
    procedure Check(Cond: Boolean; const Msg: string); inline;
  end;

  TKids = class
    Items: array[0..7] of Integer;
    function Find(Index: Integer): TObject; virtual;
  end;

  TVarLike = record
    VType: Word;
    Value: Int64;
  end;

  TMatrix = record
    M00, M01, M10, M11, M20, M21: Single;
    procedure SetYScale(const AValue: Single); inline;
  end;

  TSheet = class
    Width, Height: Integer;
    Matrix: TMatrix;
    procedure SetOrientation(Landscape: Boolean); virtual;
  end;

var
  IntA, IntB, IntC: array[0..Count - 1] of Int32;
  Box: TBox;
  Notes: Integer;
  Failures: Integer;
  Checker: TChecker;
  Kids: TKids;

procedure AliasUpdate(var Destination: Int32; const Source: Int32); inline;
begin
  Destination := Destination + Source * 3 + 1;
end;

function StoreReload(Iterations: Integer): UInt64;
var
  I, J, Index: Integer;
begin
  for I := 1 to Iterations do
    for J := 0 to Inner - 1 do
    begin
      Index := (I + J) and (Count - 1);
      IntC[Index] := IntA[Index];
      AliasUpdate(IntC[Index], IntC[Index]);
    end;
  Result := UInt32(IntC[(Iterations + 7) and (Count - 1)]);
end;

function StoreOther(Iterations: Integer): UInt64;
var
  I, J, Index: Integer;
begin
  for I := 1 to Iterations do
    for J := 0 to Inner - 1 do
    begin
      Index := (I + J) and (Count - 1);
      IntC[Index] := 0;
      AliasUpdate(IntC[Index], IntB[Index]);
    end;
  Result := UInt32(IntC[(Iterations + 7) and (Count - 1)]);
end;

function StoreThenAdd(Iterations: Integer): UInt64;
var
  I, J, Index: Integer;
  S: Int32;
begin
  for I := 1 to Iterations do
    for J := 0 to Inner - 1 do
    begin
      Index := (I + J) and (Count - 1);
      IntC[Index] := IntA[Index];
      S := IntC[Index];
      IntC[Index] := IntC[Index] + S * 3 + 1;
    end;
  Result := UInt32(IntC[(Iterations + 7) and (Count - 1)]);
end;

function TBox.IndexOf(Value: Integer): Integer;
var
  I: Integer;
begin
  for I := Low(Items) to High(Items) do
    If Items[I] = Value then
      Exit(I);
  Result := -1;
end;

function TBox.Contains(const Value: Integer): Boolean;
begin
  Result := IndexOf(Value) >= 0;
end;

function ContainsMiss(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    If not Box.Contains(-7) then
      Inc(Result);
end;

function CleanName(Name: string): string;
begin
  Name := StringReplace(Name, '_', '', []);
  Result := Name;
end;

procedure TChecker.Note(Cond: Boolean; const Msg: string);
begin
  Inc(Notes, Length(Msg) + Ord(Cond));
end;

procedure TChecker.Fail(const Msg: string);
begin
  Inc(Failed, Length(Msg) + 1);
end;

procedure TChecker.Check(Cond: Boolean; const Msg: string);
begin
  Inc(Checks);
  If (Msg <> '') and Log then
    Note(Cond, Msg);
  If not Cond then
    Fail(Msg);
end;

function CheckAll(Checker: TChecker; Iterations: Integer): Integer;
var
  I: Integer;
begin
  for I := 1 to Iterations do
    Checker.Check(IntA[I and (Count - 1)] > -1000, '');
  Result := Checker.Checks;
end;

function TKids.Find(Index: Integer): TObject;
begin
  If Index >= 0 then
    Result := Self
  else
    Result := nil;
end;

function KidAt(Index: Integer): Integer;
var
  Value: TObject;
  Found: TKids absolute Value;
  Idx: Integer;
begin
  Result := -1;
  Value := Kids.Find(Index);
  Idx := Index * 3;
  If Assigned(Value) and (Value is TKids) and (Idx < Length(Found.Items)) then
    Result := Found.Items[Idx];
end;

procedure TypeMismatch(const SourceType, DestType: Word); inline;
begin
  raise EConvertError.Create('type mismatch');
end;

function ToByte(const V: TVarLike): Byte;
begin
  case V.VType of
    1: Result := Byte(V.Value);
    2: Result := Byte(V.Value shr 8);
    3: Result := Byte(V.Value shr 16);
  else
    begin
      TypeMismatch(V.VType, 17);
      Result := 0;
    end;
  end;
end;

procedure TMatrix.SetYScale(const AValue: Single);
begin
  M11 := AValue;
end;

procedure TSheet.SetOrientation(Landscape: Boolean);
begin
  If Landscape then
    Width := Height;
end;

function FlipSheet(S: TSheet; Landscape: Boolean): Single;
begin
  S.SetOrientation(Landscape);
  S.Matrix.SetYScale(-1);
  S.Matrix.M21 := S.Height;
  Result := S.Matrix.M11 + S.Matrix.M21;
end;

procedure Expect(const What: string; Actual, Expected: UInt64);
begin
  If Actual <> Expected then
  begin
    Writeln(What, ' = ', Actual, ', expected ', Expected);
    Inc(Failures);
  end;
end;

procedure ExpectText(const What, Actual, Expected: string);
begin
  If Actual <> Expected then
  begin
    Writeln(What, ' = ', Actual, ', expected ', Expected);
    Inc(Failures);
  end;
end;

var
  K: Integer;
  V: TVarLike;
  Sheet: TSheet;
begin
  for K := 0 to Count - 1 do
  begin
    IntA[K] := K * 7 - 300;
    IntB[K] := K xor 5;
  end;
  Box := TBox.Create;
  for K := 0 to High(Box.Items) do
    Box.Items[K] := K * 3;
  Expect('StoreReload', StoreReload(500), 12997);
  Expect('StoreOther', StoreOther(500), 1531);
  Expect('StoreThenAdd', StoreThenAdd(500), 12997);
  Expect('ContainsMiss', ContainsMiss(500), 500);
  ExpectText('CleanName', CleanName(Copy('_BTC_USDT', 1, 9)), 'BTC_USDT');
  Checker := TChecker.Create;
  Checker.Log := True;
  Expect('CheckAll', CheckAll(Checker, 500), 500);
  Expect('Notes', Notes, 0);
  Expect('Failed', Checker.Failed, 0);
  Checker.Free;
  Kids := TKids.Create;
  Kids.Items[3] := 30;
  Expect('KidAt', KidAt(1), 30);
  Expect('KidAt nil', UInt64(Int64(KidAt(-1))), UInt64(Int64(-1)));
  Kids.Free;
  V.VType := 2;
  V.Value := $1234;
  Expect('ToByte', ToByte(V), $12);
  V.VType := 9;
  try
    ToByte(V);
    Expect('ToByte of an unknown type', 0, 1);
  except
    on EConvertError do ;
  end;
  Sheet := TSheet.Create;
  Sheet.Height := 100;
  Expect('FlipSheet', Round(FlipSheet(Sheet, True) * 10), 990);
  Expect('FlipSheet width', Sheet.Width, 100);
  Sheet.Free;
  Box.Free;
  If Failures = 0 then
    Writeln('VALUE_IN_REGISTER_PASS')
  else
    Halt(1);
end.
