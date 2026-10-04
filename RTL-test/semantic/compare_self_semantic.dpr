program compare_self_semantic;

{ "cmp %reg,%reg" reads nothing: its flags do not depend on the value.  The
  x86 peephole (RegLoadedWithNewValue) took every instruction of that kind
  with two equal registers for one which loads the register with a new
  value, as "xor %reg,%reg" does - and "cmp" writes nothing.  The register
  counted as dead in front of the comparison, and the load of the value into
  it was given to another register:

    Z := P^;  Y := Z;          movq  (%rcx),%rdx
    if Z < Z then ...     ->   cmpq  %rax,%rax        %rax was never loaded
    else Z := Z - 1;           subq  $1,%rax

  A comparison of a value with itself is what is left of a comparison of two
  values which turned out to be one: Max(A, A) after inlining, a bound
  compared with itself.  -O1 and -O3 were correct, -O2 was not.

  The values are those of Delphi 12.2 and of -O1. }

{$mode delphi}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  cwstring,
  {$endif UNIX}
  SysUtils;

var
  Fails: Integer = 0;
  Cell: Int64;
  M: array[0..7] of Int64;

procedure Check(Got, Want: Int64; const Name: string);
begin
  if Got <> Want then
  begin
    WriteLn('FAIL ', Name, ': ', Got, ' <> ', Want);
    Inc(Fails);
  end;
end;

function Less(P: PInt64): Int64; noinline;
var
  Y, Z: Int64;
begin
  Z := P^;
  Y := Z;
  if Z < Z then
    Z := Z + 1
  else
    Z := Z - 1;
  Result := Z + Y * 1000;
end;

function LessOrEqual(P: PInt64): Int64; noinline;
var
  Y, Z: Int64;
begin
  Z := P^;
  Y := Z;
  if Z <= Z then
    Z := Z + 1
  else
    Z := Z - 1;
  Result := Z + Y * 1000;
end;

function Differs(P: PInt64): Int64; noinline;
var
  Y, Z: Int64;
begin
  Z := P^;
  Y := Z;
  if Z <> Z then
    Z := Z + 1
  else
    Z := Z - 1;
  Result := Z + Y * 1000;
end;

function Less32(P: PInteger): Integer; noinline;
var
  Y, Z: Integer;
begin
  Z := P^;
  Y := Z;
  if Z < Z then
    Z := Z + 1
  else
    Z := Z - 1;
  Result := Z + Y * 1000;
end;

function Larger(A, B: Int64): Int64; inline;
begin
  if A > B then
    Result := A
  else
    Result := B;
end;

function LargerOfOne(P: PInt64): Int64; noinline;
var
  Y, Z: Int64;
begin
  Z := P^;
  Y := Z;
  Z := Larger(Z, Z) - 1;
  Result := Z + Y * 1000;
end;

function Longer(P: PInt64; K: Int64): Int64; noinline;
var
  X, Y, Z: Int64;
begin
  Z := P^;
  Y := Z;
  if Z < Z then
    Z := Z + 1
  else
    Z := Z - 1;
  Cell := Cell + 100;
  X := Z + Y;
  K := 5;
  Result := Z + Y * 1000 + X * 1000000 + K + M[1];
end;

{ two names of one value: the comparison reads both registers }
function TwoNames(P: PInt64): Int64; noinline;
var
  Y, Z: Int64;
begin
  Z := P^;
  Y := Z;
  if Z < Y then
    Z := Z + 1
  else
    Z := Z - 1;
  Result := Z + Y * 1000;
end;

var
  N: Integer;
begin
  M[1] := 149;
  M[3] := 163;
  Cell := 107;
  N := 163;
  Check(Less(@M[3]), 163162, 'a value is less than itself');
  Check(LessOrEqual(@M[3]), 163164, 'a value is less than itself or equal');
  Check(Differs(@M[3]), 163162, 'a value differs from itself');
  Check(Less32(@N), 163162, 'a 32-bit value is less than itself');
  Check(LargerOfOne(@M[3]), 163162, 'the larger of a value and itself');
  Check(Longer(@M[3], 9), 325163316, 'the routine of the generator');
  Check(Cell, 207, 'the routine of the generator, the cell');
  Check(TwoNames(@M[3]), 163162, 'a value is less than its copy');

  if Fails = 0 then
    WriteLn('COMPARE_SELF_PASS')
  else
  begin
    WriteLn('COMPARE_SELF_FAIL ', Fails);
    Halt(1);
  end;
end.
