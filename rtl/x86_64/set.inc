{
    This file is part of the Free Pascal run time library.
    Copyright (c) 2002 by the Free Pascal development team

    Include file with set operations called by the compiler

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}

{$asmmode intel}

{ The routines below are laid out by hand (doc/ASM_LAYOUT_RULES.md).  The byte loop for sets
  shorter than 16 bytes is reached by a jump only, so it starts a line ("align 64": the bytes
  are dead) and lies inside it; before, it lay across the line and its sub+jae pair across the
  boundary.  In the two routines without a precalculated tail the 16-byte loop got DS prefixes
  (db $3E: ignored in long mode, no uop) on its moves - four, and three more with the shorter
  SysV encodings - so that its sub+ja pair starts on byte 32: it crossed that byte on Win64
  and its jump ended on byte 30, a slow place of Zen 3, on SysV. }
{$ifndef FPC_SYSTEM_HAS_FPC_VARSET_ADD_SETS}
procedure fpc_varset_add_sets(const set1,set2; var dest;size : ptrint); compilerproc; assembler; nostackframe;
{ Windows: rcx = set1, rdx = set2, r8 = dest, r9 = size
  Linux:   rdi = set1, rsi = set2, rdx = dest, rcx = size }
asm
    sub    size, 16
    jl     @Bytewise_Prepare { probably dead branch... }

@16x_Loop:
    db     $3E,$3E,$3E
    movdqu xmm0, xmmword ptr [set1 + size]
    db     $3E
    movdqu xmm1, xmmword ptr [set2 + size]
    por    xmm0, xmm1
{$ifndef FPC_ABI_WIN64}
    db     $3E,$3E,$3E
{$endif}
    movdqu xmmword ptr [dest + size], xmm0
    sub    size, 16
    ja     @16x_Loop

    movdqu xmm0, xmmword ptr [set1] { Tail, just in case (if size is always divisible by 16, 16x_Loop can be altered to handle everything instead). }
    movdqu xmm1, xmmword ptr [set2]
    por    xmm0, xmm1
    movdqu xmmword ptr [dest], xmm0
    ret

    align  64
@Bytewise_Prepare:
    add    size, 15
@Bytewise_Loop:
    movzx  eax, byte ptr [set1 + size]
    or     al, byte ptr [set2 + size]
    mov    byte ptr [dest + size], al
    sub    size, 1
    jae    @Bytewise_Loop
end;
{$define FPC_SYSTEM_HAS_FPC_VARSET_ADD_SETS}
{$endif ndef FPC_SYSTEM_HAS_FPC_VARSET_ADD_SETS}

{$ifndef FPC_SYSTEM_HAS_FPC_VARSET_MUL_SETS}
procedure fpc_varset_mul_sets(const set1,set2; var dest;size : ptrint); compilerproc; assembler; nostackframe;
{ Same as fpc_varset_add_sets but with 'and' instead of 'or'. }
asm
    sub    size, 16
    jl     @Bytewise_Prepare { probably dead branch... }

@16x_Loop:
    db     $3E,$3E,$3E
    movdqu xmm0, xmmword ptr [set1 + size]
    db     $3E
    movdqu xmm1, xmmword ptr [set2 + size]
    pand   xmm0, xmm1
{$ifndef FPC_ABI_WIN64}
    db     $3E,$3E,$3E
{$endif}
    movdqu xmmword ptr [dest + size], xmm0
    sub    size, 16
    ja     @16x_Loop

    movdqu xmm0, xmmword ptr [set1] { Tail, just in case (if size is always divisible by 16, 16x_Loop can be altered to handle everything instead). }
    movdqu xmm1, xmmword ptr [set2]
    pand   xmm0, xmm1
    movdqu xmmword ptr [dest], xmm0
    ret

    align  64
@Bytewise_Prepare:
    add    size, 15
@Bytewise_Loop:
    movzx  eax, byte ptr [set1 + size]
    and    al, byte ptr [set2 + size]
    mov    byte ptr [dest + size], al
    sub    size, 1
    jae    @Bytewise_Loop
end;
{$define FPC_SYSTEM_HAS_FPC_VARSET_MUL_SETS}
{$endif ndef FPC_SYSTEM_HAS_FPC_VARSET_MUL_SETS}

{$ifndef FPC_SYSTEM_HAS_FPC_VARSET_SUB_SETS}
procedure fpc_varset_sub_sets(const set1,set2; var dest;size : ptrint); compilerproc; assembler; nostackframe;
{ Windows: rcx = set1, rdx = set2, r8 = dest, r9 = size
  Linux:   rdi = set1, rsi = set2, rdx = dest, rcx = size }
asm
    sub    size, 16
    jl     @Bytewise_Prepare { probably dead branch... }

    movdqu xmm1, xmmword ptr [set1] { Tail, just in case (if size is always divisible by 16, 16x_Loop can be altered to handle everything instead). }
    movdqu xmm2, xmmword ptr [set2] { Precalculated because operation is not idempotent and dest can be equal to set1/set2. }
    pandn  xmm2, xmm1

