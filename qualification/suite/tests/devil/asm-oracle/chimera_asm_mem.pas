unit chimera_asm_mem;

{ Орган «паскаль против ассемблера»: работа с памятью.

  Тот же порядок, что и у целых чисел: считает паскаль, ассемблер держит
  эталон. Здесь предмет — обход буфера: границы, перекрытия, направление
  прохода и ранний выход.

  Именно на таких формах оптимизатор делает больше всего: разворачивает
  циклы, объединяет чтения в широкие, выносит проверки из тела. Каждое из
  этих преобразований имеет свой способ ошибиться на краю буфера — потому
  длины здесь перебираются подряд, а не берутся круглыми. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch INLINEVARS}
  {$asmmode intel}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, chimera_body;

function ChiAsmMemRun: Int64;

implementation

const
  IdMem = 'CHI-ASM-MEM-001';

{ ═══ 1. Сравнение блоков ═════════════════════════════════════════════════ }

function CompareBlockPas(A, B: PByte; N: Integer): Integer;
begin
  for var I := 0 to N - 1 do
    if A[I] <> B[I] then
    begin
      if A[I] < B[I] then Exit(-1) else Exit(1);
    end;
  Result := 0;
end;

function CompareBlockAsm(A, B: PByte; N: Integer): Integer; assembler; nostackframe;
asm
{$ifdef UNIX}
        { В соглашении Unix целочисленные доводы едут в RDI, RSI, RDX, RCX, а в
          соглашении Windows — в RCX, RDX, R8, R9. Переставляем их в порядке от
          последнего к первому, чтобы ни один источник не был затёрт до чтения. }
        mov     r9, rcx
        mov     r8, rdx
        mov     rdx, rsi
        mov     rcx, rdi
{$endif}
        xor     eax, eax
        test    r8d, r8d
        jle     @@done
        movsxd  r8, r8d
@@loop: movzx   r9d, byte ptr [rcx]
        movzx   r10d, byte ptr [rdx]
        cmp     r9d, r10d
        je      @@next
        mov     eax, 1
        ja      @@done
        mov     eax, -1
        jmp     @@done
@@next: inc     rcx
        inc     rdx
        dec     r8
        jnz     @@loop
@@done:
end;

{ ═══ 2. Поиск байта ══════════════════════════════════════════════════════ }

function IndexOfBytePas(P: PByte; N: Integer; V: Byte): Integer;
begin
  for var I := 0 to N - 1 do
    if P[I] = V then Exit(I);
  Result := -1;
end;

function IndexOfByteAsm(P: PByte; N: Integer; V: Byte): Integer; assembler; nostackframe;
asm
{$ifdef UNIX}
        { В соглашении Unix целочисленные доводы едут в RDI, RSI, RDX, RCX, а в
          соглашении Windows — в RCX, RDX, R8, R9. Переставляем их в порядке от
          последнего к первому, чтобы ни один источник не был затёрт до чтения. }
        mov     r9, rcx
        mov     r8, rdx
        mov     rdx, rsi
        mov     rcx, rdi
{$endif}
        mov     eax, -1
        test    edx, edx
        jle     @@done
        movsxd  rdx, edx
        xor     r9, r9
        movzx   r8d, r8b
@@loop: movzx   r10d, byte ptr [rcx + r9]
        cmp     r10d, r8d
        je      @@found
        inc     r9
        dec     rdx
        jnz     @@loop
        jmp     @@done
@@found:
        mov     rax, r9
@@done:
end;

{ ═══ 3. Счёт вхождений байта ═════════════════════════════════════════════ }

function CountBytePas(P: PByte; N: Integer; V: Byte): Integer;
begin
  Result := 0;
  for var I := 0 to N - 1 do
    if P[I] = V then Inc(Result);
end;

function CountByteAsm(P: PByte; N: Integer; V: Byte): Integer; assembler; nostackframe;
asm
{$ifdef UNIX}
        { В соглашении Unix целочисленные доводы едут в RDI, RSI, RDX, RCX, а в
          соглашении Windows — в RCX, RDX, R8, R9. Переставляем их в порядке от
          последнего к первому, чтобы ни один источник не был затёрт до чтения. }
        mov     r9, rcx
        mov     r8, rdx
        mov     rdx, rsi
        mov     rcx, rdi
{$endif}
        xor     eax, eax
        test    edx, edx
        jle     @@done
        movsxd  rdx, edx
        movzx   r8d, r8b
