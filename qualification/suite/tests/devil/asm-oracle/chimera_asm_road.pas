unit chimera_asm_road;

{ Орган «разные дороги к одному ответу».

  Здесь другой замысел, чем у соседних органов семейства. Там одна и та же
  работа записана дважды — на паскале и на ассемблере, — и это ловит ошибку
  перевода конкретной формы цикла. Но у такой пары есть предел: если бы
  компилятор сломал само сложение, обе стороны совпали бы в неправде.

  Поэтому здесь дороги к ответу **принципиально разные**: не две записи одной
  формулы, а разные способы думать о задаче. Деление честное против замены
  умножением. Поиск перебором против поиска со сдвигом по таблице и против
  поиска одной командой процессора. Свёртка через таблицу против свёртки по
  битам, через нарезку по четыре и через команду. Такое совпадение доказывает
  не запись, а САМ ОТВЕТ: чтобы обмануть эту сверку, ошибиться нужно
  одинаково в несовместимых алгоритмах.

  Отдельно проверяется то, что делает сам оптимизатор: деление на постоянную
  он заменяет умножением на обратную величину с поправкой. Здесь этот приём
  выписан руками и сверяется с честным делением — то есть проверяется ровно та
  замена, которую компилятор выполняет молча. }

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

function ChiAsmRoadRun: Int64;

implementation

const
  IdRoad = 'CHI-ASM-ROAD-001';

{ ═══ 1. Деление на постоянную: четыре дороги ═════════════════════════════ }

{ Дорога первая — честное деление. }
function DivHonest(V: Cardinal; D: Cardinal): Cardinal;
begin
  Result := V div D;
end;

{ Дорога вторая — приём самого оптимизатора: умножение на обратную величину,
  взятую с запасом, и сдвиг. Множитель и сдвиг подобраны для делителя ниже. }
function DivByMagic(V: Cardinal): Cardinal;
var
  T: UInt64;
begin
  { делитель 1000: множитель 274877907, сдвиг 38 }
  T := UInt64(V) * UInt64(274877907);
  Result := Cardinal(T shr 38);
end;

{ Дорога третья — вычитанием со сдвигом, как делят в столбик. }
function DivByShift(V: Cardinal; D: Cardinal): Cardinal;
var
  Rem, Cur: UInt64;
begin
  Result := 0;
  Rem := 0;
  for var Bit := 31 downto 0 do
  begin
    Rem := (Rem shl 1) or ((V shr Bit) and 1);
    if Rem >= D then
    begin
      Rem := Rem - D;
      Result := Result or (Cardinal(1) shl Bit);
    end;
  end;
  Cur := Rem;
  if Cur > D then Result := 0;   { недостижимо: остаток всегда меньше делителя }
end;

{ Дорога четвёртая — команда процессора. }
function DivByOpcode(V: Cardinal; D: Cardinal): Cardinal; assembler; nostackframe;
asm
{$ifdef UNIX}
        mov     r9, rcx
        mov     r8, rdx
        mov     rdx, rsi
        mov     rcx, rdi
{$endif}
        mov     eax, ecx
        mov     r8d, edx
        xor     edx, edx
        div     r8d
end;

{ ═══ 2. Контрольная сумма: четыре дороги ═════════════════════════════════ }

var
  Tab1: array [0 .. 255] of Cardinal;             { обычная таблица }
  Tab4: array [0 .. 3, 0 .. 255] of Cardinal;     { нарезка по четыре байта }

procedure BuildCrcTables;
var
  C: Cardinal;
begin
  for var I := 0 to 255 do
  begin
    C := I;
    for var K := 1 to 8 do
      if (C and 1) <> 0
        then C := (C shr 1) xor $82F63B78
        else C := C shr 1;
    Tab1[I] := C;
    Tab4[0][I] := C;
  end;
  { Столбцы нарезки: каждый следующий — прокрутка предыдущего на байт. }
  for var I := 0 to 255 do
    for var K := 1 to 3 do
      Tab4[K][I] := (Tab4[K - 1][I] shr 8) xor Tab1[Tab4[K - 1][I] and $FF];
