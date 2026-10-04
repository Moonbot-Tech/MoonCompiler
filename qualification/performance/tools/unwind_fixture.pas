unit unwind_fixture;

{ The negative control of the unwind check (unwind_frames.py, run by
  qualification/build-driver/rtl_asm_layout_gate.py): hand-written routines whose unwind
  information is right (Good*) and routines that move the stack without saying so or say it
  wrong (Bad*).  The gate compiles this unit with the toolchain under test and fails unless
  every Bad* routine is reported and no Good* one is.  GoodPushAtt describes its save through
  the AT&T reader, the others through the Intel one. }

{$mode objfpc}
{$asmmode intel}

interface

procedure GoodLeaf;
procedure GoodPush;
procedure GoodAlloc;
procedure GoodPushAtt;
procedure BadPushSilent;
procedure BadAllocSilent;
procedure BadPushEarly;
{$ifdef LINUX}
procedure BadPushUntold;
{$endif}

implementation

procedure GoodLeaf; assembler; nostackframe;
asm
  mov rax, rcx
end;

procedure GoodPush; assembler; nostackframe;
asm
  push rbx
  {$ifdef WIN64}
  .seh_pushreg rbx
  .seh_endprologue
  {$endif}
  {$ifdef FPC_HAS_ASM_CFI_OFFSET}
  .cfi_def_cfa_offset 16
  .cfi_offset rbx, -16
  {$endif}
  xor ebx, ebx
  pop rbx
  {$ifdef FPC_HAS_ASM_CFI_OFFSET}
  .cfi_def_cfa_offset 8
  .cfi_restore rbx
  {$endif}
end;

procedure GoodAlloc; assembler; nostackframe;
asm
  sub rsp, 24
  {$ifdef WIN64}
  .seh_stackalloc 24
  .seh_endprologue
  {$endif}
  {$ifdef FPC_HAS_ASM_CFI_OFFSET}
  .cfi_def_cfa_offset 32
  {$endif}
  mov [rsp], rax
  add rsp, 24
  {$ifdef FPC_HAS_ASM_CFI_OFFSET}
  .cfi_def_cfa_offset 8
  {$endif}
end;

{$asmmode att}
procedure GoodPushAtt; assembler; nostackframe;
asm
  pushq %rbx
  {$ifdef WIN64}
  .seh_pushreg %rbx
  .seh_endprologue
  {$endif}
  {$ifdef FPC_HAS_ASM_CFI_OFFSET}
  .cfi_def_cfa_offset 16
  .cfi_offset %rbx, -16
  {$endif}
  xorl %ebx, %ebx
  popq %rbx
  {$ifdef FPC_HAS_ASM_CFI_OFFSET}
  .cfi_def_cfa_offset 8
  .cfi_restore %rbx
  {$endif}
end;
{$asmmode intel}

{ a callee-saved register pushed and nothing told }
procedure BadPushSilent; assembler; nostackframe;
asm
  push rbx
  xor ebx, ebx
  pop rbx
end;

{ stack allocated and nothing told }
procedure BadAllocSilent; assembler; nostackframe;
asm
  sub rsp, 24
  mov [rsp], rax
  add rsp, 24
end;

{ told, but not where it happens: Win64 - the directive in front of its push (the unwinder
  takes the push for done an instruction early); Linux - the CFA one slot off }
procedure BadPushEarly; assembler; nostackframe;
asm
  {$ifdef WIN64}
  .seh_pushreg rbx
  push rbx
  .seh_endprologue
  {$endif}
  {$ifdef LINUX}
  push rbx
  .cfi_def_cfa_offset 24
  .cfi_offset rbx, -16
  {$endif}
  xor ebx, ebx
  pop rbx
  {$ifdef FPC_HAS_ASM_CFI_OFFSET}
  .cfi_def_cfa_offset 8
  .cfi_restore rbx
  {$endif}
end;

{$ifdef LINUX}
{ the CFA follows the push, the saved register is not told: an unwind through the frame
  would hand the caller the register the routine left there }
procedure BadPushUntold; assembler; nostackframe;
asm
  push rbx
  .cfi_def_cfa_offset 16
  xor ebx, ebx
  pop rbx
  .cfi_def_cfa_offset 8
end;
{$endif}

end.
