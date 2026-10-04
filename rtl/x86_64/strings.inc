{
    This file is part of the Free Pascal run time library.
    Copyright (c) 2003 by Florian Klaempfl, member of the
    Free Pascal development team

    Processor dependent part of strings.pp, that can be shared with
    sysutils unit.

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}

{$ASMMODE GAS}

{$ifndef FPC_UNIT_HAS_STRCOMP}
{$define FPC_UNIT_HAS_STRCOMP}
{ Laid out by hand (doc/ASM_LAYOUT_RULES.md).  Each ABI works in its own argument registers, so
  the loop starts on byte 3 of the entry line in both and lies inside that line (bytes 3..58)
  instead of behind a 16-byte alignment and across the line; the two DS prefixes (0x3E: ignored
  in long mode, no uop) keep the third compare+jump pair off byte 32.  The encodings have the same
  lengths with either register pair. }
{$push}{$codealign proc=64}      { layout: the entry on a 64-byte line }
function StrComp(Str1, Str2: PAnsiChar): SizeInt;assembler;nostackframe;
asm
{$ifdef FPC_ABI_WIN64}
        subq   %rcx,%rdx
.Lloop:                          { unrolled 4 times }
        movb   (%rcx),%al
        cmpb   (%rdx,%rcx),%al
        jne    .Ldiff
        testb  %al,%al
        jz     .Leq
        movb   1(%rcx),%al
        cmpb   1(%rdx,%rcx),%al
        jne    .Ldiff
        testb  %al,%al
        jz     .Leq
        .byte  0x3E,0x3E
        movb   2(%rcx),%al
        cmpb   2(%rdx,%rcx),%al
        jne    .Ldiff
        testb  %al,%al
        jz     .Leq
        movb   3(%rcx),%al
        add    $4,%rcx
        cmpb   -1(%rdx,%rcx),%al
        jne    .Ldiff
        testb  %al,%al
        jnz    .Lloop
{$else FPC_ABI_WIN64}
        subq   %rdi,%rsi
.Lloop:                          { unrolled 4 times }
        movb   (%rdi),%al
        cmpb   (%rsi,%rdi),%al
        jne    .Ldiff
        testb  %al,%al
        jz     .Leq
        movb   1(%rdi),%al
        cmpb   1(%rsi,%rdi),%al
        jne    .Ldiff
        testb  %al,%al
        jz     .Leq
        .byte  0x3E,0x3E
        movb   2(%rdi),%al
        cmpb   2(%rsi,%rdi),%al
        jne    .Ldiff
        testb  %al,%al
        jz     .Leq
        movb   3(%rdi),%al
        add    $4,%rdi
        cmpb   -1(%rsi,%rdi),%al
        jne    .Ldiff
        testb  %al,%al
        jnz    .Lloop
{$endif FPC_ABI_WIN64}
.Leq:
        xorl   %eax,%eax
        ret

.Ldiff:
        sbbq   %rax,%rax        { -1 if CF was set, 0 otherwise }
        orb    $1,%al           { 0 becomes 1, -1 remains unchanged }
end;
{$pop}
{$endif FPC_UNIT_HAS_STRCOMP}