end;

{ Дорога первая — по биту. }
function CrcByBits(P: PByte; N: Integer): Cardinal;
begin
  Result := $FFFFFFFF;
  for var I := 0 to N - 1 do
  begin
    Result := Result xor P[I];
    for var K := 1 to 8 do
      if (Result and 1) <> 0
        then Result := (Result shr 1) xor $82F63B78
        else Result := Result shr 1;
  end;
  Result := not Result;
end;

{ Дорога вторая — по байту через таблицу. }
function CrcByTable(P: PByte; N: Integer): Cardinal;
begin
  Result := $FFFFFFFF;
  for var I := 0 to N - 1 do
    Result := Tab1[(Result xor P[I]) and $FF] xor (Result shr 8);
  Result := not Result;
end;

{ Дорога третья — по четыре байта разом, четырьмя таблицами. Хвост
  дорабатывается побайтово. }
function CrcBySlicing(P: PByte; N: Integer): Cardinal;
var
  W: Cardinal;
  I: Integer;
begin
  Result := $FFFFFFFF;
  I := 0;
  while I + 4 <= N do
  begin
    W := PCardinal(@P[I])^ xor Result;
    Result := Tab4[3][W and $FF] xor
              Tab4[2][(W shr 8) and $FF] xor
              Tab4[1][(W shr 16) and $FF] xor
              Tab4[0][(W shr 24) and $FF];
    Inc(I, 4);
  end;
  while I < N do
  begin
    Result := Tab1[(Result xor P[I]) and $FF] xor (Result shr 8);
    Inc(I);
  end;
  Result := not Result;
end;

{ Дорога четвёртая — команда процессора, сразу по восемь байт. }
function CrcByOpcode(P: PByte; N: Integer): Cardinal; assembler; nostackframe;
asm
{$ifdef UNIX}
        mov     r9, rcx
        mov     r8, rdx
        mov     rdx, rsi
        mov     rcx, rdi
{$endif}
        mov     eax, $FFFFFFFF
        test    edx, edx
        jle     @@done
        movsxd  rdx, edx
@@wide: cmp     rdx, 8
        jb      @@tail
        crc32   rax, qword ptr [rcx]
        add     rcx, 8
        sub     rdx, 8
        jmp     @@wide
@@tail: test    rdx, rdx
        jz      @@done
@@byte: crc32   eax, byte ptr [rcx]
        inc     rcx
        dec     rdx
        jnz     @@byte
@@done: not     eax
end;

{ ═══ 3. Поиск подстроки: три дороги ══════════════════════════════════════ }

{ Дорога первая — перебор всех положений. }
function FindNaive(H: PByte; HN: Integer; N: PByte; NN: Integer): Integer;
begin
  if (NN = 0) or (NN > HN) then Exit(-1);
  for var I := 0 to HN - NN do
  begin
    var Ok := True;
    for var J := 0 to NN - 1 do
      if H[I + J] <> N[J] then
      begin
        Ok := False;
        Break;
      end;
    if Ok then Exit(I);
  end;
  Result := -1;
end;

{ Дорога вторая — сдвиг по таблице несовпадений: сравнение идёт С КОНЦА, а
  промах двигает окно сразу на несколько позиций. Совсем другая механика. }
function FindHorspool(H: PByte; HN: Integer; N: PByte; NN: Integer): Integer;
var
  Shift: array [0 .. 255] of Integer;
  Pos:   Integer;
