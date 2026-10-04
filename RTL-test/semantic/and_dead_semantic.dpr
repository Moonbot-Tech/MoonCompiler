program and_dead_semantic;

{ A byte or a word is read and extended, a mask is applied to it, and the
  result is not used: the variable which took it gets another value.  The
  x86 peephole (OptPass1Movx, "MovxOp2Op 2") gave the AND the operand the value
  was read from -

    movzwl GS+2(%rip),%eax          andw $2,GS+2(%rip)
    andl   $2,%eax             ->

  - and the mask was applied to the variable itself.  A following TEST made
  the AND a TEST; without one the AND stayed an AND.  -O1 was correct, -O2
  and above were not (a variable of the unit at -O2, a byte and a field
  behind a pointer at -O3).

  The values are those of Delphi 12.2 and of -O1. }

{$mode delphi}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  cwstring,
  {$endif UNIX}
  SysUtils;

type
  TSmall = record
    B0, B1: Byte;
    W1: Word;
    I1: Integer;
  end;
  PSmall = ^TSmall;

var
  Failures: Integer;
  GW: Word;
  GB: Byte;
  GS: TSmall;

procedure Check(const Name: string; Got, Want: Int64);
begin
  if Got <> Want then
  begin
    WriteLn('FAIL ', Name, ': ', Got, ' <> ', Want);
    Inc(Failures);
  end;
end;

{ the result of the mask is overwritten }
function DeadWord(K: Int64): Int64; noinline;
var
  N: Integer;
begin
  N := GS.W1;
  K := (Int64(N) and 2);
  N := 77;
  K := Int64(N);
  Result := K + GS.W1;
end;

function DeadByte(K: Int64): Int64; noinline;
var
  N: Integer;
begin
  N := GB;
  K := N and 12;
  K := 5;
  Result := K + GB;
end;

{ through a pointer }
function DeadField(P: PSmall; K: Int64): Int64; noinline;
var
  N: Integer;
begin
  N := P^.B1;
  K := N and 1;
  K := 3;
  Result := K + P^.B1;
end;

{ the value comes in a register }
function DeadParameter(B: Byte; K: Int64): Int64; noinline;
var
  N: Integer;
begin
  N := B;
  K := N and 4;
  K := 9;
  Result := K + B;
end;

{ only the flags of the mask are used }
function BitOfWord: Int64; noinline;
begin
  if (GW and 2) <> 0 then
    Result := 1000 + GW
  else
    Result := 2000 + GW;
end;

function BitOfField(P: PSmall): Int64; noinline;
begin
  if (P^.W1 and $4000) = 0 then
    Result := 1000 + P^.W1
  else
    Result := 2000 + P^.W1;
end;

function BitOfParameter(W: Word): Int64; noinline;
begin
  if (W and 8) <> 0 then
    Result := 1000 + W
  else
    Result := 2000 + W;
end;

{ or and xor of a constant }
function DeadOr(K: Int64): Int64; noinline;
var
  N: Integer;
begin
  N := GW;
  K := N or 1;
  K := 1;
  Result := K + GW;
end;

function DeadXor(K: Int64): Int64; noinline;
var
  N: Integer;
begin
  N := GB;
  K := N xor 255;
  K := 1;
  Result := K + GB;
end;

begin
  GS.B0 := 200; GS.B1 := 3; GS.W1 := 40000; GS.I1 := -5;
  Check('dead word', DeadWord(1), 77 + 40000);
  Check('dead word, the variable', GS.W1, 40000);
  GB := 255;
  Check('dead byte', DeadByte(1), 5 + 255);
  Check('dead byte, the variable', GB, 255);
  Check('dead field', DeadField(@GS, 1), 3 + 3);
  Check('dead field, the variable', GS.B1, 3);
  Check('dead parameter', DeadParameter(255, 1), 9 + 255);
  GW := 40002;
  Check('bit of a word', BitOfWord, 1000 + 40002);
  Check('bit of a word, the variable', GW, 40002);
  GS.W1 := $C123;
  Check('bit of a field', BitOfField(@GS), 2000 + $C123);
  Check('bit of a field, the variable', GS.W1, $C123);
  Check('bit of a parameter', BitOfParameter(40008), 1000 + 40008);
  GW := 40002;
  Check('dead or', DeadOr(1), 1 + 40002);
  Check('dead or, the variable', GW, 40002);
  GB := 100;
  Check('dead xor', DeadXor(1), 1 + 100);
  Check('dead xor, the variable', GB, 100);
  if Failures = 0 then
    WriteLn('AND_DEAD_PASS')
  else
  begin
    WriteLn('AND_DEAD_FAIL ', Failures);
    Halt(1);
  end;
end.
