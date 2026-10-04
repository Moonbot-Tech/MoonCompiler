{ %CPU=x86_64 }
{ %OPT=-O3 }
program trangeprovenloop1;

{$mode delphiunicode}
{$R+}
{$Q-}

uses
  SysUtils;

type
  TStatic = array[-3..4] of LongInt;

procedure Fail(Code: LongInt);
begin
  Halt(Code);
end;

function DynamicUp(const A: TArray<LongInt>): Int64; noinline;
var
  I: NativeInt;
begin
  Result := 0;
  for I := 0 to High(A) do
    Result := Result + A[I];
end;

function DynamicDown(const A: TArray<LongInt>): Int64; noinline;
var
  I: NativeInt;
begin
  Result := 0;
  for I := High(A) downto 0 do
    Result := Result + A[I];
end;

function DynamicIdentityBound(const A: TArray<LongInt>): Int64; noinline;
var
  I: NativeInt;
begin
  Result := 0;
  for I := NativeInt(0) to NativeInt(High(A)) do
    Result := Result + A[I];
end;

function OpenUp(const A: array of LongInt): Int64; noinline;
var
  I: NativeInt;
begin
  Result := 0;
  for I := 0 to High(A) do
    Result := Result + A[I];
end;

function OpenDown(const A: array of LongInt): Int64; noinline;
var
  I: NativeInt;
begin
  Result := 0;
  for I := High(A) downto 0 do
    Result := Result + A[I];
end;

function StaticUp(const A: TStatic): Int64; noinline;
var
  I: NativeInt;
begin
  Result := 0;
  for I := Low(A) to High(A) do
    Result := Result + A[I];
end;

function StaticDown(const A: TStatic): Int64; noinline;
var
  I: NativeInt;
begin
  Result := 0;
  for I := High(A) downto Low(A) do
    Result := Result + A[I];
end;

function DynamicPastEnd(const A: TArray<LongInt>): Int64; noinline;
var
  I: NativeInt;
begin
  Result := 0;
  for I := 0 to High(A) + 1 do
    Result := Result + A[I];
end;

function OpenPastEnd(const A: array of LongInt): Int64; noinline;
var
  I: NativeInt;
begin
  Result := 0;
  for I := 0 to High(A) + 1 do
    Result := Result + A[I];
end;

function DynamicOffsetPastEnd(const A: TArray<LongInt>): Int64; noinline;
var
  I: NativeInt;
begin
  Result := 0;
  for I := 0 to High(A) do
    Result := Result + A[I + 1];
end;

function DynamicNarrowedIndex(const A: TArray<LongInt>): Int64; noinline;
var
  I: NativeInt;
begin
  Result := 0;
  for I := 0 to High(A) do
    Result := Result + A[Byte(I)];
end;

function DynamicNarrowedBound(const A: TArray<LongInt>): Int64; noinline;
var
  I: NativeInt;
begin
  Result := 0;
  for I := 0 to Byte(High(A)) do
    Result := Result + A[I];
end;

function DynamicNarrowedBoundDown(const A: TArray<LongInt>): Int64; noinline;
var
  I: NativeInt;
begin
  Result := 0;
  for I := Byte(High(A)) downto 0 do
    Result := Result + A[I];
end;

function OpenNarrowedBound(const A: array of LongInt): Int64; noinline;
var
  I: NativeInt;
begin
  Result := 0;
  for I := 0 to Byte(High(A)) do
    Result := Result + A[I];
end;

procedure Shrink(var A: TArray<LongInt>); noinline;
begin
  SetLength(A, 1);
end;

function MutableDescriptor(var A: TArray<LongInt>): Int64; noinline;
var
  I: NativeInt;
begin
  Result := 0;
  for I := 0 to High(A) do
  begin
    if I = 1 then
      Shrink(A);
    Result := Result + A[I];
  end;
end;