begin
  if (NN = 0) or (NN > HN) then Exit(-1);
  for var I := 0 to 255 do Shift[I] := NN;
  for var I := 0 to NN - 2 do Shift[N[I]] := NN - 1 - I;
  Pos := 0;
  while Pos <= HN - NN do
  begin
    var J := NN - 1;
    while (J >= 0) and (H[Pos + J] = N[J]) do Dec(J);
    if J < 0 then Exit(Pos);
    Inc(Pos, Shift[H[Pos + NN - 1]]);
  end;
  Result := -1;
end;

{ Дорога третья — команда, просматривающая ШЕСТНАДЦАТЬ БАЙТ ЗА РАЗ. Она
  ищет в блоке любой байт из образца и возвращает номер первого совпадения;
  образец здесь длиной в один байт — первая буква иглы. Совпал кандидат —
  хвост досравнивается обычным способом, не совпал — окно прыгает сразу на
  шестнадцать. Обход получается совсем не тот, что у перебора и у сдвига по
  таблице.

  Оговорка команды: строки для неё оканчиваются нулевым байтом, поэтому в
  данных этой проверки нулей нет — иначе блок оборвался бы раньше времени. }
function FindWithOpcode(H: PByte; HN: Integer; N: PByte; NN: Integer): Integer;
  assembler; nostackframe;
asm
{$ifdef UNIX}
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
        mov     r11, rcx         // база стога: RCX затрёт команда поиска
        movzx   eax, byte ptr [r8]
        movd    xmm1, eax        // образец из одной буквы
        xor     r10, r10         // позиция окна
@@scan: cmp     r10, rdx
        jg      @@fail
        movdqu  xmm2, oword ptr [r11 + r10]
        pcmpistri xmm1, xmm2, 0
        cmp     ecx, 16
        jae     @@skip
        add     r10, rcx         // подвинулись к найденному кандидату
        cmp     r10, rdx
        jg      @@fail
        xor     rcx, rcx         // смещение внутри иглы
@@tail: cmp     rcx, r9
        jge     @@found
        mov     rax, r10
        add     rax, rcx
        movzx   eax, byte ptr [r11 + rax]
        cmp     al, byte ptr [r8 + rcx]
        jne     @@advance
        inc     rcx
        jmp     @@tail
@@advance:
        inc     r10
        jmp     @@scan
@@skip: add     r10, 16
        jmp     @@scan
@@found:mov     rax, r10
        jmp     @@done
@@fail: mov     eax, -1
@@done:
end;

{ ═══ 4. Счёт битов: три дороги ═══════════════════════════════════════════ }

var
  BitTab: array [0 .. 255] of Byte;

procedure BuildBitTable;
begin
  for var I := 0 to 255 do
  begin
    var C := 0;
    var V := I;
    while V <> 0 do
    begin
      Inc(C, V and 1);
      V := V shr 1;
    end;
    BitTab[I] := C;
  end;
end;

{ Дорога первая — по таблице байтов. }
function BitsByTable(V: UInt64): Integer;
begin
  Result := 0;
  for var I := 0 to 7 do
    Inc(Result, BitTab[(V shr (I * 8)) and $FF]);
end;

{ Дорога вторая — параллельное сложение внутри слова: пары, четвёрки,
  байты, и наконец умножение сдвигает сумму в старший байт. Ни одного
  обращения к памяти и ни одного цикла. }
function BitsBySwar(V: UInt64): Integer;
begin
  V := V - ((V shr 1) and UInt64($5555555555555555));
  V := (V and UInt64($3333333333333333)) + ((V shr 2) and UInt64($3333333333333333));
  V := (V + (V shr 4)) and UInt64($0F0F0F0F0F0F0F0F);
  Result := (V * UInt64($0101010101010101)) shr 56;
end;

{ Дорога третья — команда процессора. }
function BitsByOpcode(V: UInt64): Integer; assembler; nostackframe;
asm
{$ifdef UNIX}
        mov     r9, rcx
        mov     r8, rdx
        mov     rdx, rsi
        mov     rcx, rdi
{$endif}
        popcnt  rax, rcx
end;

