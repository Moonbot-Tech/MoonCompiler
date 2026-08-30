unit chimera_asm_int;

{ Орган «паскаль против ассемблера»: целые числа и биты.

  Здесь перевёрнут обычный порядок вещей. В библиотеке ассемблер — это
  ускорение, а паскаль запасной путь; у нас наоборот: **считает паскаль**,
  потому что паскаль и есть то, что компилятор переводит в машинный код, а
  ассемблер лежит рядом ЭТАЛОНОМ, потому что его компилятор не трогает — он
  его только записывает как есть.

  Отсюда и правило написания. Паскальная сторона пишется так, как её пишут в
  работе: циклы, ветвления, накопители, чтобы оптимизатору было что двигать,
  разворачивать и держать в регистрах. Ассемблерная сторона пишется предельно
  прямо, без хитростей — её задача не быть быстрой, а быть очевидно верной.

  Оракул бесплатный: два ответа на один вход обязаны совпасть. Ни таблиц
  ожидаемых значений, ни модели — сравниваются две дороги к одному числу.
  Там, где ответ известен извне (общепринятые примеры), он тоже проверяется:
  совпадение двух дорог не спасёт, если обе ведут не туда.

  Соглашения ассемблерной стороны: соглашение о вызовах Windows x64 —
  целочисленные доводы в RCX, RDX, R8, R9, ответ в RAX. Заняты только
  свободные регистры (RAX, RCX, RDX, R8..R11), поэтому кадр не нужен. }

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

function ChiAsmIntRun: Int64;

implementation

const
  IdInt = 'CHI-ASM-INT-001';

{ ═══ 1. Сумма знаковых чисел ═════════════════════════════════════════════ }

function SumPas(P: PInt64; N: Integer): Int64;
begin
  Result := 0;
  while N > 0 do
  begin
    Inc(Result, P^);
    Inc(P);
    Dec(N);
  end;
end;

function SumAsm(P: PInt64; N: Integer): Int64; assembler; nostackframe;
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
@@loop: add     rax, qword ptr [rcx]
        add     rcx, 8
        dec     rdx
        jnz     @@loop
@@done:
end;

{ ═══ 2. Наибольшее и наименьшее ══════════════════════════════════════════ }

function MaxPas(P: PInt64; N: Integer): Int64;
begin
  Result := P^;
  for var I := 1 to N - 1 do
  begin
    Inc(P);
    if P^ > Result then Result := P^;
  end;
end;

function MaxAsm(P: PInt64; N: Integer): Int64; assembler; nostackframe;
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
        mov     rax, qword ptr [rcx]
        movsxd  rdx, edx
        dec     rdx
        jle     @@done
@@loop: add     rcx, 8
        mov     r8, qword ptr [rcx]
        cmp     r8, rax
        jle     @@next
        mov     rax, r8
@@next: dec     rdx
        jnz     @@loop
@@done:
end;

function MinPas(P: PInt64; N: Integer): Int64;
begin
  Result := P^;
  for var I := 1 to N - 1 do
  begin
    Inc(P);
    if P^ < Result then Result := P^;
  end;
end;

function MinAsm(P: PInt64; N: Integer): Int64; assembler; nostackframe;
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
        mov     rax, qword ptr [rcx]
        movsxd  rdx, edx
        dec     rdx
        jle     @@done
@@loop: add     rcx, 8
        mov     r8, qword ptr [rcx]
        cmp     r8, rax
        jge     @@next
        mov     rax, r8
@@next: dec     rdx
        jnz     @@loop
@@done:
end;

{ ═══ 3. Счёт единичных битов ═════════════════════════════════════════════ }

function PopCountPas(V: UInt64): Integer;
begin
  Result := 0;
  while V <> 0 do
  begin
    Inc(Result, Integer(V and 1));
    V := V shr 1;
  end;
end;

function PopCountAsm(V: UInt64): Integer; assembler; nostackframe;
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
        test    rcx, rcx
        jz      @@done
@@loop: mov     rdx, rcx
        and     edx, 1
        add     eax, edx
        shr     rcx, 1
        jnz     @@loop
@@done:
end;

{ ═══ 4. Номер старшего значащего бита ════════════════════════════════════ }

function HighBitPas(V: UInt64): Integer;
begin
  if V = 0 then Exit(-1);
  Result := 0;
  while V > 1 do
  begin
    V := V shr 1;
    Inc(Result);
  end;
end;

function HighBitAsm(V: UInt64): Integer; assembler; nostackframe;
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
        test    rcx, rcx
        jz      @@done
        bsr     rax, rcx
@@done:
end;

