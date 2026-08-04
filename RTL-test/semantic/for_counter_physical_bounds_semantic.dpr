program for_counter_physical_bounds_semantic;

{ A for loop whose constant bound sits on the physical maximum of the
  counter storage must still terminate.

  The red form (audit 9238ecbe interaction): under $R- the frontend accepts
  enum/subrange bounds beyond the declared range, but the at-end loop shape
  (body; succ; until counter > to) still incremented past the last value:
  a byte counter wrapped 255 -> 0 and "0 > 255" never fired, so
  for e := TEnum(254) to TEnum(255) looped forever (Delphi: two passes).
  The at-end shape is now refused when the bound reaches the physical
  storage domain, falling back to the pre-increment shape that never steps
  past the bound.  The for..step extension had the same wrap in its
  increment and now breaks when the counter moves against the direction. }

{$mode delphiunicode}{$H+}
{$modeswitch forstep}
{$Q-}{$R-}

uses
  mormot.core.fpcx64mm,
  SysUtils;

type
  TSmallEnum = (seA, seB, seC);
  TWordEnum = (weFar = 65500);
  TSignedSub = -5..5;

var
  Fails: Integer = 0;

procedure Check(const Name: string; Got, Want: Int64);
begin
  if Got <> Want then
  begin
    WriteLn('FAIL ', Name, ' got=', Got, ' want=', Want);
    Inc(Fails);
  end;
end;

procedure ByteEnumTop;
var
  e: TSmallEnum;
  n, sum: Integer;
begin
  n := 0;
  sum := 0;
  for e := TSmallEnum(254) to TSmallEnum(255) do
  begin
    Inc(n);
    Inc(sum, Ord(e));
    if n > 10 then
      Break;
  end;
  Check('byte-enum-top-iters', n, 2);
  Check('byte-enum-top-sum', sum, 509);
end;

procedure WordEnumTop;
var
  e: TWordEnum;
  n: Integer;
begin
  n := 0;
  for e := TWordEnum(65534) to TWordEnum(65535) do
  begin
    Inc(n);
    if n > 10 then
      Break;
  end;
  Check('word-enum-top-iters', n, 2);
end;

procedure SignedSubTop;
var
  s: TSignedSub;
  n, sum: Integer;
begin
  n := 0;
  sum := 0;
  for s := TSignedSub(125) to TSignedSub(127) do
  begin
    Inc(n);
    Inc(sum, Ord(s));
    if n > 10 then
      Break;
  end;
  Check('signed-sub-top-iters', n, 3);
  Check('signed-sub-top-sum', sum, 125 + 126 + 127);
end;

procedure ByteEnumDowntoBottom;
var
  e: TSmallEnum;
  n: Integer;
begin
  n := 0;
  for e := TSmallEnum(1) downto TSmallEnum(0) do
  begin
    Inc(n);
    if n > 10 then
      Break;
  end;
  Check('byte-enum-downto-bottom', n, 2);
end;

procedure DeclaredRangeControls;
var
  e: TSmallEnum;
  b: Byte;
  n: Integer;
begin
  n := 0;
  for e := seA to seC do
    Inc(n);
  Check('declared-enum', n, 3);
  n := 0;
  for b := 0 to 255 do
    Inc(n);
  Check('full-byte', n, 256);
  n := 0;
  for e := TSmallEnum(200) to TSmallEnum(100) do
    Inc(n);
  Check('empty-loop', n, 0);
end;

{ the reverted-loop shapes: counter unused in the body, iteration count
  wider than the counter type (red through OptimizeForLoop at O3) }
procedure RevertedCountShapes;
var
  s: ShortInt;
  w: Word;
  q: UInt64;
  UpToW: Word;
  n: Integer;
begin
  n := 0;
  for s := -100 to 100 do
    Inc(n);
  Check('signed-count-wide', n, 201);
  n := 0;
  for w := 0 to 65535 do
    Inc(n);
  Check('full-word', n, 65536);
  UpToW := 3;
  n := 0;
  for w := 5 to UpToW do
    Inc(n);
  Check('runtime-empty', n, 0);
  UpToW := 1000;
  n := 0;
  for w := 1 to UpToW do
    Inc(n);
  Check('runtime-one-to-n', n, 1000);
  n := 0;
  for q := High(UInt64) - 1 to High(UInt64) do
    Inc(n);
  Check('qword-top', n, 2);
end;

procedure StepWrapTop;
var
  b: Byte;
  n: Integer;
begin
  n := 0;
  for b := 250 to 255 step 2 do
  begin
    Inc(n);
    if n > 10 then
      Break;
  end;
  Check('step-wrap-top', n, 3);
  n := 0;
  for b := 250 to 254 step 2 do
    Inc(n);
  Check('step-exact-fit', n, 3);
  n := 0;
  for b := 5 downto 0 step 2 do
  begin
    Inc(n);
    if n > 10 then
      Break;
  end;
  Check('step-downto-bottom', n, 3);
  n := 0;
  for b := 200 to 100 step 2 do
    Inc(n);
  Check('step-empty', n, 0);
end;

begin
  ByteEnumTop;
  WordEnumTop;
  SignedSubTop;
  ByteEnumDowntoBottom;
  DeclaredRangeControls;
  RevertedCountShapes;
  StepWrapTop;
  if Fails <> 0 then
    Halt(1);
  WriteLn('FOR_PHYSBOUND_SEMANTIC_OK');
end.
