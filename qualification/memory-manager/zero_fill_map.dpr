program zero_fill_map;
{$mode delphi}{$H+}{$asmmode intel}
{ Map of the cost of zeroing N bytes: rep stosd (what _AllocMem does from 256 bytes on), rep stosq, rep stosb,
  and SSE2 loops of 16, 32 and 64 bytes per iteration; best and worst of four destination alignments. }
uses
  {$ifdef MSWINDOWS}Windows,{$endif} SysUtils;

function Rdtsc: UInt64; assembler; nostackframe;
asm
  rdtsc
  shl rdx, 32
  or rax, rdx
end;

function Chain(Count: Integer): UInt64; assembler; nostackframe;
asm
    {$ifndef MSWINDOWS}
    mov ecx, edi
    {$endif}
    xor eax, eax
    align 64
@loop:
    add rax, 1
    add rax, 1
    add rax, 1
    add rax, 1
    add rax, 1
    add rax, 1
    add rax, 1
    add rax, 1
    sub ecx, 1
    jnz @loop
end;

// Win64: rcx = dest, rdx = bytes, r8 = repeat count, r9 = mode
procedure Fill(Dest: Pointer; Bytes, Count, Mode: PtrUInt); assembler; nostackframe;
asm
    {$ifndef MSWINDOWS}
    mov r9, rcx
    mov rcx, rdi
    mov r8, rdx
    mov rdx, rsi
    {$endif}
    push rdi
    mov r10, rcx        // dest
    mov r11, rdx        // bytes
    pxor xmm0, xmm0
    cmp r9, 1
    je @stosq
    cmp r9, 2
    je @stosb
    cmp r9, 3
    je @sse16
    cmp r9, 4
    je @sse32
    cmp r9, 5
    je @sse64
    align 32
@stosd:
    mov rdi, r10
    mov rcx, r11
    shr rcx, 2
    xor eax, eax
    rep stosd
    sub r8, 1
    jnz @stosd
    jmp @done
    align 32
@stosq:
    mov rdi, r10
    mov rcx, r11
    shr rcx, 3
    xor eax, eax
    rep stosq
    sub r8, 1
    jnz @stosq
    jmp @done
    align 32
@stosb:
    mov rdi, r10
    mov rcx, r11
    xor eax, eax
    rep stosb
    sub r8, 1
    jnz @stosb
    jmp @done
    align 32
@sse16:
    lea rdx, [r10 + r11]
    mov rax, r11
    neg rax
    align 16
@l16:
    movaps oword ptr [rdx + rax], xmm0
    add rax, 16
    js @l16
    sub r8, 1
    jnz @sse16
    jmp @done
    align 32
@sse32:
    lea rdx, [r10 + r11]
    mov rax, r11
    neg rax
    align 16
@l32:
    movaps oword ptr [rdx + rax], xmm0
    movaps oword ptr [rdx + rax + 16], xmm0
    add rax, 32
    js @l32
    sub r8, 1
    jnz @sse32
    jmp @done
    align 32
@sse64:
    lea rdx, [r10 + r11]
    mov rax, r11
    neg rax
    align 16
@l64:
    movaps oword ptr [rdx + rax], xmm0
    movaps oword ptr [rdx + rax + 16], xmm0
    movaps oword ptr [rdx + rax + 32], xmm0
    movaps oword ptr [rdx + rax + 48], xmm0
    add rax, 64
    js @l64
    sub r8, 1
    jnz @sse64
@done:
    pop rdi
end;

const
  Reps = 100000;
  Names: array[0..5] of string = ('stosd', 'stosq', 'stosb', 'sse16', 'sse32', 'sse64');
var
  Buf, Base: PByte;
  Size, O, S, M: Integer;
  T0, T1, Best: UInt64;
  Scale, V, Lo, Hi: Double;
  Sum: UInt64;
  Line: string;
begin
  {$ifdef MSWINDOWS}
  If ParamCount >= 1 then
    SetThreadAffinityMask(GetCurrentThread, PtrUInt(1) shl StrToInt(ParamStr(1)));
  {$endif}
  GetMem(Buf, 1 shl 20);
  FillChar(Buf^, 1 shl 20, 1);
  Base := PByte((PtrUInt(Buf) + 8192) and not PtrUInt(4095));
  Sum := 0;
  Line := 'bytes ';
  for M := 0 to 5 do
    Line := Line + Format('  %5s best..worst', [Names[M]]);
  WriteLn(Line);
  Size := 256;
  while Size <= 2304 do
  begin
    Line := Format('%5d ', [Size]);
    for M := 0 to 5 do
    begin
      Lo := 1e30;
      Hi := 0;
      for O := 0 to 3 do
      begin
        Best := High(UInt64);
        for S := 1 to 5 do
        begin
          T0 := Rdtsc;
          Sum := Sum + Chain(500000);
          T1 := Rdtsc;
          If T1 - T0 < Best then
            Best := T1 - T0;
        end;
        Scale := Best / (500000.0 * 8.0);
        Best := High(UInt64);
        for S := 1 to 5 do
        begin
          T0 := Rdtsc;
          Fill(Base + O * 16, Size, Reps, M);
          T1 := Rdtsc;
          If T1 - T0 < Best then
            Best := T1 - T0;
        end;
        V := Best / (Reps * 1.0) / Scale;
        If V < Lo then
          Lo := V;
        If V > Hi then
          Hi := V;
      end;
      Line := Line + Format('  %8.1f..%-7.1f', [Lo, Hi]);
    end;
    WriteLn(Line);
    Inc(Size, 128);
  end;
  If Sum = 0 then
    WriteLn('impossible');
end.