@@loop: movzx   r10d, byte ptr [rcx]
        cmp     r10d, r8d
        jne     @@next
        inc     eax
@@next: inc     rcx
        dec     rdx
        jnz     @@loop
@@done:
end;

{ ═══ 4. Перенос с перекрытием ════════════════════════════════════════════ }

{ Направление обхода решает всё: при налегании справа копировать нужно с
  конца, иначе хвост затрёт то, что ещё не прочитано. }
procedure MoveOverlapPas(Src, Dst: PByte; N: Integer);
begin
  if Dst <= Src then
    for var I := 0 to N - 1 do Dst[I] := Src[I]
  else
    for var I := N - 1 downto 0 do Dst[I] := Src[I];
end;

procedure MoveOverlapAsm(Src, Dst: PByte; N: Integer); assembler; nostackframe;
asm
{$ifdef UNIX}
        { В соглашении Unix целочисленные доводы едут в RDI, RSI, RDX, RCX, а в
          соглашении Windows — в RCX, RDX, R8, R9. Переставляем их в порядке от
          последнего к первому, чтобы ни один источник не был затёрт до чтения. }
        mov     r9, rcx
        mov     r8, rdx
        mov     rdx, rsi
        mov     rcx, rdi
{$endif}
        test    r8d, r8d
        jle     @@done
        movsxd  r8, r8d
        cmp     rdx, rcx
        ja      @@back
@@fwd:  movzx   r9d, byte ptr [rcx]
        mov     byte ptr [rdx], r9b
        inc     rcx
        inc     rdx
        dec     r8
        jnz     @@fwd
        jmp     @@done
@@back: mov     r10, r8
        dec     r10
@@bloop:movzx   r9d, byte ptr [rcx + r10]
        mov     byte ptr [rdx + r10], r9b
        dec     r10
        jns     @@bloop
@@done:
end;

{ ═══ 5. Заполнение ═══════════════════════════════════════════════════════ }

procedure FillBlockPas(P: PByte; N: Integer; V: Byte);
begin
  for var I := 0 to N - 1 do P[I] := V;
end;

procedure FillBlockAsm(P: PByte; N: Integer; V: Byte); assembler; nostackframe;
asm
{$ifdef UNIX}
        { В соглашении Unix целочисленные доводы едут в RDI, RSI, RDX, RCX, а в
          соглашении Windows — в RCX, RDX, R8, R9. Переставляем их в порядке от
          последнего к первому, чтобы ни один источник не был затёрт до чтения. }
        mov     r9, rcx
        mov     r8, rdx
        mov     rdx, rsi
        mov     rcx, rdi
{$endif}
        test    edx, edx
        jle     @@done
        movsxd  rdx, edx
@@loop: mov     byte ptr [rcx], r8b
        inc     rcx
        dec     rdx
        jnz     @@loop
@@done:
end;

{ ═══ 6. Разворот блока ═══════════════════════════════════════════════════ }

procedure ReverseBlockPas(P: PByte; N: Integer);
var
  T: Byte;
begin
  var L := 0;
  var R := N - 1;
  while L < R do
  begin
    T := P[L];
    P[L] := P[R];
    P[R] := T;
    Inc(L);
    Dec(R);
  end;
end;

procedure ReverseBlockAsm(P: PByte; N: Integer); assembler; nostackframe;
asm
{$ifdef UNIX}
        { В соглашении Unix целочисленные доводы едут в RDI, RSI, RDX, RCX, а в
          соглашении Windows — в RCX, RDX, R8, R9. Переставляем их в порядке от
          последнего к первому, чтобы ни один источник не был затёрт до чтения. }
        mov     r9, rcx
        mov     r8, rdx
        mov     rdx, rsi
        mov     rcx, rdi
{$endif}
        test    edx, edx
        jle     @@done
        movsxd  rdx, edx
        xor     r8, r8           // левый
        mov     r9, rdx
        dec     r9               // правый
