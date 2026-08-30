unit chimera_asm_float;

{ Орган «паскаль против ассемблера»: дробные числа.

  Здесь сравнение строже, чем везде: требуется совпадение ДО БИТА, а не с
  допуском. Допуск в таком тесте был бы подменой предмета — мы проверяем не
  «примерно то же число», а то, что компилятор не переставил действия местами
  и не свернул умножение со сложением в одну команду там, где порядок
  зафиксирован исходником.

  Поэтому паскальная сторона написана так, чтобы порядок был однозначен:
  накопитель обновляется по одному слагаемому за раз, промежуточные величины
  не выносятся. Ассемблерная сторона выполняет ровно те же действия в том же
  порядке командами `addsd`/`mulsd`.

  Расхождение здесь — не обязательно дефект: язык местами разрешает вольности.
  Но каждая такая вольность обязана быть названной, а не молчаливой. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch INLINEVARS}
  {$asmmode intel}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, Math, chimera_body;

function ChiAsmFloatRun: Int64;

implementation

const
  IdFloat = 'CHI-ASM-FLOAT-001';

{ ═══ 1. Сумма подряд ═════════════════════════════════════════════════════ }

function SumPas(P: PDouble; N: Integer): Double;
begin
  Result := 0;
  for var I := 0 to N - 1 do
    Result := Result + P[I];
end;

function SumAsm(P: PDouble; N: Integer): Double; assembler; nostackframe;
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
        xorpd   xmm0, xmm0
        test    edx, edx
        jle     @@done
        movsxd  rdx, edx
@@loop: addsd   xmm0, qword ptr [rcx]
        add     rcx, 8
        dec     rdx
        jnz     @@loop
@@done:
end;

{ ═══ 2. Скалярное произведение ═══════════════════════════════════════════ }

function DotPas(A, B: PDouble; N: Integer): Double;
begin
  Result := 0;
  for var I := 0 to N - 1 do
    Result := Result + A[I] * B[I];
end;

function DotAsm(A, B: PDouble; N: Integer): Double; assembler; nostackframe;
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
        xorpd   xmm0, xmm0
        test    r8d, r8d
        jle     @@done
        movsxd  r8, r8d
@@loop: movq   xmm1, qword ptr [rcx]
        mulsd   xmm1, qword ptr [rdx]
        addsd   xmm0, xmm1
        add     rcx, 8
        add     rdx, 8
        dec     r8
        jnz     @@loop
@@done:
end;

{ ═══ 3. Сумма квадратов ══════════════════════════════════════════════════ }

function SumSqPas(P: PDouble; N: Integer): Double;
begin
  Result := 0;
  for var I := 0 to N - 1 do
    Result := Result + P[I] * P[I];
end;

function SumSqAsm(P: PDouble; N: Integer): Double; assembler; nostackframe;
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
        xorpd   xmm0, xmm0
        test    edx, edx
        jle     @@done
        movsxd  rdx, edx
@@loop: movq   xmm1, qword ptr [rcx]
        mulsd   xmm1, xmm1
        addsd   xmm0, xmm1
        add     rcx, 8
        dec     rdx
        jnz     @@loop
@@done:
end;

{ ═══ 4. Наибольшее и наименьшее ══════════════════════════════════════════ }

function MaxPas(P: PDouble; N: Integer): Double;
begin
  Result := P[0];
  for var I := 1 to N - 1 do
    if P[I] > Result then Result := P[I];
end;

function MaxAsm(P: PDouble; N: Integer): Double; assembler; nostackframe;
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
        movq   xmm0, qword ptr [rcx]
        movsxd  rdx, edx
        dec     rdx
        jle     @@done
@@loop: add     rcx, 8
        movq   xmm1, qword ptr [rcx]
        comisd  xmm1, xmm0
        jbe     @@next
        movsd   xmm0, xmm1
@@next: dec     rdx
        jnz     @@loop
@@done:
end;

{ ═══ 5. Скользящее среднее ═══════════════════════════════════════════════ }

{ Форма из живого кода: старое значение весит девяносто девять сотых. }
function SmoothPas(P: PDouble; N: Integer): Double;
begin
  Result := P[0];
  for var I := 1 to N - 1 do
    Result := (Result * 99 + P[I]) / 100;
end;

function SmoothAsm(P: PDouble; N: Integer): Double; assembler; nostackframe;
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
        movq   xmm0, qword ptr [rcx]
        movsxd  rdx, edx
        dec     rdx
        jle     @@done
        mov     rax, $4058C00000000000     // 99.0
        movq    xmm2, rax
        mov     rax, $4059000000000000     // 100.0
        movq    xmm3, rax
