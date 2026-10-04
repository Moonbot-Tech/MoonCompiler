program copy_map;
{$mode delphi}{$H+}{$asmmode intel}
{ Map of the cost of copying N bytes between two 16-byte aligned blocks: rep movsb (what _ReallocMem does from
  256 bytes on) against SSE2 loops of 16 and 32 bytes per iteration; best and worst of four alignments. }
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

// Win64: rcx = dest, rdx = source, r8 = bytes, r9 = mode (0 movsb, 1 sse16, 2 sse32); 20000 repeats
procedure Copy(Dest, Source: Pointer; Bytes, Mode: PtrUInt); assembler; nostackframe;
asm
    {$ifndef MSWINDOWS}
    mov r9, rcx
    mov r8, rdx
    mov rcx, rdi
    mov rdx, rsi
    {$endif}
    push rdi
    push rsi
    mov r10, rcx
    mov r11, rdx
    mov eax, 20000
    cmp r9, 1
    je @sse16
    cmp r9, 2
    je @sse32
    align 32
@movsb:
    mov rdi, r10
    mov rsi, r11
    mov rcx, r8
    rep movsb
    sub eax, 1
    jnz @movsb
    jmp @done
    align 32
@sse16:
    lea rcx, [r11 + r8]
    lea rdx, [r10 + r8]
    mov r9, r8
    neg r9
    align 16
@l16:
    movaps xmm0, oword ptr [rcx + r9]
    movaps oword ptr [rdx + r9], xmm0
    add r9, 16
    js @l16
    sub eax, 1
    jnz @sse16
    jmp @done
    align 32
@sse32:
    lea rcx, [r11 + r8]
    lea rdx, [r10 + r8]
    mov r9, r8
    neg r9
    align 16
@l32:
    movaps xmm0, oword ptr [rcx + r9]
    movaps xmm1, oword ptr [rcx + r9 + 16]
    movaps oword ptr [rdx + r9], xmm0
    movaps oword ptr [rdx + r9 + 16], xmm1
    add r9, 32
    js @l32
    sub eax, 1
    jnz @sse32
@done:
    pop rsi
    pop rdi
end;

const
  Names: array[0..2] of string = ('movsb', 'sse16', 'sse32');
var
  Buf, Src, Dst: PByte;
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
  Src := PByte((PtrUInt(Buf) + 8192) and not PtrUInt(4095));
  Dst := Src + 65536 + 1024;
  Sum := 0;
  Line := 'bytes ';
  for M := 0 to 2 do
    Line := Line + Format('  %5s best..worst', [Names[M]]);
  WriteLn(Line);
  Size := 256;
  while Size <= 4096 do
  begin
    Line := Format('%5d ', [Size]);
    for M := 0 to 2 do
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
          Copy(Dst + O * 16, Src + ((O * 3) and 3) * 16, Size, M);
          T1 := Rdtsc;
          If T1 - T0 < Best then
            Best := T1 - T0;
        end;
        V := Best / 20000.0 / Scale;
        If V < Lo then
          Lo := V;
        If V > Hi then
          Hi := V;
      end;
      Line := Line + Format('  %8.1f..%-7.1f', [Lo, Hi]);
    end;
    WriteLn(Line);
    If Size < 2048 then
      Inc(Size, 256)
    else
      Inc(Size, 1024);
  end;
  If Sum = 0 then
    WriteLn('impossible');
end.
