program lea_operand_semantic;

{ An address which is a pointer and a constant, in a register of its own:
  "lea -12(%rax),%rax; orl $2,4(%rax)".  The instruction which follows takes
  the address as its operand, "orl $2,-8(%rax)", and no LEA is left (x86
  peephole, OptPass1LEA, "LeaOp2Op").  A LEA which adds a constant to its own
  register was made an addition first, and an addition the instruction does
  not take.  The conversion comes behind the instruction which follows now.

  The forms: a flag in the header in front of a block, set, cleared and
  tested; a field of the header counted from another field; the address kept
  for a second statement; the address behind a sum of a pointer and an index;
  the header read and the pointer used behind it; a constant which moves the
  register where the flags of an addition would be read.

  The values are those of Delphi 12.2 and of -O1. }

{$mode delphi}{$H+}
{$Q-}{$R-}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  cwstring,
  {$endif UNIX}
  SysUtils;

type
  PHeader = ^THeader;
  THeader = record
    Ofs: Integer;
    SizeFlags: Cardinal;
    Kind: Cardinal;
  end;

const
  HeaderSize = SizeOf(THeader);

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

procedure SetFlag(Fp: PByte; Size: Cardinal); noinline;
var
  Nx: PByte;
begin
  Nx := Fp + Size;
  PHeader(Nx - HeaderSize)^.SizeFlags := PHeader(Nx - HeaderSize)^.SizeFlags or 2;
end;

procedure ClearFlag(Fp: PByte; Size: Cardinal); noinline;
var
  Nx: PByte;
begin
  Nx := Fp + Size;
  PHeader(Nx - HeaderSize)^.SizeFlags := PHeader(Nx - HeaderSize)^.SizeFlags and not Cardinal(2);
end;

function HasFlag(Fp: PByte; Size: Cardinal): Boolean; noinline;
var
  Nx: PByte;
begin
  Nx := Fp + Size;
  Result := PHeader(Nx - HeaderSize)^.SizeFlags and 4 <> 0;
end;

procedure SetBoth(Nx: PByte); noinline;
begin
  PHeader(Nx - HeaderSize)^.SizeFlags := PHeader(Nx - HeaderSize)^.SizeFlags or 8;
  PHeader(Nx - HeaderSize)^.Kind := PHeader(Nx - HeaderSize)^.Kind + PHeader(Nx - HeaderSize)^.SizeFlags;
end;

function HeaderAndNext(Nx: PByte): Int64; noinline;
var
  H: PHeader;
begin
  { the pointer is used behind the header }
  H := PHeader(Nx - HeaderSize);
  Inc(H^.Kind, 3);
  Result := Int64(H^.Kind) * 1000 + Nx^;
end;

function StepAndTest(P: PByte; Count: Integer): Integer; noinline;
var
  Q: PByte;
begin
  { the register moves by a constant and is compared behind the move }
  Result := 0;
  Q := P + 5;
  while Count > 0 do
    begin
      Inc(Q, 3);
      if Q^ <> 0 then
        Inc(Result);
      Dec(Count);
    end;
  if Q = P + 5 then
    Result := -1;
end;

function AtIndex(P: PByte; Index: Integer): Int64; noinline;
var
  H: PHeader;
begin
  H := PHeader(P + Index * SizeOf(THeader) - HeaderSize);
  H^.Ofs := H^.Ofs + 7;
  Result := H^.Ofs;
end;

var
  Buf: array[0..95] of Byte;
  H: PHeader;
  K: Integer;
begin
  FillChar(Buf, SizeOf(Buf), 0);
  H := PHeader(@Buf[20]);
  H^.SizeFlags := 5;
  H^.Kind := 100;
  SetFlag(@Buf[0], 32);
  Check(H^.SizeFlags, 7, 'a flag is set in the header in front of the block');
  Check(Ord(HasFlag(@Buf[0], 32)), 1, 'a flag is tested');
  ClearFlag(@Buf[0], 32);
  Check(H^.SizeFlags, 5, 'a flag is cleared');
  SetBoth(@Buf[32]);
  Check(Int64(H^.SizeFlags) * 1000 + H^.Kind, 13 * 1000 + 113, 'two statements with the address of the header');
  Buf[32] := 9;
  Check(HeaderAndNext(@Buf[32]), 116 * 1000 + 9, 'the pointer is used behind the header');
  for K := 40 to 95 do
    Buf[K] := Ord(K mod 2 = 0);
  Check(StepAndTest(@Buf[32], 10), 5, 'the register moves by a constant in a loop');
  Check(StepAndTest(@Buf[32], 0), -1, 'the loop does not run');
  PHeader(@Buf[60])^.Ofs := -3;
  Check(AtIndex(@Buf[36], 3), 4, 'the header of the element at an index');

  if Fails = 0 then
    WriteLn('LEA_OPERAND_PASS')
  else
  begin
    WriteLn('LEA_OPERAND_FAIL ', Fails);
    Halt(1);
  end;
end.