@@loop: add     rcx, 8
        mulsd   xmm0, xmm2
        addsd   xmm0, qword ptr [rcx]
        divsd   xmm0, xmm3
        dec     rdx
        jnz     @@loop
@@done:
end;

{ ═══ 6. Свёртка с окном ══════════════════════════════════════════════════ }

function ConvPas(P, W: PDouble; N, M: Integer): Double;
begin
  Result := 0;
  for var I := 0 to N - M do
  begin
    var S: Double := 0;
    for var J := 0 to M - 1 do
      S := S + P[I + J] * W[J];
    Result := Result + S;
  end;
end;

function ConvAsm(P, W: PDouble; N, M: Integer): Double; assembler; nostackframe;
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
        xorpd   xmm0, xmm0
        movsxd  r8, r8d
        movsxd  r9, r9d
        sub     r8, r9           // число положений окна минус один
        js      @@done
@@outer:xorpd   xmm2, xmm2       // накопитель окна
        xor     r10, r10
@@inner:cmp     r10, r9
        jge     @@fold
        mov     r11, r10
        shl     r11, 3
        movq   xmm1, qword ptr [rcx + r11]
        mulsd   xmm1, qword ptr [rdx + r11]
        addsd   xmm2, xmm1
        inc     r10
        jmp     @@inner
@@fold: addsd   xmm0, xmm2
        add     rcx, 8
        dec     r8
        jns     @@outer
@@done:
end;

{ ═══ 7. Умножение комплексных чисел ══════════════════════════════════════ }

{ Доводы едут парами через память: в соглашении Windows пятый и последующие
  доводы лежат в стеке, и брать их из регистров было бы ошибкой. }
procedure MulComplexPas(A, B, C: PDouble);
begin
  C[0] := A[0] * B[0] - A[1] * B[1];
  C[1] := A[0] * B[1] + A[1] * B[0];
end;

procedure MulComplexAsm(A, B, C: PDouble); assembler; nostackframe;
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
        movq   xmm0, qword ptr [rcx]        // AR
        movq   xmm1, qword ptr [rcx + 8]    // AI
        movq   xmm2, qword ptr [rdx]        // BR
        movq   xmm3, qword ptr [rdx + 8]    // BI
        movsd   xmm4, xmm0
        mulsd   xmm4, xmm2                   // AR*BR
        movsd   xmm5, xmm1
        mulsd   xmm5, xmm3                   // AI*BI
        subsd   xmm4, xmm5
        movq   qword ptr [r8], xmm4
        movsd   xmm4, xmm0
        mulsd   xmm4, xmm3                   // AR*BI
        movsd   xmm5, xmm1
        mulsd   xmm5, xmm2                   // AI*BR
        addsd   xmm4, xmm5
        movq   qword ptr [r8 + 8], xmm4
end;

{ ═══ 8. Компенсированная сумма ═══════════════════════════════════════════ }

{ Складывает так, чтобы потерянные младшие разряды возвращались обратно.
  Форма чувствительна к любому переупорядочиванию: стоит поменять порядок
  вычитаний — и поправка перестаёт работать. }
function KahanPas(P: PDouble; N: Integer): Double;
var
  C, Y, T: Double;
begin
  Result := 0;
  C := 0;
  for var I := 0 to N - 1 do
  begin
    Y := P[I] - C;
    T := Result + Y;
    C := (T - Result) - Y;
    Result := T;
  end;
end;

function KahanAsm(P: PDouble; N: Integer): Double; assembler; nostackframe;
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
        xorpd   xmm0, xmm0       // сумма
        xorpd   xmm3, xmm3       // поправка
        test    edx, edx
        jle     @@done
        movsxd  rdx, edx
@@loop: movq   xmm1, qword ptr [rcx]
        subsd   xmm1, xmm3       // y = p - c
        movsd   xmm2, xmm0
        addsd   xmm2, xmm1       // t = sum + y
        movsd   xmm4, xmm2
        subsd   xmm4, xmm0       // t - sum
        subsd   xmm4, xmm1       // (t - sum) - y
        movsd   xmm3, xmm4       // c
        movsd   xmm0, xmm2       // sum = t
        add     rcx, 8
        dec     rdx
        jnz     @@loop
@@done:
end;

{ ═══ 9. Усечение к целому ════════════════════════════════════════════════ }

function TruncPas(V: Double): Int64;
begin
  Result := Trunc(V);
end;

function TruncAsm(V: Double): Int64; assembler; nostackframe;
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
        cvttsd2si rax, xmm0
end;

{ ═══ 10. Умножение матрицы на вектор ═════════════════════════════════════ }