{ ═══ 5. Номер младшего значащего бита ════════════════════════════════════ }

function LowBitPas(V: UInt64): Integer;
begin
  if V = 0 then Exit(-1);
  Result := 0;
  while (V and 1) = 0 do
  begin
    V := V shr 1;
    Inc(Result);
  end;
end;

function LowBitAsm(V: UInt64): Integer; assembler; nostackframe;
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
        test    rcx, rcx
        jz      @@done
        bsf     rax, rcx
@@done:
end;

{ ═══ 6. Разворот битов ═══════════════════════════════════════════════════ }

function ReverseBitsPas(V: UInt64): UInt64;
begin
  Result := 0;
  for var I := 0 to 63 do
  begin
    Result := (Result shl 1) or (V and 1);
    V := V shr 1;
  end;
end;

function ReverseBitsAsm(V: UInt64): UInt64; assembler; nostackframe;
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
        mov     r8d, 64
@@loop: shl     rax, 1
        mov     rdx, rcx
        and     rdx, 1
        or      rax, rdx
        shr     rcx, 1
        dec     r8d
        jnz     @@loop
end;

{ ═══ 7. Перестановка байт ════════════════════════════════════════════════ }

function SwapBytesPas(V: UInt64): UInt64;
begin
  Result := ((V and $00000000000000FF) shl 56) or
            ((V and $000000000000FF00) shl 40) or
            ((V and $0000000000FF0000) shl 24) or
            ((V and $00000000FF000000) shl 8)  or
            ((V and $000000FF00000000) shr 8)  or
            ((V and $0000FF0000000000) shr 24) or
            ((V and $00FF000000000000) shr 40) or
            ((V and $FF00000000000000) shr 56);
end;

function SwapBytesAsm(V: UInt64): UInt64; assembler; nostackframe;
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
        mov     rax, rcx
        bswap   rax
end;

{ ═══ 8. Расстояние Хемминга ══════════════════════════════════════════════ }

function HammingPas(A, B: PByte; N: Integer): Integer;
var
  X: Byte;
begin
  Result := 0;
  for var I := 0 to N - 1 do
  begin
    X := A[I] xor B[I];
    while X <> 0 do
    begin
      Inc(Result, X and 1);
      X := X shr 1;
    end;
  end;
end;

function HammingAsm(A, B: PByte; N: Integer): Integer; assembler; nostackframe;
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
        xor     r9d, r10d
@@bits: test    r9d, r9d
        jz      @@next
        mov     r10d, r9d
        and     r10d, 1
        add     eax, r10d
        shr     r9d, 1
        jmp     @@bits
@@next: inc     rcx
        inc     rdx
        dec     r8
        jnz     @@loop
@@done:
end;

{ ═══ 9. Старшая половина произведения ════════════════════════════════════ }

function MulHighPas(A, B: UInt64): UInt64;
var
  AL, AH, BL, BH, T, W1, W2: UInt64;
begin
  AL := A and $FFFFFFFF;
  AH := A shr 32;
  BL := B and $FFFFFFFF;
  BH := B shr 32;
  T := AL * BL;
  T := AH * BL + (T shr 32);
  W1 := T and $FFFFFFFF;
  W2 := T shr 32;
  T := AL * BH + W1;
  Result := AH * BH + W2 + (T shr 32);
end;

function MulHighAsm(A, B: UInt64): UInt64; assembler; nostackframe;
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
        mov     rax, rcx
        mul     rdx
        mov     rax, rdx
end;

{ ═══ 10. Деление с остатком ══════════════════════════════════════════════ }

function DivModPas(A, B: UInt64; out Rem: UInt64): UInt64;
begin
  Result := A div B;
  Rem := A - Result * B;
end;

function DivModAsm(A, B: UInt64; out Rem: UInt64): UInt64; assembler; nostackframe;
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
        mov     rax, rcx         // делимое
        mov     r9, rdx          // делитель: rdx понадобится под остаток
        xor     rdx, rdx
        div     r9
        mov     qword ptr [r8], rdx
end;

{ ═══ 11. Наибольший общий делитель ═══════════════════════════════════════ }

function GcdPas(A, B: UInt64): UInt64;
var
  T: UInt64;
begin
  while B <> 0 do
  begin
    T := B;
    B := A mod B;
    A := T;
  end;
  Result := A;
end;

function GcdAsm(A, B: UInt64): UInt64; assembler; nostackframe;
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
        mov     rax, rcx
        mov     r8, rdx
@@loop: test    r8, r8
        jz      @@done
        xor     rdx, rdx
        div     r8
        mov     rax, r8
        mov     r8, rdx
        jmp     @@loop