procedure ExpectRangeErrorDynamic(const A: TArray<LongInt>);
var
  Raised: Boolean;
begin
  Raised := False;
  try
    DynamicPastEnd(A);
  except
    on ERangeError do
      Raised := True;
  end;
  if not Raised then
    Fail(40);
end;

procedure ExpectRangeErrorOpen(const A: array of LongInt);
var
  Raised: Boolean;
begin
  Raised := False;
  try
    OpenPastEnd(A);
  except
    on ERangeError do
      Raised := True;
  end;
  if not Raised then
    Fail(41);
end;

procedure ExpectRangeErrorMutation;
var
  A: TArray<LongInt>;
  Raised: Boolean;
begin
  SetLength(A, 4);
  A[0] := 10;
  A[1] := 20;
  A[2] := 30;
  A[3] := 40;
  Raised := False;
  try
    MutableDescriptor(A);
  except
    on ERangeError do
      Raised := True;
  end;
  if not Raised then
    Fail(42);
end;

procedure ExpectRangeErrorOffset(const A: TArray<LongInt>);
var
  Raised: Boolean;
begin
  Raised := False;
  try
    DynamicOffsetPastEnd(A);
  except
    on ERangeError do
      Raised := True;
  end;
  if not Raised then
    Fail(43);
end;

procedure CheckNarrowedIndex;
var
  A: TArray<LongInt>;
  I: NativeInt;
  Expected: Int64;
begin
  SetLength(A, 300);
  for I := 0 to High(A) do
    A[I] := I * 3 + 1;
  Expected := 0;
  for I := 0 to High(A) do
    Expected := Expected + A[Byte(I)];
  if DynamicNarrowedIndex(A) <> Expected then
    Fail(44);
end;

procedure ExpectRangeErrorNarrowedBounds;
var
  A: TArray<LongInt>;
  Raised: Boolean;
begin
  Raised := False;
  try
    DynamicNarrowedBound(A);
  except
    on ERangeError do
      Raised := True;
  end;
  if not Raised then
    Fail(45);

  Raised := False;
  try
    DynamicNarrowedBoundDown(A);
  except
    on ERangeError do
      Raised := True;
  end;
  if not Raised then
    Fail(46);

  Raised := False;
  try
    OpenNarrowedBound(A);
  except
    on ERangeError do
      Raised := True;
  end;
  if not Raised then
    Fail(47);
end;

procedure RunSizes;
var
  A: TArray<LongInt>;
  S: TStatic;
  I, N: NativeInt;
  Expected: Int64;
begin
  for N := 0 to 17 do
  begin
    SetLength(A, N);
    Expected := 0;
    for I := 0 to High(A) do
    begin
      A[I] := I * 7 - 13;
      Expected := Expected + A[I];
    end;
    if DynamicUp(A) <> Expected then
      Fail(10);
    if DynamicDown(A) <> Expected then
      Fail(11);
    if DynamicIdentityBound(A) <> Expected then
      Fail(14);
    if OpenUp(A) <> Expected then
      Fail(12);
    if OpenDown(A) <> Expected then
      Fail(13);
  end;

  Expected := 0;
  for I := Low(S) to High(S) do
  begin
    S[I] := I * 11 + 5;
    Expected := Expected + S[I];
  end;
  if StaticUp(S) <> Expected then
    Fail(20);
  if StaticDown(S) <> Expected then
    Fail(21);
end;

var
  A: TArray<LongInt>;

begin
  RunSizes;
  SetLength(A, 3);
  A[0] := 1;
  A[1] := 2;
  A[2] := 3;
  ExpectRangeErrorDynamic(A);
  ExpectRangeErrorOpen(A);
  ExpectRangeErrorMutation;
  ExpectRangeErrorOffset(A);
  CheckNarrowedIndex;
  ExpectRangeErrorNarrowedBounds;
  WriteLn('RANGE-PROVEN-LOOP:PASS');
end.