{ ═══ 5. Квадратный корень: три дороги ════════════════════════════════════ }

{ Дорога первая — приближения Ньютона в целых числах. }
function SqrtByNewton(V: UInt64): UInt64;
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

{ Дорога вторая — побитовое восстановление: пробуем поставить очередной бит
  и смотрим, не превысил ли квадрат. Ни одного деления. }
function SqrtByBits(V: UInt64): UInt64;
var
  Bit, Res, Rem: UInt64;
begin
  Res := 0;
  Rem := V;
  Bit := UInt64(1) shl 62;
  while Bit > Rem do Bit := Bit shr 2;
  while Bit <> 0 do
  begin
    if Rem >= Res + Bit then
    begin
      Rem := Rem - (Res + Bit);
      Res := (Res shr 1) + Bit;
    end
    else
      Res := Res shr 1;
    Bit := Bit shr 2;
  end;
  Result := Res;
end;

{ Дорога третья — через дробный корень процессора с поправкой на краю. }
function SqrtByOpcode(V: UInt64): UInt64; assembler; nostackframe;
asm
{$ifdef UNIX}
        mov     r9, rcx
        mov     r8, rdx
        mov     rdx, rsi
        mov     rcx, rdi
{$endif}
        mov     rax, rcx
        test    rax, rax
        jz      @@done
        { перевод без знака: старший бит требует особого обращения }
        mov     r8, rax
        shr     r8, 1
        mov     r9, rax
        and     r9, 1
        or      r8, r9
        cvtsi2sd xmm0, r8
        addsd   xmm0, xmm0
        sqrtsd  xmm0, xmm0
        cvttsd2si rax, xmm0
        { поправка: корень мог получиться на единицу больше или меньше }
@@big:  test    rax, rax
        jz      @@small
        mov     r8, rax
        imul    r8, r8
        cmp     r8, rcx
        jbe     @@small
        dec     rax
        jmp     @@big
@@small:mov     r8, rax
        inc     r8
        mov     r9, r8
        imul    r9, r9
        { переполнение произведения означает, что дальше идти некуда }
        jo      @@done
        cmp     r9, rcx
        ja      @@done
        mov     rax, r8
        jmp     @@small
@@done:
end;

{ ═══ 6. Умножение длинных чисел: две дороги ══════════════════════════════ }

type
  TChiWide = record
    Lo, Hi: UInt64;
  end;

{ Дорога первая — школьное умножение столбиком по половинкам. }
function MulSchool(A, B: UInt64): TChiWide;
var
  AL, AH, BL, BH: UInt64;
  P0, P1, P2, P3, Mid: UInt64;
begin
  AL := A and $FFFFFFFF;
  AH := A shr 32;
  BL := B and $FFFFFFFF;
  BH := B shr 32;
  P0 := AL * BL;
  P1 := AL * BH;
  P2 := AH * BL;
  P3 := AH * BH;
  Mid := (P0 shr 32) + (P1 and $FFFFFFFF) + (P2 and $FFFFFFFF);
  Result.Lo := (P0 and $FFFFFFFF) or (Mid shl 32);
  Result.Hi := P3 + (P1 shr 32) + (P2 shr 32) + (Mid shr 32);
end;

{ Дорога вторая — приём Карацубы: три умножения вместо четырёх, зато со
  знаковой поправкой на разностях. Совсем другая арифметика переносов. }
{ Средняя часть здесь — сумма двух почти предельных произведений, и в
  шестьдесят четыре разряда она НЕ ВЛЕЗАЕТ. Школьный способ обходит это тем,
  что складывает половинками; у Карацубы половинок нет, поэтому перенос
  средней части приходится вести отдельным разрядом. Ровно на этом месте
  большинство переносов Карацубы и ошибается. }
function MulKaratsuba(A, B: UInt64): TChiWide;
var
  AL, AH, BL, BH: UInt64;
  Z0, Z2, T, Mid: UInt64;
  MidHi, CarryLo: UInt64;
  DA, DB: Int64;
  Neg: Boolean;