@@loop: cmp     r8, r9
        jge     @@done
        movzx   r10d, byte ptr [rcx + r8]
        movzx   r11d, byte ptr [rcx + r9]
        mov     byte ptr [rcx + r8], r11b
        mov     byte ptr [rcx + r9], r10b
        inc     r8
        dec     r9
        jmp     @@loop
@@done:
end;

{ ═══ 7. Сложение по модулю два ═══════════════════════════════════════════ }

procedure XorBlockPas(Dst, Src: PByte; N: Integer);
begin
  for var I := 0 to N - 1 do Dst[I] := Dst[I] xor Src[I];
end;

procedure XorBlockAsm(Dst, Src: PByte; N: Integer); assembler; nostackframe;
asm
{$ifdef UNIX}
        { В соглашении Unix целочисленные доводы едут в RDI, RSI, RDX, RCX, а в
          соглашении Windows — в RCX, RDX, R8, R9. Переставляем их в порядке от
          последнего к первому, чтобы ни один источник не был затёрт до чтения. }
        mov     r9, rcx
        mov     r8, rdx
        mov     rdx, rsi
        mov     rcx, rdi
{$endif}
        test    r8d, r8d
        jle     @@done
        movsxd  r8, r8d
@@loop: movzx   r9d, byte ptr [rdx]
        movzx   r10d, byte ptr [rcx]
        xor     r10d, r9d
        mov     byte ptr [rcx], r10b
        inc     rcx
        inc     rdx
        dec     r8
        jnz     @@loop
@@done:
end;

{ ═══ 8. Поиск подстроки ══════════════════════════════════════════════════ }

function FindSubPas(Hay: PByte; HayLen: Integer; Needle: PByte; NeedleLen: Integer): Integer;
begin
  if (NeedleLen = 0) or (NeedleLen > HayLen) then Exit(-1);
  for var I := 0 to HayLen - NeedleLen do
  begin
    var Ok := True;
    for var J := 0 to NeedleLen - 1 do
      if Hay[I + J] <> Needle[J] then
      begin
        Ok := False;
        Break;
      end;
    if Ok then Exit(I);
  end;
  Result := -1;
end;

function FindSubAsm(Hay: PByte; HayLen: Integer; Needle: PByte; NeedleLen: Integer): Integer;
  assembler; nostackframe;
asm
{$ifdef UNIX}
        { В соглашении Unix целочисленные доводы едут в RDI, RSI, RDX, RCX, а в
          соглашении Windows — в RCX, RDX, R8, R9. Переставляем их в порядке от
          последнего к первому, чтобы ни один источник не был затёрт до чтения. }
        mov     r9, rcx
        mov     r8, rdx
        mov     rdx, rsi
        mov     rcx, rdi
{$endif}
        mov     eax, -1
        test    r9d, r9d
        jle     @@done
        cmp     r9d, edx
        jg      @@done
        movsxd  rdx, edx
        movsxd  r9, r9d
        sub     rdx, r9          // последняя допустимая позиция
        xor     r10, r10         // позиция в стоге
@@outer:xor     r11, r11         // смещение внутри иглы
@@inner:cmp     r11, r9
        jge     @@found
        mov     al, byte ptr [rcx + r11]
        cmp     al, byte ptr [r8 + r11]
        jne     @@next
        inc     r11
        jmp     @@inner
@@next: inc     rcx
        inc     r10
        cmp     r10, rdx
        jle     @@outer
        mov     eax, -1
        jmp     @@done
@@found:mov     rax, r10
@@done:
end;

{ ═══ 9. Сумма байтов как чисел ═══════════════════════════════════════════ }

function SumBytesPas(P: PByte; N: Integer): Int64;
begin
  Result := 0;
  for var I := 0 to N - 1 do Inc(Result, P[I]);
end;

