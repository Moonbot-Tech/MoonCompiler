{ Exact UTF16 code-unit search shared by UnicodeString and BSTR wrappers.
  A leaf in the Microsoft ABI uses only volatile GPRs and XMM0..XMM5 on
  both targets. No helper calls, stack writes, or nonvolatile registers. }
{$push}{$asmmode intel}{$codealign proc=64}
function PosUTF16(Needle, Source: Pointer; NeedleLength, SourceLength, Offset: SizeInt): SizeInt;
  ms_abi_default; assembler; nostackframe;
asm
  xor eax,eax
  test r8,r8
  jle @done
  mov r10,[rsp+40]
  test r10,r10
  jle @done
  sub r9,r8
  jl @done
  inc r9
  cmp r10,r9
  jg @done
  lea rax,[rdx+r10*2-2]
  lea r9,[rdx+r9*2]
  lea r8,[r8*2-4]
  movzx r10d,word ptr [rcx+r8+2]
  movd xmm0,r10d
  pshuflw xmm0,xmm0,0
  pshufd xmm0,xmm0,0
{ RCX: needle, RDX: source, R8: needle bytes minus 4,
    R9: one past the last candidate start. Only even mask bits represent
    UTF16 boundaries. Every vector is contained in the declared strings. }
@scan:
  lea r11,[rax+64]
  cmp r11,r9
  ja @scan8
  movdqu xmm1,[rax+r8+2]
  movdqu xmm2,[rax+r8+18]
  movdqu xmm3,[rax+r8+34]
  movdqu xmm4,[rax+r8+50]
  pcmpeqw xmm1,xmm0
  pcmpeqw xmm2,xmm0
  pcmpeqw xmm3,xmm0
  pcmpeqw xmm4,xmm0
  movdqa xmm5,xmm1
  por xmm5,xmm2
  por xmm5,xmm3
  por xmm5,xmm4
  pmovmskb r11d,xmm5
  test r11d,r11d
  jnz @mask32
  add rax,64
  jmp @scan
@mask32:
  pmovmskb r11d,xmm1
  pmovmskb r10d,xmm2
  shl r10,16
  or r11,r10
  pmovmskb r10d,xmm3
  shl r10,32
  or r11,r10
  pmovmskb r10d,xmm4
  shl r10,48
  or r11,r10
  mov r10,$5555555555555555
  and r11,r10
  lea r10,[rax+64]
  movq xmm3,r10
  jmp @batch
@scan8:
  lea r11,[rax+16]
  cmp r11,r9
  ja @tail
  movdqu xmm1,[rax+r8+2]
  pcmpeqw xmm1,xmm0
  pmovmskb r11d,xmm1
  and r11d,$5555
  jnz @mask8
  add rax,16
  jmp @scan8
@mask8:
  lea r10,[rax+16]
  movq xmm3,r10
  jmp @batch
@miss:
  xor eax,eax
@done:
  ret
@batch:
  movq xmm4,rax
@candidate:
  bsf r10,r11
  movq rax,xmm4
  add rax,r10
  lea r10,[r11-1]
  and r11,r10
  movq xmm5,r11
  test r8,r8
  js @found
  cmp r8,12
  jae @wide
  mov r10d,[rcx]
  cmp [rax],r10d
  jne @reject
  mov r11,r8
  test r11,r11
  jz @found
@words:
  mov r10d,[rcx+r11]
  cmp [rax+r11],r10d
  jne @reject
  sub r11,4
  jg @words
@found:
  sub rax,rdx
  shr rax,1
  inc rax
  ret
@wide:
  movdqu xmm1,[rcx]
  movdqu xmm2,[rax]
  pcmpeqb xmm1,xmm2
  pmovmskb r10d,xmm1
  cmp r10d,$ffff
  jne @reject
  lea r11,[r8-12]
  test r11,r11
  jz @found
@vectors:
  movdqu xmm1,[rcx+r11]
  movdqu xmm2,[rax+r11]
  pcmpeqb xmm1,xmm2
  pmovmskb r10d,xmm1
  cmp r10d,$ffff
  jne @reject
  sub r11,16
  jg @vectors
  jmp @found
@reject:
  movq r11,xmm5
  test r11,r11
  jnz @candidate
  movq rax,xmm3
  jmp @scan
@tail:
  cmp rax,r9
  jae @miss
  movzx r10d,word ptr [rcx+r8+2]
@tailscan:
  cmp [rax+r8+2],r10w
  je @tailcandidate
  add rax,2
  cmp rax,r9
  jb @tailscan
  xor eax,eax
  ret
@tailcandidate:
  lea r11,[rax+2]
  movq xmm3,r11
  mov r11d,1
  jmp @batch
end;
{$pop}
{$asmmode att}