begin
  AL := A and $FFFFFFFF;
  AH := A shr 32;
  BL := B and $FFFFFFFF;
  BH := B shr 32;
  Z0 := AL * BL;
  Z2 := AH * BH;
  DA := Int64(AH) - Int64(AL);
  DB := Int64(BL) - Int64(BH);
  Neg := (DA < 0) xor (DB < 0);
  if DA < 0 then DA := -DA;
  if DB < 0 then DB := -DB;
  T := UInt64(DA) * UInt64(DB);

  Mid := Z0 + Z2;
  if Mid < Z0 then MidHi := 1 else MidHi := 0;
  if Neg then
  begin
    if Mid < T then Dec(MidHi);
    Mid := Mid - T;
  end
  else
  begin
    Mid := Mid + T;
    if Mid < T then Inc(MidHi);
  end;

  Result.Lo := Z0 + (Mid shl 32);
  if Result.Lo < Z0 then CarryLo := 1 else CarryLo := 0;
  Result.Hi := Z2 + (Mid shr 32) + (MidHi shl 32) + CarryLo;
end;

{ Дорога третья — одна команда процессора. }
procedure MulByOpcode(A, B: UInt64; R: Pointer); assembler; nostackframe;
asm
{$ifdef UNIX}
        mov     r9, rcx
        mov     r8, rdx
        mov     rdx, rsi
        mov     rcx, rdi
{$endif}
        mov     rax, rcx
        mul     rdx
        mov     qword ptr [r8], rax
        mov     qword ptr [r8 + 8], rdx
end;

{ ═══ 7. Суммирование: три дороги с доказуемым порядком точности ══════════ }

function SumSequential(P: PDouble; N: Integer): Double;
begin
  Result := 0;
  for var I := 0 to N - 1 do
    Result := Result + P[I];
end;

{ Попарное сложение: складываем половинами, глубина ошибки растёт как
  логарифм длины, а не как длина. }
function SumPairwise(P: PDouble; N: Integer): Double;
begin
  if N = 0 then Exit(0);
  if N = 1 then Exit(P[0]);
  var Half := N div 2;
  Result := SumPairwise(P, Half) + SumPairwise(@P[Half], N - Half);
end;

function SumKahan(P: PDouble; N: Integer): Double;
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

{ ═══ Прогон ══════════════════════════════════════════════════════════════ }

function ChiAsmRoadRun: Int64;
var
  Acc:  UInt64;
  Src:  TChiSource;
  Buf:  array [0 .. 2047] of Byte;
  Nee:  array [0 .. 15] of Byte;
  D:    array [0 .. 1023] of Double;
  W1, W2: TChiWide;
  WR:   array [0 .. 1] of UInt64;
  V:    UInt64;