procedure MatVecPas(M, V, R: PDouble);
begin
  for var I := 0 to 3 do
  begin
    var S: Double := 0;
    for var J := 0 to 3 do
      S := S + M[I * 4 + J] * V[J];
    R[I] := S;
  end;
end;

procedure MatVecAsm(M, V, R: PDouble); assembler; nostackframe;
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
        xor     r9, r9           // строка
@@row:  xorpd   xmm0, xmm0
        xor     r10, r10         // столбец
@@col:  mov     r11, r9
        shl     r11, 5           // строка * 4 * 8
        mov     rax, r10
        shl     rax, 3
        add     r11, rax
        movq   xmm1, qword ptr [rcx + r11]
        movq   xmm2, qword ptr [rdx + rax]
        mulsd   xmm1, xmm2
        addsd   xmm0, xmm1
        inc     r10
        cmp     r10, 4
        jl      @@col
        mov     rax, r9
        shl     rax, 3
        movq   qword ptr [r8 + rax], xmm0
        inc     r9
        cmp     r9, 4
        jl      @@row
end;

{ ═══ Прогон ══════════════════════════════════════════════════════════════ }

function SameBits(const A, B: Double): Boolean;
begin
  Result := PInt64(@A)^ = PInt64(@B)^;
end;

function ChiAsmFloatRun: Int64;
var
  Acc:   UInt64;
  Src:   TChiSource;
  A, B:  array [0 .. 255] of Double;
  W:     array [0 .. 7] of Double;
  M:     array [0 .. 15] of Double;
  V, R1, R2: array [0 .. 3] of Double;
  CA, CB, CC1, CC2: array [0 .. 1] of Double;
