program add_swap_semantic;

{ "add $8,%reg" followed by an addition or a subtraction to the same register
  was moved behind it by the x86 peephole (OptPass1Add, OptPass1Sub,
  "Add/sub swap 1a/1b") so that the constant can join an address later.  The
  second operation may read the register it changes - as its source or in
  the address of its memory operand - and then it read the value without the
  constant:

    Inc(P, 8);              add  $8,%rcx          add  (%rcx),%rcx
    Inc(P, PInt64(P)^);     add  (%rcx),%rcx  ->  add  $8,%rcx

  SkipBlock and SkipBack step over a block whose length stands in its
  header, the way a reader of a binary format does.  Twice and Cancel are
  the same in registers only.  -O1 was correct, -O2 and above were not.

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

function SkipBlock(P: PByte): Int64; noinline;
begin
  Inc(P, 8);
  Inc(P, PInt64(P)^);
  Result := PInt64(P)^;
end;

function SkipBack(P: PByte): Int64; noinline;
begin
  Dec(P, 8);
  Dec(P, PInt64(P)^);
  Result := PInt64(P)^;
end;

function SkipTwo(P: PByte; Step: Int64): Int64; noinline;
begin
  Inc(P, 16);
  Inc(P, PInt64(P + Step)^);
  Result := PInt64(P)^;
end;

function Twice(K: Int64): Int64; noinline;
var
  X: Int64;
begin
  X := K * 3;
  X := X + 3;
  X := X + X;
  Result := X;
end;

function TwiceDown(K: Int64): Int64; noinline;
var
  X: Int64;
begin
  X := K * 3;
  X := X - 3;
  X := X + X;
  Result := X;
end;

function Cancel(K: Int64): Int64; noinline;
var
  X, Y: Int64;
begin
  X := K * 3;
  Y := K + 1;
  X := X - 3;
  X := X - X;
  Result := X + Y;
end;

function Twice32(K: Integer): Integer; noinline;
var
  X: Integer;
begin
  X := K * 3;
  X := X + 3;
  X := X + X;
  Result := X;
end;

{ the other operand is another register: the two may change places }
function Plain(K, L: Int64): Int64; noinline;
var
  X: Int64;
begin
  X := K * 3;
  X := X + 3;
  X := X + L;
  Result := X;
end;

begin
  Buf[0] := 40; Buf[1] := 24; Buf[2] := 0; Buf[3] := 0;
  Buf[4] := 777; Buf[5] := 0; Buf[6] := 555; Buf[7] := 0;
  Check(SkipBlock(@Buf[0]), 777, 'a block is stepped over by the length in its header');
  Buf[0] := 111; Buf[1] := 333; Buf[2] := 0; Buf[3] := 0;
  Buf[4] := 24; Buf[5] := 0; Buf[6] := 0; Buf[7] := 0;
  Check(SkipBack(@Buf[5]), 333, 'a block is stepped back by the length in its trailer');
  Buf[0] := 0; Buf[1] := 0; Buf[2] := 5; Buf[3] := 16;
  Buf[4] := 0; Buf[5] := 888; Buf[6] := 0; Buf[7] := 999;
  Check(SkipTwo(@Buf[1], 0), 888, 'the length stands behind the header');
  Check(Twice(10), 66, 'a sum with a constant is doubled');
  Check(TwiceDown(10), 54, 'a difference with a constant is doubled');
  Check(Cancel(10), 11, 'a difference with a constant is taken from itself');
  Check(Twice32(10), 66, 'a 32-bit sum with a constant is doubled');
  Check(Plain(10, 5), 38, 'a sum with a constant and another register');

  if Fails = 0 then
    WriteLn('ADD_SWAP_PASS')
  else
  begin
    WriteLn('ADD_SWAP_FAIL ', Fails);
    Halt(1);
  end;
end.
