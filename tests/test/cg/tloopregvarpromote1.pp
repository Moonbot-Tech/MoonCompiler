{ %CPU=x86_64 }
{ %OPT=-O3 }
program tloopregvarpromote1;

{ An integer value which the register allocator spills and which the
  outermost call-free loop accesses is loaded into a register of its own
  before that loop and stored after it (rgobj, loop regions marked by
  ncgflw).  The values must survive break, continue, nested loops, zero-trip
  entries, narrow widths and value parameters, used after the loop or dead
  there, a loop which ends the enclosing body, repeat-until-False and for-step
  loops; values the allocator keeps in registers keep them.  A value written
  only on the way out of the loop keeps its slot; one written on every
  iteration gets a register.  The expected digests come from an independent
  model; the assembler shape is checked by
  qualification/optimizer-core/loop-regvar. }

{$mode delphi}
{$modeswitch forstep}
{$pointermath on}
{$R-}{$Q-}
{$asmmode intel}

const
  OffsetBasis = UInt64($CBF29CE484222325);
  Prime = UInt64($00000100000001B3);
  RecordLengths: array[0..7] of Byte = (3, 0, 5, 1, 0, 7, 2, 4);

var
  Records: array[0..63] of Byte;

threadvar
  ThreadSum: Integer;

{ Clobber the registers which are volatile in both x86-64 ABIs.  Values that
  are genuinely live over an outer-loop backedge must survive this call. }
procedure ClobberVolatile; assembler; nostackframe;
asm
  PXOR XMM0,XMM0
  PXOR XMM1,XMM1
  PXOR XMM2,XMM2
  PXOR XMM3,XMM3
  PXOR XMM4,XMM4
  PXOR XMM5,XMM5
  XOR RAX,RAX
  XOR RCX,RCX
  XOR RDX,RDX
  XOR R8,R8
  XOR R9,R9
  XOR R10,R10
  XOR R11,R11
end;


procedure FillRecords;
var
  I, K, Pos: Integer;
begin
  Pos := 0;
  for I := 0 to High(RecordLengths) do
    begin
      Records[Pos] := RecordLengths[I];
      Inc(Pos);
      for K := 1 to RecordLengths[I] do
        begin
          Records[Pos] := Byte(Pos * 37 + 11);
          Inc(Pos);
        end;
    end;
end;


{ The request loop of the heartbeat: seven values and the record pointer
  stay live over the call of every iteration, more than the callee-saved
  registers of either ABI.  The hash and the payload pointer carried by the
  byte loop live over the whole routine as well, so they conflict with the
  most values and are spilled first; the byte loop keeps them in registers of
  its own.  As in the heartbeat, the byte loop is tested at its beginning
  against a bound read from the record, and an empty record enters it zero
  times. }
function HashRequests(Count: Integer): UInt64; noinline;
var
  P, Payload: PByte;
  Hash, A, B, C, D, E, F, G: UInt64;
  I, J: Integer;
begin
  Hash := OffsetBasis xor (UInt64(Count) * UInt64($9E3779B97F4A7C15));
  Payload := @Records[Count and 7];
  Result := 0;
  for I := 1 to 2 do
    begin
      A := 1;
      B := 2;
      C := 3;
      D := 4;
      E := 5;
      F := 6;
      G := UInt64(I);
      P := @Records[0];
      for J := 1 to Count do
        begin
          ClobberVolatile;
          Payload := P + 1;
          while Payload < P + 1 + P^ do
            begin
              Hash := (Hash xor Payload^) * Prime;
              Inc(Payload);
            end;
          Inc(P, 1 + P^);
          A := A + Hash;
          B := B xor (Hash shr 3);
          C := C + (A shr 1);
          D := D xor C;
          E := E + D;
          F := F xor (E shl 1);
          G := G + F;
        end;
      Result := Result xor A xor B xor C xor D xor E xor F xor G;
    end;
  Result := Result xor Hash xor
    UInt64(Payload - PByte(@Records[0])) * UInt64($C2B2AE3D27D4EB4F);
end;