@16x_Loop:
    movdqu xmm1, xmmword ptr [set1 + size]
    movdqu xmm0, xmmword ptr [set2 + size]
    pandn  xmm0, xmm1
    movdqu xmmword ptr [dest + size], xmm0
    sub    size, 16
    ja     @16x_Loop

    movdqu xmmword ptr [dest], xmm2 { Write precalculated tail. }
    ret

    align  64
@Bytewise_Prepare:
    add    size, 15
@Bytewise_Loop:
    movzx  eax, byte ptr [set2 + size]
    not    eax
    and    al, byte ptr [set1 + size]
    mov    byte ptr [dest + size], al
    sub    size, 1
    jae    @Bytewise_Loop
end;
{$define FPC_SYSTEM_HAS_FPC_VARSET_SUB_SETS}
{$endif ndef FPC_SYSTEM_HAS_FPC_VARSET_SUB_SETS}

{$ifndef FPC_SYSTEM_HAS_FPC_VARSET_SYMDIF_SETS}
procedure fpc_varset_symdif_sets(const set1,set2; var dest;size : ptrint); compilerproc; assembler; nostackframe;
{ Same as fpc_varset_sub_sets but with 'xor' instead of 'and not'.

  Windows: rcx = set1, rdx = set2, r8 = dest, r9 = size
  Linux:   rdi = set1, rsi = set2, rdx = dest, rcx = size }
asm
    sub    size, 16
    jl     @Bytewise_Prepare { probably dead branch... }

    movdqu xmm2, xmmword ptr [set1] { Tail, just in case (if size is always divisible by 16, 16x_Loop can be altered to handle everything instead). }
    movdqu xmm1, xmmword ptr [set2] { Precalculated because operation is not idempotent and dest can be equal to set1/set2. }
    pxor   xmm2, xmm1

@16x_Loop:
    movdqu xmm0, xmmword ptr [set1 + size]
    movdqu xmm1, xmmword ptr [set2 + size]
    pxor   xmm0, xmm1
    movdqu xmmword ptr [dest + size], xmm0
    sub    size, 16
    ja     @16x_Loop

    movdqu xmmword ptr [dest], xmm2 { Write precalculated tail. }
    ret

    align  64
@Bytewise_Prepare:
    add    size, 15
@Bytewise_Loop:
    movzx  eax, byte ptr [set2 + size]
    xor    al, byte ptr [set1 + size]
    mov    byte ptr [dest + size], al
    sub    size, 1
    jae    @Bytewise_Loop
end;
{$define FPC_SYSTEM_HAS_FPC_VARSET_SYMDIF_SETS}
{$endif ndef FPC_SYSTEM_HAS_FPC_VARSET_SYMDIF_SETS}

{$ifndef FPC_SYSTEM_HAS_FPC_VARSET_CONTAINS_SET}
{$push}{$codealign proc=64}      { layout: the entry on a 64-byte line }
function fpc_varset_contains_sets(const set1,set2;size : ptrint):boolean; compilerproc; assembler; nostackframe;
{ Windows: rcx = set1, rdx = set2, r8 = size
  Linux:   rdi = set1, rsi = set2, rdx = size }
asm
    sub    size, 16
    jl     @Bytewise_Prepare { probably dead branch... }

{ Folds all 16-byte "set1 and not set2" chunks with OR and checks the final result for zero. Better for small enough sets. }
    movdqu xmm1, xmmword ptr [set1]
    movdqu xmm2, xmmword ptr [set2]
    pandn  xmm2, xmm1

@16x_Loop:
    movdqu xmm1, xmmword ptr [set1 + size]
    movdqu xmm0, xmmword ptr [set2 + size]
    pandn  xmm0, xmm1
    por    xmm2, xmm0
    sub    size, 16
    ja     @16x_Loop

    pxor   xmm0, xmm0
    pcmpeqb xmm0, xmm2
    pmovmskb ecx, xmm0
    xor    eax, eax
    inc    cx
    setz   al
    ret

@No:
    xor    eax, eax
    ret

    align  16                   { dead bytes: both pairs of the byte loop clear of byte 32 }
@Bytewise_Prepare:
    add    size, 16
    neg    size
    sub    set1, size
    sub    set2, size
@Bytewise_Loop:
    movzx  eax, byte ptr [set2 + size]
    not    eax
    test   byte ptr [set1 + size], al
    jnz    @No
    inc    size
    jnz    @Bytewise_Loop
    mov    eax, $1
end;
{$pop}
{$define FPC_SYSTEM_HAS_FPC_VARSET_CONTAINS_SET}
{$endif ndef FPC_SYSTEM_HAS_FPC_VARSET_CONTAINS_SET}

{$asmmode att}
