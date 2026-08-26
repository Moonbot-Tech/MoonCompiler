program delphi_implicit_asm_frame_semantic;

{$mode delphi}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  {$endif UNIX}
  SysUtils;

type
  THash = packed array[0 .. 3] of UInt64;

function EqualHash(var A, B: THash): Boolean;
asm
  {$ifndef MSWINDOWS}
  mov rcx, rdi
  mov rdx, rsi
  {$endif MSWINDOWS}
  mov rax, [rcx]
  cmp rax, [rdx]
  jne @NotEqual
  mov rax, [rcx + 8]
  cmp rax, [rdx + 8]
  jne @NotEqual
  mov rax, [rcx + 16]
  cmp rax, [rdx + 16]
  jne @NotEqual
  mov rax, [rcx + 24]
  cmp rax, [rdx + 24]
  jne @NotEqual
  mov rax, 1
  ret
@NotEqual:
  xor rax, rax
  ret
end;

function LocalFrame(Value: Byte): NativeInt;
var
  Buffer: array[0 .. 31] of Byte;
asm
  {$ifdef MSWINDOWS}
  mov byte ptr [Buffer], cl
  {$else}
  mov byte ptr [Buffer], dil
  {$endif MSWINDOWS}
  movzx eax, byte ptr [Buffer]
end;

function StackParameter(A1, A2, A3, A4, A5, A6, A7: NativeInt): NativeInt;
asm
  mov rax, A7
end;

var
  A, B: THash;

begin
  A[0] := 1;
  A[1] := 2;
  A[2] := 3;
  A[3] := 4;
  B := A;
  If not EqualHash(A, B) then
    raise Exception.Create('equal hash was rejected');
  B[2] := 5;
  If EqualHash(A, B) then
    raise Exception.Create('different hash was accepted');
  If LocalFrame(37) <> 37 then
    raise Exception.Create('assembler local frame was lost');
  If StackParameter(1, 2, 3, 4, 5, 6, 7) <> 7 then
    raise Exception.Create('assembler stack parameter frame was lost');
  WriteLn('DELPHI_IMPLICIT_ASM_FRAME_PASS');
end.