begin
  Acc := 0;
  ChiCovered(IdFloat);
  Src := ChiSource(1618033988);

  { ── Суммы и произведения ── }
  for var Round := 1 to 20 do
  begin
    var N := 1 + Src.NextBelow(255);
    for var I := 0 to N - 1 do
    begin
      A[I] := (Src.NextUnit - 0.5) * 1000;
      B[I] := (Src.NextUnit - 0.5) * 0.001;
    end;
    ChiClaim(SameBits(SumPas(@A[0], N), SumAsm(@A[0], N)),
      'сумма дробных: разошлись до бита');
    ChiClaim(SameBits(DotPas(@A[0], @B[0], N), DotAsm(@A[0], @B[0], N)),
      'скалярное произведение: разошлись до бита');
    ChiClaim(SameBits(SumSqPas(@A[0], N), SumSqAsm(@A[0], N)),
      'сумма квадратов: разошлись до бита');
    ChiClaim(SameBits(MaxPas(@A[0], N), MaxAsm(@A[0], N)),
      'наибольшее дробное: разошлись');
    ChiClaim(SumSqAsm(@A[0], N) >= 0, 'сумма квадратов отрицательна');
    Acc := ChiMix(Acc, Trunc(SumAsm(@A[0], N) * 1000));
  end;
  ChiBranch(IdFloat, 'sum-dot-max');

  { Числа разного порядка: тут порядок сложения виден особенно. }
  A[0] := 1E16;
  A[1] := 1;
  A[2] := -1E16;
  A[3] := 1;
  ChiClaim(SameBits(SumPas(@A[0], 4), SumAsm(@A[0], 4)),
    'сумма дробных: разошлись на числах разного порядка');
  ChiClaim(SumAsm(@A[0], 4) = 1, 'сумма дробных: подряд дала не то, что обязана');
  ChiBranch(IdFloat, 'catastrophic-order');

  { ── Компенсированная сумма ── }
  for var I := 0 to 255 do A[I] := 0.1;
  ChiClaim(SameBits(KahanPas(@A[0], 256), KahanAsm(@A[0], 256)),
    'компенсированная сумма: разошлись до бита');
  ChiClaim(KahanAsm(@A[0], 256) <> SumAsm(@A[0], 256),
    'компенсированная сумма: совпала с обычной — поправка не работает');
  ChiClaim(Abs(KahanAsm(@A[0], 256) - 25.6) < Abs(SumAsm(@A[0], 256) - 25.6),
    'компенсированная сумма: не точнее обычной');
  for var Round := 1 to 20 do
  begin
    var N := 1 + Src.NextBelow(255);
    for var I := 0 to N - 1 do A[I] := (Src.NextUnit - 0.5) * Power(10, Src.NextBelow(12) - 6);
    ChiClaim(SameBits(KahanPas(@A[0], N), KahanAsm(@A[0], N)),
      'компенсированная сумма: разошлись на случайных');
  end;
  ChiBranch(IdFloat, 'kahan');

  { ── Скользящее среднее ── }
  for var Round := 1 to 20 do
  begin
    var N := 2 + Src.NextBelow(254);
    for var I := 0 to N - 1 do A[I] := (Src.NextUnit) * 100;
    ChiClaim(SameBits(SmoothPas(@A[0], N), SmoothAsm(@A[0], N)),
      'скользящее среднее: разошлись до бита');
    Acc := ChiMix(Acc, Trunc(SmoothAsm(@A[0], N) * 1000));
  end;
  ChiBranch(IdFloat, 'smooth');

  { ── Свёртка с окном ── }
  for var Round := 1 to 20 do
  begin
    var N := 16 + Src.NextBelow(200);
    var Mw := 1 + Src.NextBelow(7);
    for var I := 0 to N - 1 do A[I] := (Src.NextUnit - 0.5) * 10;
    for var I := 0 to Mw - 1 do W[I] := Src.NextUnit;
    ChiClaim(SameBits(ConvPas(@A[0], @W[0], N, Mw), ConvAsm(@A[0], @W[0], N, Mw)),
      'свёртка: разошлись до бита');
  end;
  ChiBranch(IdFloat, 'convolution');

  { ── Комплексное умножение ── }
  for var Round := 1 to 100 do
  begin
    CA[0] := (Src.NextUnit - 0.5) * 100;
    CA[1] := (Src.NextUnit - 0.5) * 100;
    CB[0] := (Src.NextUnit - 0.5) * 100;
    CB[1] := (Src.NextUnit - 0.5) * 100;
    MulComplexPas(@CA[0], @CB[0], @CC1[0]);
    MulComplexAsm(@CA[0], @CB[0], @CC2[0]);
    ChiClaim(SameBits(CC1[0], CC2[0]) and SameBits(CC1[1], CC2[1]),
      'комплексное умножение: разошлись до бита');
  end;
  CA[0] := 0; CA[1] := 1;
  CB[0] := 0; CB[1] := 1;
  MulComplexAsm(@CA[0], @CB[0], @CC2[0]);
  ChiClaim((CC2[0] = -1) and (CC2[1] = 0),
    'комплексное умножение: мнимая единица в квадрате не минус один');
  ChiBranch(IdFloat, 'complex');

  { ── Матрица на вектор ── }
  for var Round := 1 to 60 do
  begin
    for var I := 0 to 15 do M[I] := (Src.NextUnit - 0.5) * 20;
    for var I := 0 to 3 do V[I] := (Src.NextUnit - 0.5) * 20;
    MatVecPas(@M[0], @V[0], @R1[0]);
    MatVecAsm(@M[0], @V[0], @R2[0]);
    for var I := 0 to 3 do
      ChiClaim(SameBits(R1[I], R2[I]), 'матрица на вектор: строка разошлась до бита');
    Acc := ChiMix(Acc, Trunc(R2[0] * 1000));
  end;
  { Единичная матрица обязана вернуть вектор как есть. }
  for var I := 0 to 15 do M[I] := 0;
  for var I := 0 to 3 do M[I * 4 + I] := 1;
  for var I := 0 to 3 do V[I] := I + 0.5;
  MatVecAsm(@M[0], @V[0], @R2[0]);
  for var I := 0 to 3 do
    ChiClaim(R2[I] = V[I], 'матрица на вектор: единичная исказила вектор');
  ChiBranch(IdFloat, 'matvec');

  { ── Усечение ── }
  var Probes: array [0 .. 9] of Double;
  Probes[0] := 0;
  Probes[1] := 1.9;
  Probes[2] := -1.9;
  Probes[3] := 0.5;
  Probes[4] := -0.5;
  Probes[5] := 1E15 + 0.5;
  Probes[6] := -1E15 - 0.5;
  Probes[7] := 2.5;
  Probes[8] := -2.5;
  Probes[9] := 4503599627370495.5;
  for var I := 0 to High(Probes) do
    ChiClaim(TruncPas(Probes[I]) = TruncAsm(Probes[I]),
      'усечение: разошлись на образце ' + IntToStr(I));
  for var Round := 1 to 200 do
  begin
    var X := (Src.NextUnit - 0.5) * 1E12;
    ChiClaim(TruncPas(X) = TruncAsm(X), 'усечение: разошлись на случайном');
  end;
  ChiClaim(TruncAsm(1.9) = 1, 'усечение: округлило вместо отбрасывания');
  ChiClaim(TruncAsm(-1.9) = -1, 'усечение: отрицательное ушло не в ту сторону');
  ChiBranch(IdFloat, 'trunc');
  Acc := ChiMix(Acc, TruncAsm(1E12));

  Result := Int64(Acc and $7FFFFFFFFFFF);
end;

end.