function SumBytesAsm(P: PByte; N: Integer): Int64; assembler; nostackframe;
asm
{$ifdef UNIX}
        { В соглашении Unix целочисленные доводы едут в RDI, RSI, RDX, RCX, а в
          соглашении Windows — в RCX, RDX, R8, R9. Переставляем их в порядке от
          последнего к первому, чтобы ни один источник не был затёрт до чтения. }
        mov     r9, rcx
        mov     r8, rdx
        mov     rdx, rsi
        mov     rcx, rdi
{$endif}
        xor     rax, rax
        test    edx, edx
        jle     @@done
        movsxd  rdx, edx
@@loop: movzx   r8d, byte ptr [rcx]
        add     rax, r8
        inc     rcx
        dec     rdx
        jnz     @@loop
@@done:
end;

{ ═══ 10. Проверка на нулевой блок ════════════════════════════════════════ }

function IsZeroPas(P: PByte; N: Integer): Boolean;
begin
  for var I := 0 to N - 1 do
    if P[I] <> 0 then Exit(False);
  Result := True;
end;

function IsZeroAsm(P: PByte; N: Integer): Boolean; assembler; nostackframe;
asm
{$ifdef UNIX}
        { В соглашении Unix целочисленные доводы едут в RDI, RSI, RDX, RCX, а в
          соглашении Windows — в RCX, RDX, R8, R9. Переставляем их в порядке от
          последнего к первому, чтобы ни один источник не был затёрт до чтения. }
        mov     r9, rcx
        mov     r8, rdx
        mov     rdx, rsi
        mov     rcx, rdi
{$endif}
        mov     eax, 1
        test    edx, edx
        jle     @@done
        movsxd  rdx, edx
@@loop: cmp     byte ptr [rcx], 0
        jne     @@nonzero
        inc     rcx
        dec     rdx
        jnz     @@loop
        jmp     @@done
@@nonzero:
        xor     eax, eax
@@done:
end;

{ ═══ Прогон ══════════════════════════════════════════════════════════════ }

function ChiAsmMemRun: Int64;
var
  Acc:   UInt64;
  Src:   TChiSource;
  A, B:  array [0 .. 511] of Byte;
  C, D:  array [0 .. 511] of Byte;
  Orig:  array [0 .. 511] of Byte;
  Sign:  Integer;