{ Continue and break leave through the continue and break labels; J = 0
  never enters the inner loop.  I and S are used after the loop. }
function BreakAndContinue(Count: Integer): Integer; noinline;
var
  I, S, Limit, J, Total: Integer;
begin
  Total := 0;
  for J := 0 to Count - 1 do
    begin
      ClobberVolatile;
      Limit := J * 3;
      I := 0;
      S := 0;
      while I < Limit do
        begin
          Inc(I);
          if I mod 3 = 0 then
            Continue;
          Inc(S, I);
          if S > 40 then
            Break;
        end;
      Total := Total + S * 100 + I;
    end;
  Result := Total;
end;


{ A call-free loop nested in the outermost one writes the same values and
  K, defined anew by every pass before its use. }
function NestedInner(Count: Integer): Integer; noinline;
var
  J, I, K, Acc: Integer;
begin
  Result := 0;
  for J := 1 to Count do
    begin
      ClobberVolatile;
      Acc := J;
      I := 0;
      K := 0;
      while I < J do
        begin
          K := 0;
          repeat
            Inc(Acc, K * I + 1);
            Inc(K);
          until K > I;
          Inc(I);
        end;
      Result := Result * 7 + Acc + I + K;
    end;
end;


{ Byte and Word carriers of a repeat loop. }
function RepeatNarrow(Count: Integer): Integer; noinline;
var
  J: Integer;
  B: Byte;
  W: Word;
begin
  Result := 0;
  for J := 1 to Count do
    begin
      ClobberVolatile;
      B := Byte(J * 13);
      W := Word(J * 1000);
      repeat
        B := B + 7;
        W := W xor (B shl 3);
      until B < 16;
      Result := Result + B + W * 3;
    end;
end;


{ A value parameter written by the loop, read again in the next iteration. }
function ParamWritten(Seed: UInt64; Count: Integer): UInt64; noinline;
var
  J, I: Integer;
begin
  Result := 0;
  for J := 1 to Count do
    begin
      ClobberVolatile;
      I := J;
      while I > 0 do
        begin
          Seed := Seed * 6364136223846793005 + 1442695040888963407;
          Dec(I, 2);
        end;
      Result := Result xor Seed xor UInt64(Int64(I));
    end;
end;


{ I is dead after the loop: every iteration assigns it before reading it. }
function DeadAfter(Count: Integer): Integer; noinline;
var
  J, I, Sum: Integer;
begin
  Result := 0;
  for J := 1 to Count do
    begin
      ClobberVolatile;
      I := J;
      Sum := 0;
      while I > 0 do
        begin
          Inc(Sum, I);
          Dec(I);
        end;
      Result := Result + Sum;
    end;
end;


{ Each loop ends the body of the enclosing loop, whose next pass defines I
  anew, and I is read after the enclosing loop: the value of the last pass
  must reach it.  Odd passes run a loop tested at its beginning, even passes
  a guarded repeat. }
function LastInBody(N: Integer): Integer; noinline;
var
  J, I, S: Integer;
begin
  I := 0;
  S := 0;
  for J := 0 to N do
    begin
      ClobberVolatile;
      I := J;
      if Odd(J) then
        while (I < N + 5) and ((I and 64) = 0) do
          begin
            Inc(I);
            Inc(S, I);
          end
      else
        while I < N + 4 do
          begin
            Inc(I, 2);
            S := S + I * 3;
          end;
    end;
  Result := I * 1000 + S;
end;


{ The string assignment calls a helper: the loop is not call-free. }
function ManagedInner(Count: Integer): Integer; noinline;
var
  J, I: Integer;
  S, T: string;
begin
  Result := 0;
  T := 'xy';
  S := '';
  for J := 1 to Count do
    begin
      ClobberVolatile;
      I := 0;
      while I < J do
        begin
          S := T;
          Inc(I);
        end;
      Result := Result + I + Length(S);
    end;
end;


{ The threadvar written by the loop keeps its thread storage. }
function ThreadvarInner(Count: Integer): Integer; noinline;
var
  J, I: Integer;