begin
  Acc := 0;
  ChiCovered(IdRoad);
  BuildCrcTables;
  BuildBitTable;
  Src := ChiSource(1234567891);

  { ── Деление на постоянную: приём оптимизатора против честного деления ── }
  for var Round := 1 to 400 do
  begin
    var X := Cardinal(Src.NextWord);
    ChiClaim(DivHonest(X, 1000) = DivByMagic(X),
      'деление: замена умножением разошлась с честным делением');
    ChiClaim(DivHonest(X, 1000) = DivByShift(X, 1000),
      'деление: столбиком разошлось с честным');
    ChiClaim(DivHonest(X, 1000) = DivByOpcode(X, 1000),
      'деление: команда разошлась с честным');
  end;
  { Края разрядной сетки — там замена умножением ошибается чаще всего. }
  var Edges: array [0 .. 7] of Cardinal;
  Edges[0] := 0;
  Edges[1] := 999;
  Edges[2] := 1000;
  Edges[3] := 1001;
  Edges[4] := $FFFFFFFF;
  Edges[5] := $FFFFFFFF - 999;
  Edges[6] := $80000000;
  Edges[7] := 4294966999;
  for var I := 0 to High(Edges) do
  begin
    ChiClaim(DivHonest(Edges[I], 1000) = DivByMagic(Edges[I]),
      'деление: замена умножением ошиблась на краю ' + IntToStr(Edges[I]));
    ChiClaim(DivHonest(Edges[I], 1000) = DivByShift(Edges[I], 1000),
      'деление: столбиком ошиблось на краю');
  end;
  ChiBranch(IdRoad, 'divide-four-roads');
  Acc := ChiMix(Acc, DivByMagic($FFFFFFFF));

  { Столбиком и командой — на произвольных делителях. }
  for var Round := 1 to 300 do
  begin
    var X := Cardinal(Src.NextWord);
    var Dv := 1 + Cardinal(Src.NextBelow(65535));
    ChiClaim(DivByShift(X, Dv) = DivByOpcode(X, Dv),
      'деление: столбиком и команда разошлись');
    ChiClaim(DivByShift(X, Dv) = X div Dv, 'деление: столбиком неверно');
  end;
  ChiBranch(IdRoad, 'divide-any-divisor');

  { ── Контрольная сумма: четыре дороги ── }
  Move(PAnsiChar('123456789')^, Buf[0], 9);
  ChiClaim(CrcByBits(@Buf[0], 9) = $E3069283, 'сумма по битам: известный ответ не сошёлся');
  ChiClaim(CrcBySlicing(@Buf[0], 9) = $E3069283, 'сумма нарезкой: известный ответ не сошёлся');
  for var N := 0 to 300 do
  begin
    for var I := 0 to N - 1 do Buf[I] := Byte(Src.NextBelow(256));
    var A := CrcByBits(@Buf[0], N);
    var B := CrcByTable(@Buf[0], N);
    var C := CrcBySlicing(@Buf[0], N);
    var Dd := CrcByOpcode(@Buf[0], N);
    ChiClaim(A = B, 'сумма: биты и таблица разошлись на длине ' + IntToStr(N));
    ChiClaim(A = C, 'сумма: биты и нарезка разошлись на длине ' + IntToStr(N));
    ChiClaim(A = Dd, 'сумма: биты и команда разошлись на длине ' + IntToStr(N));
    Acc := ChiMix(Acc, A);
  end;
  ChiBranch(IdRoad, 'crc-four-roads');

  { Хвосты нарезки: длины вокруг кратности четырём и восьми проверяются
    поимённо — там нарезка переходит на побайтовую доработку. }
  for var N := 1 to 40 do
  begin
    for var I := 0 to N - 1 do Buf[I] := Byte(200 + (I mod 7));
    ChiClaim(CrcBySlicing(@Buf[0], N) = CrcByTable(@Buf[0], N),
      'сумма: хвост нарезки разошёлся на длине ' + IntToStr(N));
    ChiClaim(CrcByOpcode(@Buf[0], N) = CrcByTable(@Buf[0], N),
      'сумма: хвост команды разошёлся на длине ' + IntToStr(N));
  end;
  ChiBranch(IdRoad, 'crc-tails');

  { ── Поиск подстроки: три дороги ── }
  for var Round := 1 to 200 do
  begin
    var HN := 20 + Src.NextBelow(2000);
    { Байты берутся от единицы: нулевой байт для команды поиска означает конец
      строки, и блок оборвался бы раньше времени. }
    for var I := 0 to HN - 1 do Buf[I] := Byte(1 + Src.NextBelow(5));
    var NN := 1 + Src.NextBelow(8);
    for var I := 0 to NN - 1 do Nee[I] := Byte(1 + Src.NextBelow(5));
    var R1 := FindNaive(@Buf[0], HN, @Nee[0], NN);
    var R2 := FindHorspool(@Buf[0], HN, @Nee[0], NN);
    var R3 := FindWithOpcode(@Buf[0], HN, @Nee[0], NN);
    ChiClaim(R1 = R2, 'поиск: перебор и сдвиг по таблице разошлись');
    ChiClaim(R1 = R3, 'поиск: перебор и команда разошлись');
    { заложенная игла обязана находиться всеми тремя }
    var At := Src.NextBelow(HN - NN);
    Move(Buf[At], Nee[0], NN);
    R1 := FindNaive(@Buf[0], HN, @Nee[0], NN);
    R2 := FindHorspool(@Buf[0], HN, @Nee[0], NN);
    R3 := FindWithOpcode(@Buf[0], HN, @Nee[0], NN);
    ChiClaim((R1 >= 0) and (R1 <= At), 'поиск: заложенная игла не найдена перебором');
    ChiClaim(R1 = R2, 'поиск: заложенная — сдвиг разошёлся');
    ChiClaim(R1 = R3, 'поиск: заложенная — команда разошлась');
    Acc := ChiMix(Acc, R1);
  end;
  ChiBranch(IdRoad, 'find-three-roads');

  { ── Счёт битов: три дороги ── }
  for var Round := 1 to 500 do
  begin
    V := Src.NextWord;
    var A := BitsByTable(V);
    var B := BitsBySwar(V);
    var C := BitsByOpcode(V);
    ChiClaim(A = B, 'счёт битов: таблица и разрядное сложение разошлись');
    ChiClaim(A = C, 'счёт битов: таблица и команда разошлись');
  end;
  ChiClaim(BitsBySwar(0) = 0, 'счёт битов: ноль не ноль');
  ChiClaim(BitsBySwar(UInt64($FFFFFFFFFFFFFFFF)) = 64, 'счёт битов: предел не 64');
  ChiClaim(BitsBySwar(UInt64($8000000000000000)) = 1, 'счёт битов: старший бит не один');
  ChiBranch(IdRoad, 'popcount-three-roads');

  { ── Корень: три дороги ── }
  for var Round := 1 to 300 do
  begin
    { Два обращения к источнику держим РАЗНЫМИ операторами: порядок вычисления
      доводов внутри одного выражения язык не задаёт, и одна и та же строка на
      разных системах дала бы разные числа. }
    var Raw := Src.NextWord;
    var Shift := Src.NextBelow(40);
    V := Raw shr Shift;
    var A := SqrtByNewton(V);
    var B := SqrtByBits(V);
    var C := SqrtByOpcode(V);
    ChiClaim(A = B, 'корень: Ньютон и биты разошлись');
    ChiClaim(A = C, 'корень: Ньютон и команда разошлись');
    ChiClaim(A * A <= V, 'корень: квадрат больше числа');
    if A < UInt64(4000000000) then
      ChiClaim((A + 1) * (A + 1) > V, 'корень: нашёлся не наибольший');
    Acc := ChiMix(Acc, Int64(A));
  end;
  { Точные квадраты и их соседи. }
  for var K := 0 to 200 do
  begin
    V := UInt64(K) * UInt64(K);
    ChiClaim(SqrtByBits(V) = UInt64(K), 'корень: точный квадрат не сошёлся');
    ChiClaim(SqrtByOpcode(V) = UInt64(K), 'корень: команда на точном квадрате');
    if K > 0 then
    begin
      ChiClaim(SqrtByBits(V - 1) = UInt64(K - 1), 'корень: на единицу меньше квадрата');
      ChiClaim(SqrtByOpcode(V - 1) = UInt64(K - 1), 'корень: команда на единицу меньше');
    end;
  end;
  ChiBranch(IdRoad, 'sqrt-three-roads');

  { ── Умножение длинных чисел: три дороги ── }
  for var Round := 1 to 400 do
  begin
    var X := Src.NextWord;
    var Y := Src.NextWord;
    W1 := MulSchool(X, Y);
    W2 := MulKaratsuba(X, Y);
    MulByOpcode(X, Y, @WR[0]);
    ChiClaim((W1.Lo = W2.Lo) and (W1.Hi = W2.Hi),
      'длинное умножение: столбиком и Карацуба разошлись');
    ChiClaim((W1.Lo = WR[0]) and (W1.Hi = WR[1]),
      'длинное умножение: столбиком и команда разошлись');
    ChiClaim(W1.Lo = X * Y, 'длинное умножение: младшая половина не сошлась с обычной');
    Acc := ChiMix(Acc, Int64(W1.Hi));
  end;
  { Края: предел, ноль, единица, степени двойки. }
  var Pairs: array [0 .. 5, 0 .. 1] of UInt64;
  Pairs[0][0] := 0;                              Pairs[0][1] := UInt64($FFFFFFFFFFFFFFFF);
  Pairs[1][0] := 1;                              Pairs[1][1] := UInt64($FFFFFFFFFFFFFFFF);
  Pairs[2][0] := UInt64($FFFFFFFFFFFFFFFF);      Pairs[2][1] := UInt64($FFFFFFFFFFFFFFFF);
  Pairs[3][0] := UInt64($100000000);             Pairs[3][1] := UInt64($100000000);
  Pairs[4][0] := UInt64($FFFFFFFF);              Pairs[4][1] := UInt64($FFFFFFFF);
  Pairs[5][0] := UInt64($8000000000000000);      Pairs[5][1] := 2;
  for var I := 0 to 5 do
  begin
    W1 := MulSchool(Pairs[I][0], Pairs[I][1]);
    W2 := MulKaratsuba(Pairs[I][0], Pairs[I][1]);
    MulByOpcode(Pairs[I][0], Pairs[I][1], @WR[0]);
    ChiClaim((W1.Lo = W2.Lo) and (W1.Hi = W2.Hi),
      'длинное умножение: край, столбиком против Карацубы');
    ChiClaim((W1.Lo = WR[0]) and (W1.Hi = WR[1]),
      'длинное умножение: край, столбиком против команды');
  end;
  ChiClaim((WR[0] = 0) and (WR[1] = 1), 'длинное умножение: сдвиг на разряд не сошёлся');
  ChiBranch(IdRoad, 'wide-mul-three-roads');

  { ── Суммирование: три дороги и порядок точности ── }
  for var I := 0 to 1023 do D[I] := 0.1;
  var S1 := SumSequential(@D[0], 1024);
  var S2 := SumPairwise(@D[0], 1024);
  var S3 := SumKahan(@D[0], 1024);
  ChiClaim(Abs(S3 - 102.4) <= Abs(S2 - 102.4), 'суммирование: попарное точнее компенсированного');
  ChiClaim(Abs(S2 - 102.4) <= Abs(S1 - 102.4), 'суммирование: последовательное точнее попарного');
  ChiClaim(S1 <> S3, 'суммирование: последовательное совпало с компенсированным — проверка вхолостую');
  ChiBranch(IdRoad, 'summation-order');

  { На числах одного порядка все три дороги обязаны сойтись точно: разница
    появляется только там, где младшие разряды теряются. }
  for var I := 0 to 255 do D[I] := I + 1;
  ChiClaim(SumSequential(@D[0], 256) = SumPairwise(@D[0], 256),
    'суммирование: на целых значениях дороги разошлись');
  ChiClaim(SumSequential(@D[0], 256) = SumKahan(@D[0], 256),
    'суммирование: компенсация изменила точный ответ');
  ChiClaim(SumSequential(@D[0], 256) = 32896, 'суммирование: известная сумма не сошлась');
  ChiBranch(IdRoad, 'summation-exact');
  Acc := ChiMix(Acc, Trunc(S3 * 1000));

  Result := Int64(Acc and $7FFFFFFFFFFF);
end;

end.
