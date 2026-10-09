program asm_delphi_operands_semantic;
{$APPTYPE CONSOLE}
{$Q-}{$R-}
uses System.SysUtils;
var
  G: UInt64;
  Small: Byte;
  WordValue: Word;
  DwordValue: Cardinal;
  Copied: UInt64;
  Last: Int64;

function StackArgument(A,B,C,D,E,F,H,V: Int64): Int64; assembler;
asm
  .noframe
  mov rax,V
end;

procedure StackReference(A,B,C,D,E,F,H: Int64; var V: Int64); assembler;
asm
  .noframe
  mov rax,V
  mov qword ptr [rax],12345
end;

{$ifdef FPC}
function HeaderNoFrame(A,B,C,D,E,F,H,V: Int64): Int64; assembler; nostackframe;
asm
  mov rax,V
end;
{$endif}

function ReadRCX: UInt64; assembler;
asm
  .noframe
  mov rcx, G
  mov rax, rcx
end;

function ReadR10: UInt64; assembler;
asm
  mov r10, [G]
  mov rax, r10
end;

function GlobalAddress: Pointer; assembler;
asm
  lea rax, G
end;

procedure StoreGlobal; assembler;
asm
  mov r10, 123456789ABCDEF0h
  mov G, r10
  mov cl, 40
  inc(cl)
  inc (cl)
  mov Small, cl
  mov dx, 7654h
  mov WordValue, dx
  mov r8d, 98765432h
  mov DwordValue, r8d
  movq xmm0, G
  movq Copied, xmm0
end;

function ImmAdd: UInt64; assembler;
asm
  xor eax, eax
  add rax,3983948547
end;

function ImmMove: UInt64; assembler;
asm
  mov rax,3983948547
end;

function ImmLogic: UInt64; assembler;
asm
  xor eax, eax
  or rax,0FFFFFFFFh
  and rax,0FFFFFFFEh
  xor rax,0FFFFFFFCh
end;

procedure ImmMemory; assembler;
asm
  mov qword ptr [G],0FFFFFFFFh
end;

{$ifdef MSWINDOWS}
function StackBase: Pointer; assembler;
asm
  .noframe
  mov rax, abs [gs:08h]
end;

function StackLimit: Pointer; assembler;
asm
  mov rax, abs [gs:10h]
end;
{$endif}

begin
  Last:=$123456789ABC;
  If StackArgument(1,2,3,4,5,6,7,Last)<>Last then
    raise Exception.Create('Frameless stack argument');
  {$ifdef FPC}
  If HeaderNoFrame(1,2,3,4,5,6,7,Last)<>Last then
    raise Exception.Create('Header nostackframe argument');
  {$endif}
  StackReference(1,2,3,4,5,6,7,Last);
  If Last<>12345 then
    raise Exception.Create('Frameless stack reference');
  StoreGlobal;
  If (G <> $123456789ABCDEF0) or (Copied <> G) or (ReadRCX <> G) or
     (ReadR10 <> G) or (GlobalAddress <> @G) or (Small <> 42) or
     (WordValue <> $7654) or (DwordValue <> $98765432) then
    raise Exception.Create('Symbol addressing or operand width');
  If (ImmAdd <> UInt64(Int64(-311018749))) or (ImmMove <> UInt64(3983948547)) or (ImmLogic <> 2) then
    raise Exception.Create('imm32 sign extension versus imm64');
  ImmMemory;
  If G <> High(UInt64) then
    raise Exception.Create('Memory imm32 sign extension');
  {$ifdef MSWINDOWS}
  {$ifdef FPC}
  If (NativeUInt(@G) < $100000000) then
    raise Exception.Create('Win64 oracle requires the product image above 4GB');
  {$endif}
  If StackBase = nil then
    raise Exception.Create('Missing stack base');
  If NativeUInt(StackBase) <= NativeUInt(StackLimit) then
    raise Exception.Create('Absolute segment addressing');
  {$endif}
  WriteLn('ASM_DELPHI_OPERANDS_PASS');
end.