@@done:
end;

{ ═══ 12. Целочисленный квадратный корень ═════════════════════════════════ }

function ISqrtPas(V: UInt64): UInt64;
var
  X, Y: UInt64;
begin
  if V = 0 then Exit(0);
  X := V;
  Y := (X + 1) shr 1;
  while Y < X do
  begin
    X := Y;
    Y := (X + V div X) shr 1;
  end;
  Result := X;
end;

{ Ассемблерная сторона считает тем же способом, но своими командами: сравнение
  идёт не с другой формулой, а с другим переводом одной и той же. }
function ISqrtAsm(V: UInt64): UInt64; assembler; nostackframe;
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
        test    rcx, rcx
        jz      @@done
        mov     r8, rcx          // r8 = V
        mov     rax, rcx         // x = V
        mov     r9, rcx
        inc     r9
        shr     r9, 1            // y = (V+1)/2
@@loop: cmp     r9, rax
        jae     @@done
        mov     rax, r9          // x = y
        mov     r10, rax
        mov     rax, r8
        xor     rdx, rdx
        div     r10              // rax = V div x
        add     rax, r10         // x + V div x
        shr     rax, 1
        mov     r9, rax          // y
        mov     rax, r10         // x
        jmp     @@loop
@@done:
end;

{ ═══ 13. Возведение в степень по модулю ══════════════════════════════════ }

function PowModPas(Base, Exp, Modu: UInt64): UInt64;
begin
  Result := 1;
  Base := Base mod Modu;
  while Exp > 0 do
  begin
    if (Exp and 1) <> 0 then Result := (Result * Base) mod Modu;
    Base := (Base * Base) mod Modu;
    Exp := Exp shr 1;
  end;
end;

function PowModAsm(Base, Exp, Modu: UInt64): UInt64; assembler; nostackframe;
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
        mov     r10, r8          // modu
        mov     r11, rdx         // exp
        mov     rax, rcx
        xor     rdx, rdx
        div     r10
        mov     r9, rdx          // base := base mod modu
        mov     r8, 1            // result
@@loop: test    r11, r11
        jz      @@done
        test    r11b, 1
        jz      @@square
        mov     rax, r8
        mul     r9
        div     r10
        mov     r8, rdx
@@square:
        mov     rax, r9
        mul     r9
        div     r10
        mov     r9, rdx
        shr     r11, 1
        jmp     @@loop
@@done: mov     rax, r8
end;

{ ═══ 14. Число переменной длины ══════════════════════════════════════════ }

function VarIntWritePas(V: UInt64; P: PByte): Integer;
begin
  Result := 0;
  repeat
    P[Result] := Byte(V and $7F);
    V := V shr 7;
    if V <> 0 then P[Result] := P[Result] or $80;
    Inc(Result);
  until V = 0;
end;

function VarIntWriteAsm(V: UInt64; P: PByte): Integer; assembler; nostackframe;
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
@@loop: mov     r8, rcx
        and     r8d, $7F
        shr     rcx, 7
        jz      @@last
        or      r8b, $80
@@last: mov     byte ptr [rdx + rax], r8b
        inc     eax
        test    rcx, rcx
        jnz     @@loop
end;

{ ═══ 15. Насыщающее сложение ═════════════════════════════════════════════ }

function AddSatPas(A, B: Int64): Int64;
var
  S: Int64;
begin
  S := A + B;
  if ((A xor S) and (B xor S)) < 0 then
  begin
    if A < 0 then Result := Low(Int64) else Result := High(Int64);
  end
  else
    Result := S;
end;

function AddSatAsm(A, B: Int64): Int64; assembler; nostackframe;
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
        mov     rax, rcx
        add     rax, rdx
        jno     @@done
        mov     rax, $7FFFFFFFFFFFFFFF
        test    rcx, rcx
        jns     @@done
        mov     rax, $8000000000000000
@@done:
end;

{ ═══ Прогон ══════════════════════════════════════════════════════════════ }

function ChiAsmIntRun: Int64;
var
  Acc:  UInt64;
  Src:  TChiSource;
  A64:  array [0 .. 511] of Int64;
  B1:   array [0 .. 255] of Byte;
  B2:   array [0 .. 255] of Byte;
  Buf1: array [0 .. 15] of Byte;
  Buf2: array [0 .. 15] of Byte;
  V:    UInt64;