begin
  ThreadSum := 0;
  Result := 0;
  for J := 1 to Count do
    begin
      ClobberVolatile;
      I := 0;
      while I < J do
        begin
          Inc(ThreadSum, I);
          Inc(I);
        end;
      Result := Result + I;
    end;
  Result := Result * 1000 + ThreadSum;
end;


{ No enclosing loop: the call-free loop is outermost by itself, and nothing
  it accesses is spilled. }
function TopLevel(N: Integer): Integer; noinline;
var
  I, S: Integer;
begin
  ClobberVolatile;
  S := 0;
  I := 0;
  while I < N do
    begin
      Inc(S, I * I);
      Inc(I);
    end;
  ClobberVolatile;
  Result := S + I;
end;


{ Exit leaves the loop without its break label. }
function ExitInner(Count: Integer): Integer; noinline;
var
  J, I: Integer;
begin
  Result := 0;
  for J := 1 to Count do
    begin
      ClobberVolatile;
      I := 0;
      while I < J do
        begin
          Inc(I);
          if I > 5 then
            Exit(Result + I);
        end;
      Result := Result + I;
    end;
end;


{ repeat .. until False with Break, the last statement of the enclosing
  body: a loop without a successor. }
function RepeatFalse(N: Integer): Integer; noinline;
var
  J, I, S: Integer;
begin
  I := 0;
  S := 0;
  for J := 0 to N do
    begin
      ClobberVolatile;
      I := J * 2;
      repeat
        Inc(S, I);
        Dec(I);
        if I < J then
          Break;
      until False;
    end;
  Result := I * 1000 + S;
end;


{ A for-step loop tests its latch at the end; after it the counter holds the
  first value past the bound. }
function ForStep(N: Integer): Integer; noinline;
var
  J, K, S, Last: Integer;
begin
  S := 0;
  Last := 0;
  K := 0;
  for J := 0 to N do
    begin
      ClobberVolatile;
      for K := J to N * 3 step 4 do
        Inc(S, K);
      Last := Last + K;
    end;
  Result := S * 7 + Last;
end;


{ Continue in a for-step loop runs its latch. }
function ForStepContinue(N: Integer): Integer; noinline;
var
  J, K, S: Integer;
begin
  S := 0;
  for J := 1 to N do
    begin
      ClobberVolatile;
      for K := 0 to J * 5 step 3 do
        begin
          if Odd(K) then
            Continue;
          Inc(S, K * J);
        end;
    end;
  Result := S;
end;


{ Fewer values live over the call than callee-saved registers in either ABI:
  the recurrences of the call-free loop are not spilled, and the loop keeps
  the registers they have. }
function InRegisterAlready(Count: Integer): Integer; noinline;
var
  J, I, S, T: Integer;
begin
  S := 0;
  T := 1;
  for J := 1 to Count do
    begin
      ClobberVolatile;
      I := J * 5;
      while I > 0 do
        begin
          S := S + I;
          T := T xor (S shl 1);
          Dec(I, 3);
        end;
    end;
  Result := S * 3 + T;
end;


{ The bound of the call-free loop is invariant and lives over the whole
  routine next to the heartbeat's seven values: it is spilled, and the loop
  reads it from a register loaded before the loop, which it never writes. }
function SpilledInvariant(Count: Integer): UInt64; noinline;
var
  A, B, C, D, E, F, G, S: UInt64;
  Limit, I, J, K: Integer;
begin
  Limit := Count * 3 + 1;
  S := 0;
  Result := 0;
  for I := 1 to 2 do
    begin
      A := 1;
      B := 2;
      C := 3;
      D := 4;
      E := 5;
      F := 6;
      G := UInt64(I);
      for J := 1 to Count do
        begin
          ClobberVolatile;
          K := J;
          while K < Limit do
            begin
              S := S * 31 + UInt64(K);
              Inc(K, 2);
            end;
          A := A + S;
          B := B xor (S shr 3);
          C := C + (A shr 1);
          D := D xor C;
          E := E + D;
          F := F xor (E shl 1);
          G := G + F;
        end;
      Result := Result xor A xor B xor C xor D xor E xor F xor G;
    end;
  Result := Result xor S xor UInt64(Limit);
