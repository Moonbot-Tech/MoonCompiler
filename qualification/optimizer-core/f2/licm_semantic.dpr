program licm_semantic;

{$mode unleashed}
{$Q-}
{$R-}

uses
  SysUtils;

var
  GlobalScale: Int64;
threadvar
  ThreadScale: Int64;

procedure Check(Condition: Boolean; const Name: string);
begin
  If not Condition then begin
    WriteLn('FAIL:', Name);
    Halt(1);
  end;
end;

function HoistProbe(Scale: Int64; N: Integer): Int64; noinline;
var
  I: Integer;
begin
  Result := 0;
  I := 0;
  while I < N do begin
    Result := Result + Scale * 257 + I;
    Inc(I);
  end;
end;

function MutatedLocal(Scale: Int64; N: Integer): Int64; noinline;
var
  I: Integer;
begin
  Result := 0;
  I := 0;
  while I < N do begin
    Result := Result + Scale * 257;
    Inc(Scale);
    Inc(I);
  end;
end;

procedure Touch(var Value: Int64); noinline;
begin
  Inc(Value);
end;

function CallClobber(Scale: Int64; N: Integer): Int64; noinline;
var
  I: Integer;
begin
  Result := 0;
  I := 0;
  while I < N do begin
    Result := Result + Scale * 257;
    Touch(Scale);
    Inc(I);
  end;
end;

function GlobalClobber(N: Integer): Int64; noinline;
var
  I: Integer;
begin
  Result := 0;
  I := 0;
  while I < N do begin
    Result := Result + GlobalScale * 257;
    Inc(GlobalScale);
    Inc(I);
  end;
end;

function ThreadClobber(N: Integer): Int64; noinline;
var
  I: Integer;
begin
  Result := 0;
  I := 0;
  while I < N do begin
    Result := Result + ThreadScale * 257;
    Inc(ThreadScale);
    Inc(I);
  end;
end;

function PointerClobber(P: PInt64; N: Integer): Int64; noinline;
var
  I: Integer;
begin
  Result := 0;
  I := 0;
  while I < N do begin
    Result := Result + P^ * 257;
    Inc(P^);
    Inc(I);
  end;
end;

{$push}
{$Q+}
function CheckedZero(Enter: Boolean; Value: Int64): Int64; noinline;
begin
  Result := 7;
  while Enter do begin
    Result := Result + Value * 2;
    Enter := False;
  end;
end;
{$pop}

function DivZero(Enter: Boolean; Value, Divisor: Int64): Int64; noinline;
begin
  Result := 9;
  while Enter do begin
    Result := Result + Value div Divisor;
    Enter := False;
  end;
end;

function NestedProbe(Scale: Int64; OuterN, InnerN: Integer): Int64; noinline;
var
  A, I: Integer;
begin
  Result := 0;
  A := 0;
  while A < OuterN do begin
    I := 0;
    while I < InnerN do begin
      Result := Result + Scale * 257 + A * 16 + I;
      Inc(I);
    end;
    Inc(A);
  end;
end;

function StepLatch(Start_, Limit_, Step_, Scale: Integer): Int64; noinline;
var
  I: Integer;
begin
  Result := 0;
  for I := Start_ to Limit_ step Step_ do
    Result := Result + I * Scale;
end;

function BreakContinue(Scale: Int64): Int64; noinline;
var
  I: Integer;
begin
  Result := 0;
  I := -1;
  while I < 20 do begin
    Inc(I);
    If Odd(I) then
      Continue;
    If I = 12 then
      Break;
    Result := Result + Scale * 257;
  end;
end;

function ManagedFuncret(Scale: Integer): UnicodeString; noinline;
var
  I: Integer;
begin
  Result := '';
  I := 0;
  while I < 8 do begin
    Result := Result + Chr(65 + ((Scale * 257 + I) and 15));
    Inc(I);
  end;
end;

function ManagedFetchInLoop: Integer; noinline;
var
  Parts: array of UnicodeString;
  Item: UnicodeString;
  I: Integer;

  function Fetch(Index: Integer): UnicodeString; noinline;
  begin
    Result := Parts[Index];
  end;

begin
  SetLength(Parts, 4);
  Parts[0] := 'a';
  Parts[1] := 'bb';
  Parts[2] := 'ccc';
  Parts[3] := 'dddd';
  Result := 0;
  for I := 0 to 3 do begin
    Item := Fetch(I);
    Inc(Result, Length(Item) * 10);
  end;
end;

function GrowingLength: Integer; noinline;
var
  Values: array of Integer;
  I: Integer;
begin
  SetLength(Values, 4);
  for I := 0 to High(Values) do
    Values[I] := I + 1;
  Result := 0;
  I := 0;
  while I < Length(Values) do begin
    Result := Result + Values[I] * 2;
    If (I = 1) and (Length(Values) = 4) then
      SetLength(Values, 6);
    If I >= 4 then
      Values[I] := 100;
    Inc(I);
  end;
end;

function RealExcluded(Scale: Double; N: Integer): Double; noinline;
var
  I: Integer;
begin
  Result := 0;
  I := 0;
  while I < N do begin
    Result := Result + Scale * 257.0;
    Inc(I);
  end;
end;

function LabelBarrier(Scale: Int64; N: Integer): Int64; noinline;
label
  Done;
var
  I: Integer;
begin
  Result := 0;
  I := 0;
  while I < N do begin
    Result := Result + Scale * 257;
    If I = 100 then
      goto Done;
    Inc(I);
  end;
Done:
end;

var
  X: Int64;
  S: UnicodeString;
begin
  Check(HoistProbe(7, 1000) = 7 * 257 * 1000 + 999 * 1000 div 2,
    'positive');
  Check(MutatedLocal(3, 4) = 18 * 257, 'mutated-local');
  Check(CallClobber(3, 4) = 18 * 257, 'call-clobber');

  GlobalScale := 2;
  Check(GlobalClobber(4) = 14 * 257, 'global');
  ThreadScale := 2;
  Check(ThreadClobber(4) = 14 * 257, 'threadvar');
  X := 2;
  Check(PointerClobber(@X, 3) = 9 * 257, 'pointer');

  try
    Check(CheckedZero(False, High(Int64)) = 7, 'checked-zero-trip');
  except
    Check(False, 'checked-zero-trip-exception');
  end;
  try
    Check(DivZero(False, 1, 0) = 9, 'div-zero-trip');
  except
    Check(False, 'div-zero-trip-exception');
  end;

  Check(NestedProbe(3, 4, 8) = 25552, 'nested');
  Check(StepLatch(1, 9, 2, 3) = 75, 'step-latch');
  Check(BreakContinue(2) = 3084, 'break-continue');
  S := ManagedFuncret(3);
  Check(Length(S) = 8, 'managed-funcret');
  Check(ManagedFetchInLoop = 100, 'managed-fetch');
  Check(GrowingLength = 20, 'growing-length');
  Check(Abs(RealExcluded(1.5, 4) - 1542.0) < 0.0001, 'real-excluded');
  Check(LabelBarrier(2, 4) = 2056, 'label-barrier');
  WriteLn('F2-LICM:PASS');
end.