begin
  Acc := 0;
  ChiCovered(IdInt);
  Src := ChiSource(20260830);

  { ── Сумма, наибольшее, наименьшее ── }
  for var Round := 1 to 8 do
  begin
    var N := 1 + Src.NextBelow(High(A64));
    for var I := 0 to N - 1 do
      A64[I] := Int64(Src.NextWord) - Int64(1) shl 62;
    ChiClaim(SumPas(@A64[0], N) = SumAsm(@A64[0], N), 'сумма: паскаль и ассемблер разошлись');
    ChiClaim(MaxPas(@A64[0], N) = MaxAsm(@A64[0], N), 'наибольшее: разошлись');
    ChiClaim(MinPas(@A64[0], N) = MinAsm(@A64[0], N), 'наименьшее: разошлись');
    Acc := ChiMix(Acc, SumAsm(@A64[0], N));
  end;
  { Один элемент и одинаковые значения — края обхода. }
  A64[0] := -5;
  ChiClaim(SumPas(@A64[0], 1) = SumAsm(@A64[0], 1), 'сумма: один элемент');
  ChiClaim(MaxPas(@A64[0], 1) = MaxAsm(@A64[0], 1), 'наибольшее: один элемент');
  ChiBranch(IdInt, 'sum-max-min');

  { ── Биты ── }
  var Probes: array [0 .. 9] of UInt64;
  Probes[0] := 0;
  Probes[1] := 1;
  Probes[2] := UInt64($8000000000000000);
  Probes[3] := UInt64($FFFFFFFFFFFFFFFF);
  Probes[4] := $0F0F0F0F0F0F0F0F;
  Probes[5] := $8000000000000001;
  Probes[6] := $00000000FFFFFFFF;
  Probes[7] := $FFFFFFFF00000000;
  Probes[8] := 12345678901234567;
  Probes[9] := $5555555555555555;
  for var I := 0 to High(Probes) do
  begin
    V := Probes[I];
    ChiClaim(PopCountPas(V) = PopCountAsm(V), 'счёт битов: разошлись');
    ChiClaim(HighBitPas(V) = HighBitAsm(V), 'старший бит: разошлись');
    ChiClaim(LowBitPas(V) = LowBitAsm(V), 'младший бит: разошлись');
    ChiClaim(ReverseBitsPas(V) = ReverseBitsAsm(V), 'разворот битов: разошлись');
    ChiClaim(SwapBytesPas(V) = SwapBytesAsm(V), 'перестановка байт: разошлись');
    Acc := ChiMix(Acc, Int64(ReverseBitsAsm(V)));
  end;
  { Внешняя истина: обе дороги могут вести не туда одинаково. }
  ChiClaim(PopCountAsm($FFFFFFFFFFFFFFFF) = 64, 'счёт битов: предел не 64');
  ChiClaim(SwapBytesAsm($0102030405060708) = $0807060504030201,
    'перестановка байт: известный пример не сошёлся');
  ChiClaim(ReverseBitsAsm(1) = UInt64($8000000000000000),
    'разворот битов: единица не ушла в старший');
  ChiBranch(IdInt, 'bit-ops');

  for var Round := 1 to 200 do
  begin
    V := Src.NextWord;
    ChiClaim(PopCountPas(V) = PopCountAsm(V), 'счёт битов: разошлись на случайном');
    ChiClaim(HighBitPas(V) = HighBitAsm(V), 'старший бит: разошлись на случайном');
    ChiClaim(ReverseBitsPas(V) = ReverseBitsAsm(V), 'разворот: разошлись на случайном');
  end;
  ChiBranch(IdInt, 'bit-ops-random');

  { ── Расстояние Хемминга ── }
  for var Round := 1 to 12 do
  begin
    var N := 1 + Src.NextBelow(High(B1));
    for var I := 0 to N - 1 do
    begin
      B1[I] := Byte(Src.NextBelow(256));
      B2[I] := Byte(Src.NextBelow(256));
    end;
    ChiClaim(HammingPas(@B1[0], @B2[0], N) = HammingAsm(@B1[0], @B2[0], N),
      'расстояние: разошлись');
    Acc := ChiMix(Acc, HammingAsm(@B1[0], @B2[0], N));
  end;
  FillChar(B1, SizeOf(B1), 0);
  FillChar(B2, SizeOf(B2), $FF);
  ChiClaim(HammingAsm(@B1[0], @B2[0], 256) = 256 * 8,
    'расстояние: полное несовпадение не дало восемь бит на байт');
  ChiClaim(HammingAsm(@B1[0], @B1[0], 256) = 0, 'расстояние: сам с собой не ноль');
  ChiBranch(IdInt, 'hamming');

  { ── Умножение, деление, остаток ── }
  for var Round := 1 to 200 do
  begin
    var X := Src.NextWord;
    var Y := Src.NextWord;
    ChiClaim(MulHighPas(X, Y) = MulHighAsm(X, Y), 'старшая половина: разошлись');
    if Y <> 0 then
    begin
      var R1, R2: UInt64;
      var Q1 := DivModPas(X, Y, R1);
      var Q2 := DivModAsm(X, Y, R2);
      ChiClaim((Q1 = Q2) and (R1 = R2), 'деление: частное или остаток разошлись');
      ChiClaim(Q2 * Y + R2 = X, 'деление: частное и остаток не восстанавливают делимое');
      ChiClaim(GcdPas(X, Y) = GcdAsm(X, Y), 'общий делитель: разошлись');
    end;
    Acc := ChiMix(Acc, Int64(MulHighAsm(X, Y)));
  end;
  ChiClaim(MulHighAsm(UInt64($FFFFFFFFFFFFFFFF), UInt64($FFFFFFFFFFFFFFFF)) =
           UInt64($FFFFFFFFFFFFFFFE), 'старшая половина: предел не сошёлся');
  ChiClaim(GcdAsm(1071, 462) = 21, 'общий делитель: известный пример не сошёлся');
  ChiBranch(IdInt, 'mul-div-gcd');

  { ── Корень и степень по модулю ── }
  for var Round := 1 to 150 do
  begin
    V := Src.NextWord shr 4;
    ChiClaim(ISqrtPas(V) = ISqrtAsm(V), 'корень: разошлись');
    var R := ISqrtAsm(V);
    ChiClaim(R * R <= V, 'корень: квадрат больше числа');
    if R < UInt64($FFFFFFFF) then
      ChiClaim((R + 1) * (R + 1) > V, 'корень: нашёлся не наибольший');
  end;
  ChiClaim(ISqrtAsm(0) = 0, 'корень: из нуля не ноль');
  ChiClaim(ISqrtAsm(1) = 1, 'корень: из единицы не единица');
  ChiClaim(ISqrtAsm(144) = 12, 'корень: из ста сорока четырёх не двенадцать');
  ChiBranch(IdInt, 'isqrt');

  for var Round := 1 to 100 do
  begin
    var Base := Src.NextWord shr 33;
    var Exp := Src.NextWord shr 40;
    var Modu := 3 + (Src.NextWord shr 34);
    ChiClaim(PowModPas(Base, Exp, Modu) = PowModAsm(Base, Exp, Modu),
      'степень по модулю: разошлись');
    Acc := ChiMix(Acc, Int64(PowModAsm(Base, Exp, Modu)));
  end;
  ChiClaim(PowModAsm(2, 10, 1000) = 24, 'степень по модулю: известный пример не сошёлся');
  ChiBranch(IdInt, 'powmod');

  { ── Число переменной длины ── }
  for var Round := 1 to 200 do
  begin
    V := Src.NextWord shr (Src.NextBelow(64));
    var L1 := VarIntWritePas(V, @Buf1[0]);
    var L2 := VarIntWriteAsm(V, @Buf2[0]);
    ChiClaim(L1 = L2, 'число переменной длины: длины разошлись');
    ChiClaim(CompareMem(@Buf1[0], @Buf2[0], L1), 'число переменной длины: байты разошлись');
  end;
  ChiClaim(VarIntWriteAsm(0, @Buf1[0]) = 1, 'число переменной длины: ноль не один байт');
  ChiClaim(VarIntWriteAsm(127, @Buf1[0]) = 1, 'число переменной длины: сто двадцать семь не один байт');
  ChiClaim(VarIntWriteAsm(128, @Buf1[0]) = 2, 'число переменной длины: сто двадцать восемь не два байта');
  ChiBranch(IdInt, 'varint');

  { ── Насыщающее сложение ── }
  for var Round := 1 to 200 do
  begin
    var X := Int64(Src.NextWord);
    var Y := Int64(Src.NextWord);
    ChiClaim(AddSatPas(X, Y) = AddSatAsm(X, Y), 'насыщение: разошлись');
  end;
  ChiClaim(AddSatAsm(High(Int64), 1) = High(Int64), 'насыщение: не удержало верх');
  ChiClaim(AddSatAsm(Low(Int64), -1) = Low(Int64), 'насыщение: не удержало низ');
  ChiClaim(AddSatAsm(5, -7) = -2, 'насыщение: обычное сложение испорчено');
  ChiBranch(IdInt, 'add-saturating');
  Acc := ChiMix(Acc, AddSatAsm(High(Int64), 1));

  Result := Int64(Acc and $7FFFFFFFFFFF);
end;

end.
