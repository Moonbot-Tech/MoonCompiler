program add_load_semantic;

{ "add %reg2,%reg1" followed by a load through %reg1 becomes one load with
  both registers in its address (OptPass2ADD, "AddMov2Mov").  At -O3 the load
  need not follow the addition; when %reg2 changes in between, the load was
  moved up to the addition - past instructions which read or write the
  register the load writes:

    Inc(P, X);        add  %rdx,%rdi          mov  (%rdi,%rdx),%rdx
    Inc(X, 1);        add  $1,%rdx       ->   add  $1,%rdx
    X := PInt64(P)^;  mov  (%rdi),%rdx

  The increment of the value about to be replaced came after the load and
  was added to the value loaded.  Found by the generator of the memory-order
  gate once the forwarding of a memory value (ForwardMemoryValue) turned
  "add (%rdi),%rdi" into "add %rdx,%rdi".  DeadStep gives 701 at -O3 and -O4
  on main e3017da29 (Win64 and Linux) and on the release ccaa5fbaf (Linux);
  the other forms keep a register the load does not write today and stay as
  guards.

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
  Buf: array[0..7] of Int64;

procedure Check(Got, Want: Int64; const Name: string);
begin
  if Got <> Want then
  begin
    WriteLn('FAIL ', Name, ': ', Got, ' <> ', Want);
    Inc(Fails);
  end;
end;

{ the step is dead: the load replaces it }
function DeadStep(P: PByte): Int64; noinline;
var
  X: Int64;
begin
  X := PInt64(P)^;
  Inc(P, X);
  Inc(X, 1);
  X := PInt64(P)^;
  Result := X;
end;

{ the old value is read before the load replaces it }
function ReadBefore(P: PByte): Int64; noinline;
var
  X, Y: Int64;
begin
  X := PInt64(P)^;
  Inc(P, X);
  Y := X * 3;
  X := PInt64(P)^;
  Result := X + Y;
end;

{ the same with the length an argument }
function StepArgument(P: PByte; X: Int64): Int64; noinline;
begin
  Inc(P, X);
  Inc(X, 2);
  X := PInt64(P)^;
  Result := X;
end;

{ a 32-bit length, a load which extends }
function DeadStep32(P: PByte): Int64; noinline;
var
  X: Integer;
begin
  X := PInteger(P)^;
  Inc(P, X);
  Inc(X, 1);
  X := PInteger(P)^;
  Result := X;
end;

begin
  Buf[0] := 16; Buf[1] := 5; Buf[2] := 700; Buf[3] := 0;
  Check(DeadStep(@Buf[0]), 700, 'a step of the length about to be replaced');
  Check(ReadBefore(@Buf[0]), 748, 'the length read before it is replaced');
  Check(StepArgument(@Buf[0], 8), 5, 'the length an argument');
  Buf[0] := 8; Buf[1] := -3;
  Check(DeadStep32(@Buf[0]), -3, 'a 32-bit length');

  if Fails = 0 then
    WriteLn('ADD_LOAD_PASS')
  else
  begin
    WriteLn('ADD_LOAD_FAIL ', Fails);
    Halt(1);
  end;
end.