begin
  Acc := 0;
  ChiCovered(IdMem);
  Src := ChiSource(31415926);

  { ── Сравнение блоков: длины перебираются ПОДРЯД, а не круглыми ── }
  for var N := 0 to 64 do
  begin
    for var I := 0 to 511 do
    begin
      A[I] := Byte(Src.NextBelow(4));
      B[I] := A[I];
    end;
    ChiClaim(CompareBlockPas(@A[0], @B[0], N) = CompareBlockAsm(@A[0], @B[0], N),
      'сравнение: равные блоки разошлись на длине ' + IntToStr(N));
    if N > 0 then
    begin
      var At := Src.NextBelow(N);
      B[At] := A[At] xor $80;
      Sign := CompareBlockPas(@A[0], @B[0], N);
      ChiClaim(Sign = CompareBlockAsm(@A[0], @B[0], N),
        'сравнение: разные блоки разошлись на длине ' + IntToStr(N));
      ChiClaim(Sign <> 0, 'сравнение: правка не замечена');
      ChiClaim(CompareBlockAsm(@B[0], @A[0], N) = -Sign,
        'сравнение: перемена сторон не поменяла знак');
    end;
  end;
  ChiBranch(IdMem, 'compare');
  ChiClaim(CompareBlockAsm(@A[0], @B[0], 0) = 0, 'сравнение: пустые блоки не равны');
  ChiBranch(IdMem, 'compare-empty');

  { ── Поиск и счёт байта ── }
  for var Round := 1 to 40 do
  begin
    var N := 1 + Src.NextBelow(511);
    for var I := 0 to N - 1 do A[I] := Byte(Src.NextBelow(6));
    var V := Byte(Src.NextBelow(8));
    ChiClaim(IndexOfBytePas(@A[0], N, V) = IndexOfByteAsm(@A[0], N, V),
      'поиск байта: разошлись');
    ChiClaim(CountBytePas(@A[0], N, V) = CountByteAsm(@A[0], N, V),
      'счёт байта: разошлись');
    var At := IndexOfByteAsm(@A[0], N, V);
    if At >= 0 then
      ChiClaim(A[At] = V, 'поиск байта: нашёлся не тот байт');
    Acc := ChiMix(Acc, CountByteAsm(@A[0], N, V));
  end;
  { Байт в самом начале, в самом конце и отсутствующий. }
  FillChar(A, SizeOf(A), 1);
  A[0] := 9;
  ChiClaim(IndexOfByteAsm(@A[0], 100, 9) = 0, 'поиск байта: первый не найден');
  A[0] := 1;
  A[99] := 9;
  ChiClaim(IndexOfByteAsm(@A[0], 100, 9) = 99, 'поиск байта: последний не найден');
  ChiClaim(IndexOfByteAsm(@A[0], 99, 9) = -1, 'поиск байта: нашёл за границей');
  ChiClaim(IndexOfByteAsm(@A[0], 100, 7) = -1, 'поиск байта: нашёл несуществующий');
  ChiBranch(IdMem, 'find-count');

  { ── Перенос с перекрытием: обе стороны налегания ── }
  for var Shift := 1 to 16 do
  begin
    for var I := 0 to 255 do A[I] := Byte(I);
    Move(A[0], C[0], 256);
    { налегание слева: пишем назад }
    MoveOverlapPas(@A[Shift], @A[0], 200);
    MoveOverlapAsm(@C[Shift], @C[0], 200);
    ChiClaim(CompareMem(@A[0], @C[0], 256), 'перенос: налегание слева разошлось');

    for var I := 0 to 255 do A[I] := Byte(I * 3);
    Move(A[0], C[0], 256);
    { налегание справа: пишем с конца }
    MoveOverlapPas(@A[0], @A[Shift], 200);
    MoveOverlapAsm(@C[0], @C[Shift], 200);
    ChiClaim(CompareMem(@A[0], @C[0], 256), 'перенос: налегание справа разошлось');
  end;
  { Полное совпадение источника и приёмника — перенос обязан ничего не менять. }
  for var I := 0 to 255 do A[I] := Byte(I * 5);
  Move(A[0], C[0], 256);
  MoveOverlapAsm(@A[0], @A[0], 256);
  ChiClaim(CompareMem(@A[0], @C[0], 256), 'перенос: сам в себя испортил данные');
  ChiBranch(IdMem, 'move-overlap');

  { ── Заполнение и проверка на ноль ── }
  for var N := 0 to 64 do
  begin
    FillChar(A, SizeOf(A), $AA);
    FillChar(C, SizeOf(C), $AA);
    FillBlockPas(@A[0], N, $5C);
    FillBlockAsm(@C[0], N, $5C);
    ChiClaim(CompareMem(@A[0], @C[0], SizeOf(A)),
      'заполнение: разошлось на длине ' + IntToStr(N));
    if N < SizeOf(A) then
      ChiClaim(A[N] = $AA, 'заполнение: вышло за длину');
    ChiClaim(IsZeroPas(@A[0], N) = IsZeroAsm(@A[0], N), 'проверка нуля: разошлись');
  end;
  FillChar(A, SizeOf(A), 0);
  ChiClaim(IsZeroAsm(@A[0], 512), 'проверка нуля: нулевой блок не признан');
  A[511] := 1;
  ChiClaim(not IsZeroAsm(@A[0], 512), 'проверка нуля: единица в хвосте не замечена');
  ChiClaim(IsZeroAsm(@A[0], 511), 'проверка нуля: заглянул за длину');
  ChiClaim(IsZeroAsm(@A[0], 0), 'проверка нуля: пустой блок не признан нулевым');
  ChiBranch(IdMem, 'fill-iszero');

  { ── Разворот блока: чётные и нечётные длины ── }
  for var N := 0 to 65 do
  begin
    for var I := 0 to N - 1 do
    begin
      A[I] := Byte(I * 7 + 1);
      C[I] := A[I];
    end;
    ReverseBlockPas(@A[0], N);
    ReverseBlockAsm(@C[0], N);
    ChiClaim(CompareMem(@A[0], @C[0], N),
      'разворот: разошёлся на длине ' + IntToStr(N));
    ReverseBlockAsm(@C[0], N);
    for var I := 0 to N - 1 do
      ChiClaim(C[I] = Byte(I * 7 + 1), 'разворот: дважды не вернул исходное');
  end;
  ChiBranch(IdMem, 'reverse');

  { ── Сложение по модулю два ── }
  for var Round := 1 to 30 do
  begin
    var N := 1 + Src.NextBelow(511);
    for var I := 0 to N - 1 do
    begin
      A[I] := Byte(Src.NextBelow(256));
      B[I] := Byte(Src.NextBelow(256));
      C[I] := A[I];
      D[I] := B[I];
      Orig[I] := A[I];
    end;
    XorBlockPas(@A[0], @B[0], N);
    XorBlockAsm(@C[0], @D[0], N);
    ChiClaim(CompareMem(@A[0], @C[0], N), 'сложение по модулю два: разошлось');
    { дважды подряд возвращает исходное — сверяем с сохранённым до правки }
    XorBlockAsm(@C[0], @D[0], N);
    ChiClaim(CompareMem(@C[0], @Orig[0], N), 'сложение по модулю два: не обратимо');
    Acc := ChiMix(Acc, SumBytesAsm(@A[0], N));
  end;
  ChiBranch(IdMem, 'xor-block');

  { ── Сумма байтов ── }
  for var Round := 1 to 30 do
  begin
    var N := 1 + Src.NextBelow(511);
    for var I := 0 to N - 1 do A[I] := Byte(Src.NextBelow(256));
    ChiClaim(SumBytesPas(@A[0], N) = SumBytesAsm(@A[0], N), 'сумма байтов: разошлись');
  end;
  FillChar(A, SizeOf(A), $FF);
  ChiClaim(SumBytesAsm(@A[0], 512) = 512 * 255, 'сумма байтов: предел не сошёлся');
  ChiBranch(IdMem, 'sum-bytes');

  { ── Поиск подстроки ── }
  for var Round := 1 to 40 do
  begin
    var N := 8 + Src.NextBelow(400);
    for var I := 0 to N - 1 do A[I] := Byte(Src.NextBelow(4));
    var M := 1 + Src.NextBelow(6);
    for var I := 0 to M - 1 do B[I] := Byte(Src.NextBelow(4));
    ChiClaim(FindSubPas(@A[0], N, @B[0], M) = FindSubAsm(@A[0], N, @B[0], M),
      'поиск подстроки: разошлись');
    { игла, заведомо лежащая в стоге }
    var At := Src.NextBelow(N - M);
    Move(A[At], B[0], M);
    var R1 := FindSubPas(@A[0], N, @B[0], M);
    ChiClaim(R1 = FindSubAsm(@A[0], N, @B[0], M), 'поиск подстроки: заложенная разошлась');
    ChiClaim((R1 >= 0) and (R1 <= At), 'поиск подстроки: заложенная не найдена');
    Acc := ChiMix(Acc, R1);
  end;
  { края: игла длиннее стога, пустая игла, игла в самом конце }
  ChiClaim(FindSubAsm(@A[0], 3, @B[0], 5) = -1, 'поиск подстроки: длиннее стога');
  ChiClaim(FindSubAsm(@A[0], 10, @B[0], 0) = -1, 'поиск подстроки: пустая игла');
  for var I := 0 to 9 do A[I] := Byte(I);
  B[0] := 8; B[1] := 9;
  ChiClaim(FindSubAsm(@A[0], 10, @B[0], 2) = 8, 'поиск подстроки: хвост не найден');
  ChiClaim(FindSubAsm(@A[0], 9, @B[0], 2) = -1, 'поиск подстроки: нашёл за границей');
  B[0] := 0; B[1] := 1;
  ChiClaim(FindSubAsm(@A[0], 10, @B[0], 2) = 0, 'поиск подстроки: голова не найдена');
  ChiBranch(IdMem, 'find-substring');
  Acc := ChiMix(Acc, SumBytesAsm(@A[0], 512));

  Result := Int64(Acc and $7FFFFFFFFFFF);
end;

end.
