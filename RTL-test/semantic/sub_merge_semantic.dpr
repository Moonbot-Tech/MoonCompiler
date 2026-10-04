program sub_merge_semantic;

{ Two subtractions of constants from one register are one subtraction of
  their sum (x86 peephole, OptPass1Sub).  Where the sum was negative the
  rule changed the sign of the constant and left the instruction a
  subtraction: "sub $3,%rax; sub $-8,%rax" became "sub $5,%rax", not
  "add $5,%rax".  64-bit operands only: the constant of a narrower
  instruction is masked and never negative.  -O1 was correct, -O2 and above
  were not.

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

procedure Check(Got, Want: Int64; const Name: string);
begin
  if Got <> Want then
  begin
    WriteLn('FAIL ', Name, ': ', Got, ' <> ', Want);
    Inc(Fails);
  end;
end;

function DecDec(K: Int64): Int64; noinline;
var
  X: Int64;
begin
  X := K * 3;
  Dec(X, 3);
  Dec(X, -8);
  Result := X;
end;

function MinusMinus(K: Int64): Int64; noinline;
var
  X: Int64;
begin
  X := K * 3;
  X := X - 3;
  X := X - (-8);
  Result := X;
end;

function DecDecDown(K: Int64): Int64; noinline;
var
  X: Int64;
begin
  X := K * 3;
  Dec(X, -3);
  Dec(X, 8);
  Result := X;
end;

function DecDecBoth(K: Int64): Int64; noinline;
var
  X: Int64;
begin
  X := K * 3;
  Dec(X, -3);
  Dec(X, -8);
  Result := X;
end;

function DecDecZero(K: Int64): Int64; noinline;
var
  X: Int64;
begin
  X := K * 3;
  Dec(X, 8);
  Dec(X, -8);
  Result := X;
end;

function DecDec32(K: Integer): Integer; noinline;
var
  X: Integer;
begin
  X := K * 3;
  Dec(X, 3);
  Dec(X, -8);
  Result := X;
end;

function IncDec(K: Int64): Int64; noinline;
var
  X: Int64;
begin
  X := K * 3;
  Inc(X, 3);
  Dec(X, 8);
  Result := X;
end;

function DecInc(K: Int64): Int64; noinline;
var
  X: Int64;
begin
  X := K * 3;
  Dec(X, 3);
  Inc(X, 8);
  Result := X;
end;

function DecDecWide(K: Int64): Int64; noinline;
var
  X: Int64;
begin
  X := K * 3;
  Dec(X, 1000000);
  Dec(X, -3000000);
  Result := X;
end;

begin
  Check(DecDec(10), 35, 'Dec by 3 and by -8');
  Check(MinusMinus(10), 35, 'minus 3 and minus -8');
  Check(DecDecDown(10), 25, 'Dec by -3 and by 8');
  Check(DecDecBoth(10), 41, 'Dec by -3 and by -8');
  Check(DecDecZero(10), 30, 'Dec by 8 and by -8');
  Check(DecDec32(10), 35, 'Dec of a 32-bit value by 3 and by -8');
  Check(IncDec(10), 25, 'Inc by 3 and Dec by 8');
  Check(DecInc(10), 35, 'Dec by 3 and Inc by 8');
  Check(DecDecWide(10), 2000030, 'Dec by a million and by minus three millions');

  if Fails = 0 then
    WriteLn('SUB_MERGE_PASS')
  else
  begin
    WriteLn('SUB_MERGE_FAIL ', Fails);
    Halt(1);
  end;
end.
