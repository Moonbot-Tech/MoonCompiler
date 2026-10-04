program value_forward_semantic;
{$ifdef FPC}{$mode delphi}{$H+}{$asmmode intel}{$endif}
{$APPTYPE CONSOLE}
{$Q-}{$R-}

type
  TValues = array[0..7] of Int64;
  PValues = ^TValues;
var
  Values: TValues;
  Failures: Integer;

{ ISA witnesses for the existing Full32Write producer set. These assembler
  routines do not exercise the peephole; the source and IR tests below do. }
function ShiftLeftUpper(N: UInt32): UInt64;
{$ifdef FPC}assembler; nostackframe;{$endif}
asm
  {$ifndef MSWINDOWS}mov ecx, edi{$endif}
  mov rax, $FEDCBA9887654321
  shl eax, cl
end;

function ShiftRightUpper(N: UInt32): UInt64;
{$ifdef FPC}assembler; nostackframe;{$endif}
asm
  {$ifndef MSWINDOWS}mov ecx, edi{$endif}
  mov rax, $FEDCBA9887654321
  shr eax, cl
end;

function ShiftSignedUpper(N: UInt32): UInt64;
{$ifdef FPC}assembler; nostackframe;{$endif}
asm
  {$ifndef MSWINDOWS}mov ecx, edi{$endif}
  mov rax, $FEDCBA9887654321
  sar eax, cl
end;

function TruncateIndex(A: UInt64; P: PValues): Int64;
var I: UInt32;
begin
  I := UInt32(A) and 7;
  Result := P^[I];
end;

function KeepUpper(A: UInt64): UInt64;
var B: UInt32;
begin
  B := UInt32(A);
  Result := UInt64(B) + (A shr 32);
end;

function ShiftIndex(A: UInt32; N: Byte; P: PValues): Int64;
var I: UInt32;
begin
  I := (A shr N) and 7;
  Result := P^[I];
end;

function MutateSource(A: UInt32; B: Byte): UInt64;
var C: UInt32;
begin
  C := A;
  PByte(@A)^ := B;
  Result := UInt64(C) + UInt64(A) * 65537;
end;

function ByteDivision(A, B: Byte): UInt32;
var R, Q: Byte;
begin
  R := A mod B;
  Q := A div B;
  Result := UInt32(R) + UInt32(Q) * 65536;
end;

procedure Check(Ok: Boolean);
begin
  If not Ok then Inc(Failures);
end;

var
  A: UInt64;
  Lo, Hi: UInt32;
  I, J, K: Integer;
  Count: Byte;
  Expected: UInt32;
begin
  for I := 0 to 7 do Values[I] := Int64(I) * 1234567891 - 9988776655;
  for I := 0 to 255 do begin
    Check((ShiftLeftUpper(I) shr 32) = 0);
    Check((ShiftRightUpper(I) shr 32) = 0);
    Check((ShiftSignedUpper(I) shr 32) = 0);
  end;
  for I := 0 to 255 do begin
    Lo := UInt32(I) * 16909060;
    Hi := UInt32(255-I) * 16843009;
    A := (UInt64(Hi) shl 32) or Lo;
    Check(TruncateIndex(A, @Values) = Values[Lo mod 8]);
    Check(KeepUpper(A) = UInt64(Lo) + Hi);
    Check(MutateSource(Lo, Byte(255-I)) = UInt64(Lo) +
      UInt64((Lo and $FFFFFF00) or UInt32(255-I)) * 65537);
    for J := 0 to 255 do begin
      Count := Byte(J);
      Expected := Lo;
      for K := 1 to (J and 31) do Expected := Expected div 2;
      Check(ShiftIndex(Lo, Count, @Values) = Values[Expected mod 8]);
    end;
    for J := 1 to 255 do begin
      K := I;
      Expected := 0;
      while K >= J do begin
        Dec(K, J);
        Inc(Expected, 65536);
      end;
      Inc(Expected, K);
      Check(ByteDivision(Byte(I), Byte(J)) = Expected);
    end;
  end;
  If Failures <> 0 then begin
    WriteLn('VALUE_FORWARD_FAIL ', Failures);
    Halt(1);
  end;
  WriteLn('VALUE_FORWARD_PASS');
end.