end;


{ Seven values and the found position live over the calls, and the position
  is spilled.  The call-free loop writes it once, just before it breaks: the
  write runs at most once per entry, so a register loaded before the loop
  and stored after it would cost more than the write, and the position keeps
  its slot.  A key which is not in the records leaves the position as it
  was. }
function WriteThenBreak(Count: Integer): UInt64; noinline;
var
  A, B, C, D, E, F, G: UInt64;
  Found, J, K, Key: Integer;
begin
  Found := -1;
  A := 1;
  B := 2;
  C := 3;
  D := 4;
  E := 5;
  F := 6;
  G := 7;
  for J := 1 to Count do
    begin
      ClobberVolatile;
      A := A + UInt64(J);
      B := B xor (A shr 3);
      C := C + (B shr 1);
      D := D xor C;
      E := E + D;
      F := F xor (E shl 1);
      G := G + F;
    end;
  Key := Byte(Count * 37 + 11);
  K := 0;
  while K < Length(Records) do
    begin
      if Records[K] = Key then
        begin
          Found := K;
          Break;
        end;
      Inc(K);
    end;
  ClobberVolatile;
  Result := A xor B xor C xor D xor E xor F xor G xor UInt64(Int64(Found));
end;


{ The same, but the spilled value is written on every iteration and read
  only after the loop: the write repeats, so the loop keeps the value in a
  register and stores it once after the loop.  A start past the records
  enters the loop zero times. }
function WriteEveryIteration(Count: Integer): UInt64; noinline;
var
  A, B, C, D, E, F, G: UInt64;
  Last, J, K: Integer;
begin
  Last := 0;
  A := 1;
  B := 2;
  C := 3;
  D := 4;
  E := 5;
  F := 6;
  G := 7;
  for J := 1 to Count do
    begin
      ClobberVolatile;
      A := A + UInt64(J);
      B := B xor (A shr 3);
      C := C + (B shr 1);
      D := D xor C;
      E := E + D;
      F := F xor (E shl 1);
      G := G + F;
    end;
  K := Count;
  while K < Length(Records) do
    begin
      Last := K * 3 + Records[K];
      Inc(K, 5);
    end;
  ClobberVolatile;
  Result := A xor B xor C xor D xor E xor F xor G xor UInt64(Last);
end;


begin
  FillRecords;
  if HashRequests(8)<>UInt64($CF887029A440E251) then
    Halt(1);
  if BreakAndContinue(9)<>28273 then
    Halt(2);
  if NestedInner(6)<>101931 then
    Halt(3);
  if RepeatNarrow(9)<>128112 then
    Halt(4);
  if ParamWritten(UInt64($0123456789ABCDEF),5)<>UInt64($F347BFE9E7549D40) then
    Halt(5);
  if DeadAfter(7)<>84 then
    Halt(6);
  if ManagedInner(4)<>18 then
    Halt(7);
  if ThreadvarInner(5)<>15020 then
    Halt(8);
  if TopLevel(9)<>213 then
    Halt(9);
  if ExitInner(8)<>21 then
    Halt(10);
  if LastInBody(5)<>10389 then
    Halt(11);
  if LastInBody(6)<>10476 then
    Halt(12);
  if RepeatFalse(6)<>5168 then
    Halt(13);
  if ForStep(7)<>3380 then
    Halt(14);
  if ForStepContinue(6)<>1050 then
    Halt(15);
  if InRegisterAlready(7)<>2408 then
    Halt(16);
  if SpilledInvariant(6)<>UInt64($75664BEA5A3995E8) then
    Halt(17);
  if WriteThenBreak(9)<>UInt64($00000000000001E0) then
    Halt(18);
  if WriteThenBreak(4)<>UInt64($FFFFFFFFFFFFFF88) then
    Halt(19);
  if WriteEveryIteration(5)<>UInt64($00000000000000E8) then
    Halt(20);
  if WriteEveryIteration(70)<>UInt64($00000000000AAEAA) then
    Halt(21);
end.
