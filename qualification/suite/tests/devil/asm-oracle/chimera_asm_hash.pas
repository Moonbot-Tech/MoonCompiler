unit chimera_asm_hash;

{ Орган «паскаль против ассемблера»: свёртки.

  Самая ценная часть этого семейства — там, где у процессора есть СВОЯ команда
  для всего алгоритма: контрольная сумма Кастаньоли считается либо табличным
  проходом на паскале, либо одной командой `crc32`. Это не «две записи одного
  цикла», а два принципиально разных пути к одному числу, и совпадение здесь
  доказывает и таблицу, и цикл, и работу с переносом разрядов.

  Остальные свёртки собраны так же, как их пишут в работе: накопитель, простое
  число, сдвиги, обход байтов. Ассемблерная сторона повторяет шаг в шаг —
  её задача быть очевидной, а не быстрой. }

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

function ChiAsmHashRun: Int64;

implementation

const
  IdHash = 'CHI-ASM-HASH-001';

var
  { Таблица для табличного прохода: строится один раз по определению. }
  CrcCTab: array [0 .. 255] of Cardinal;
  CrcZTab: array [0 .. 255] of Cardinal;

procedure BuildTables;
var
  C: Cardinal;
begin
  for var I := 0 to 255 do
  begin
    C := I;
    for var K := 1 to 8 do
      if (C and 1) <> 0
        then C := (C shr 1) xor $82F63B78    { Кастаньоли }
        else C := C shr 1;
    CrcCTab[I] := C;
    C := I;
    for var K := 1 to 8 do
      if (C and 1) <> 0
        then C := (C shr 1) xor $EDB88320    { обычный, как в архиваторах }
        else C := C shr 1;
    CrcZTab[I] := C;
  end;
end;

{ ═══ 1. Контрольная сумма Кастаньоли: таблица против команды ═════════════ }

function Crc32cPas(Crc: Cardinal; P: PByte; N: Integer): Cardinal;
begin
  Result := not Crc;
  for var I := 0 to N - 1 do
    Result := CrcCTab[(Result xor P[I]) and $FF] xor (Result shr 8);
  Result := not Result;
end;

{ Одна команда процессора на байт — совсем другая дорога к тому же числу. }
function Crc32cAsm(Crc: Cardinal; P: PByte; N: Integer): Cardinal; assembler; nostackframe;
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
        mov     eax, ecx
        not     eax
        test    r8d, r8d
        jle     @@done
        movsxd  r8, r8d
@@loop: crc32   eax, byte ptr [rdx]
        inc     rdx
        dec     r8
        jnz     @@loop
@@done: not     eax
end;

{ ═══ 2. Обычная контрольная сумма: таблица против побитового прохода ═════ }

function Crc32Pas(Crc: Cardinal; P: PByte; N: Integer): Cardinal;
begin
  Result := not Crc;
  for var I := 0 to N - 1 do
    Result := CrcZTab[(Result xor P[I]) and $FF] xor (Result shr 8);
  Result := not Result;
end;

{ Здесь у процессора команды нет, поэтому эталон честно крутит биты. }
function Crc32Asm(Crc: Cardinal; P: PByte; N: Integer): Cardinal; assembler; nostackframe;
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
        mov     eax, ecx
        not     eax
        test    r8d, r8d
        jle     @@done
        movsxd  r8, r8d
@@loop: movzx   r9d, byte ptr [rdx]
        xor     eax, r9d
        mov     r10d, 8
@@bits: mov     r9d, eax
        and     r9d, 1
        shr     eax, 1
        test    r9d, r9d
        jz      @@next
        xor     eax, $EDB88320
@@next: dec     r10d
        jnz     @@bits
        inc     rdx
        dec     r8
        jnz     @@loop
@@done: not     eax
end;

{ ═══ 3. Свёртка простым множителем ═══════════════════════════════════════ }

function FnvPas(P: PByte; N: Integer): UInt64;
begin
  Result := UInt64(14695981039346656037);
  for var I := 0 to N - 1 do
  begin
    Result := Result xor P[I];
    Result := Result * UInt64(1099511628211);
  end;
end;

{ Счётчик держится в R10: умножение пишет старшую половину в RDX, и счётчик
  там бы не пережил первого же оборота. }
function FnvAsm(P: PByte; N: Integer): UInt64; assembler; nostackframe;
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
        mov     rax, $CBF29CE484222325
        mov     r9, $100000001B3
        test    edx, edx
        jle     @@done
        movsxd  r10, edx
@@loop: movzx   r8d, byte ptr [rcx]
        xor     rax, r8
        mul     r9
        inc     rcx
        dec     r10
        jnz     @@loop
@@done:
end;

{ ═══ 4. Сумма Адлера ═════════════════════════════════════════════════════ }

function AdlerPas(P: PByte; N: Integer): Cardinal;
var
  A, B: Cardinal;
begin
  A := 1;
  B := 0;
  for var I := 0 to N - 1 do
  begin
    A := (A + P[I]) mod 65521;
    B := (B + A) mod 65521;
  end;
  Result := (B shl 16) or A;
end;

{ Деление пишет остаток в RDX, поэтому счётчик живёт в R8, а делитель в R11. }
function AdlerAsm(P: PByte; N: Integer): Cardinal; assembler; nostackframe;
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
        mov     r9d, 1           // A
        xor     r10d, r10d       // B
        test    edx, edx
        jle     @@done
        movsxd  r8, edx
        mov     r11d, 65521
@@loop: movzx   eax, byte ptr [rcx]
        add     r9d, eax
        mov     eax, r9d
        xor     edx, edx
        div     r11d
        mov     r9d, edx
        add     r10d, r9d
        mov     eax, r10d
        xor     edx, edx
        div     r11d
        mov     r10d, edx
        inc     rcx
        dec     r8
        jnz     @@loop
@@done: mov     eax, r10d
        shl     eax, 16
        or      eax, r9d
end;

{ ═══ 5. Сумма Флетчера ═══════════════════════════════════════════════════ }

function FletcherPas(P: PWord; N: Integer): Cardinal;
var
  S1, S2: Cardinal;
begin
  S1 := 0;
  S2 := 0;
  for var I := 0 to N - 1 do
  begin
    S1 := (S1 + P[I]) mod 65535;
    S2 := (S2 + S1) mod 65535;
  end;
  Result := (S2 shl 16) or S1;
end;

function FletcherAsm(P: PWord; N: Integer): Cardinal; assembler; nostackframe;
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
        xor     r9d, r9d         // S1
        xor     r10d, r10d       // S2
        test    edx, edx
        jle     @@done
        movsxd  r8, edx
        mov     r11d, 65535
@@loop: movzx   eax, word ptr [rcx]
        add     r9d, eax
        mov     eax, r9d
        xor     edx, edx
        div     r11d
        mov     r9d, edx
        add     r10d, r9d
        mov     eax, r10d
        xor     edx, edx
        div     r11d
        mov     r10d, edx
        add     rcx, 2
        dec     r8
        jnz     @@loop
@@done: mov     eax, r10d
        shl     eax, 16
        or      eax, r9d
end;

{ ═══ 6. Свёртка сдвигом и сложением ══════════════════════════════════════ }

function ShiftHashPas(P: PByte; N: Integer): Cardinal;
begin
  Result := 5381;
  for var I := 0 to N - 1 do
    Result := ((Result shl 5) + Result) + P[I];
end;

function ShiftHashAsm(P: PByte; N: Integer): Cardinal; assembler; nostackframe;
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
        mov     eax, 5381
        test    edx, edx
        jle     @@done
        movsxd  rdx, edx
@@loop: mov     r9d, eax
        shl     r9d, 5
        add     r9d, eax
        movzx   r8d, byte ptr [rcx]
        add     r9d, r8d
        mov     eax, r9d
        inc     rcx
        dec     rdx
        jnz     @@loop
@@done:
end;

{ ═══ 7. Перемешивание разрядов ═══════════════════════════════════════════ }

function MixPas(V: UInt64): UInt64;
begin
  V := V xor (V shr 33);
  V := V * UInt64($FF51AFD7ED558CCD);
  V := V xor (V shr 33);
  V := V * UInt64($C4CEB9FE1A85EC53);
  Result := V xor (V shr 33);
end;

function MixAsm(V: UInt64): UInt64; assembler; nostackframe;
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
        mov     r10, rax
        shr     r10, 33
        xor     rax, r10
        mov     r9, $FF51AFD7ED558CCD
        mul     r9
        mov     r10, rax
        shr     r10, 33
        xor     rax, r10
        mov     r9, $C4CEB9FE1A85EC53
        mul     r9
        mov     r10, rax
        shr     r10, 33
        xor     rax, r10
end;

{ ═══ 8. Свёртка со вращением ═════════════════════════════════════════════ }

function RotateHashPas(P: PByte; N: Integer): Cardinal;
begin
  Result := 0;
  for var I := 0 to N - 1 do
    Result := ((Result shl 7) or (Result shr 25)) xor P[I];
end;

function RotateHashAsm(P: PByte; N: Integer): Cardinal; assembler; nostackframe;
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
@@loop: rol     eax, 7
        movzx   r8d, byte ptr [rcx]
        xor     eax, r8d
        inc     rcx
        dec     rdx
        jnz     @@loop
@@done:
end;

{ ═══ Прогон ══════════════════════════════════════════════════════════════ }

function ChiAsmHashRun: Int64;
var
  Acc:  UInt64;
  Src:  TChiSource;
  Buf:  array [0 .. 1023] of Byte;
  W:    array [0 .. 511] of Word;
  V:    UInt64;
begin
  Acc := 0;
  ChiCovered(IdHash);
  BuildTables;
  Src := ChiSource(2718281828);

  { ── Кастаньоли: таблица против команды процессора ── }
  { Общепринятый пример — обе дороги могут ошибаться согласованно. }
  Move(PAnsiChar('123456789')^, Buf[0], 9);
  ChiClaim(Crc32cPas(0, @Buf[0], 9) = $E3069283, 'Кастаньоли: паскаль не дал известный ответ');
  ChiClaim(Crc32cAsm(0, @Buf[0], 9) = $E3069283, 'Кастаньоли: команда не дала известный ответ');
  ChiBranch(IdHash, 'crc32c-vector');

  for var N := 0 to 200 do
  begin
    for var I := 0 to N - 1 do Buf[I] := Byte(Src.NextBelow(256));
    ChiClaim(Crc32cPas(0, @Buf[0], N) = Crc32cAsm(0, @Buf[0], N),
      'Кастаньоли: таблица и команда разошлись на длине ' + IntToStr(N));
    { продолжение счёта кусками обязано дать то же, что счёт целиком }
    if N >= 4 then
    begin
      var Half := N div 2;
      var Part := Crc32cAsm(0, @Buf[0], Half);
      ChiClaim(Crc32cAsm(Part, @Buf[Half], N - Half) = Crc32cAsm(0, @Buf[0], N),
        'Кастаньоли: счёт кусками разошёлся с целым');
    end;
    Acc := ChiMix(Acc, Crc32cAsm(0, @Buf[0], N));
  end;
  ChiBranch(IdHash, 'crc32c-table-vs-opcode');

  { ── Обычная сумма: таблица против побитового прохода ── }
  Move(PAnsiChar('123456789')^, Buf[0], 9);
  ChiClaim(Crc32Pas(0, @Buf[0], 9) = $CBF43926, 'обычная сумма: известный ответ не сошёлся');
  for var N := 0 to 120 do
  begin
    for var I := 0 to N - 1 do Buf[I] := Byte(Src.NextBelow(256));
    ChiClaim(Crc32Pas(0, @Buf[0], N) = Crc32Asm(0, @Buf[0], N),
      'обычная сумма: таблица и биты разошлись на длине ' + IntToStr(N));
  end;
  ChiBranch(IdHash, 'crc32-table-vs-bits');

  { ── Свёртка простым множителем ── }
  ChiClaim(FnvPas(nil, 0) = UInt64(14695981039346656037), 'простой множитель: пустой вход не дал начальное');
  ChiClaim(FnvAsm(nil, 0) = UInt64(14695981039346656037), 'простой множитель: ассемблер на пустом входе');
  for var N := 0 to 200 do
  begin
    for var I := 0 to N - 1 do Buf[I] := Byte(Src.NextBelow(256));
    ChiClaim(FnvPas(@Buf[0], N) = FnvAsm(@Buf[0], N),
      'простой множитель: разошлись на длине ' + IntToStr(N));
    Acc := ChiMix(Acc, Int64(FnvAsm(@Buf[0], N)));
  end;
  ChiBranch(IdHash, 'fnv');

  { ── Сумма Адлера ── }
  Move(PAnsiChar('Wikipedia')^, Buf[0], 9);
  ChiClaim(AdlerPas(@Buf[0], 9) = $11E60398, 'Адлер: известный ответ не сошёлся');
  for var N := 0 to 200 do
  begin
    for var I := 0 to N - 1 do Buf[I] := Byte(Src.NextBelow(256));
    ChiClaim(AdlerPas(@Buf[0], N) = AdlerAsm(@Buf[0], N),
      'Адлер: разошлись на длине ' + IntToStr(N));
  end;
  ChiBranch(IdHash, 'adler');

  { ── Сумма Флетчера ── }
  for var N := 0 to 150 do
  begin
    for var I := 0 to N - 1 do W[I] := Word(Src.NextBelow(65536));
    ChiClaim(FletcherPas(@W[0], N) = FletcherAsm(@W[0], N),
      'Флетчер: разошлись на длине ' + IntToStr(N));
    Acc := ChiMix(Acc, FletcherAsm(@W[0], N));
  end;
  ChiBranch(IdHash, 'fletcher');

  { ── Сдвиг и вращение ── }
  for var N := 0 to 200 do
  begin
    for var I := 0 to N - 1 do Buf[I] := Byte(Src.NextBelow(256));
    ChiClaim(ShiftHashPas(@Buf[0], N) = ShiftHashAsm(@Buf[0], N),
      'свёртка сдвигом: разошлись на длине ' + IntToStr(N));
    ChiClaim(RotateHashPas(@Buf[0], N) = RotateHashAsm(@Buf[0], N),
      'свёртка вращением: разошлись на длине ' + IntToStr(N));
  end;
  ChiBranch(IdHash, 'shift-rotate');

  { ── Перемешивание разрядов ── }
  for var Round := 1 to 300 do
  begin
    V := Src.NextWord;
    ChiClaim(MixPas(V) = MixAsm(V), 'перемешивание: разошлись');
    Acc := ChiMix(Acc, Int64(MixAsm(V)));
  end;
  ChiClaim(MixPas(0) = 0, 'перемешивание: ноль перестал быть нулём');
  ChiClaim(MixAsm(0) = 0, 'перемешивание: ассемблер сделал из нуля не ноль');
  ChiClaim(MixAsm(1) <> 1, 'перемешивание: единица не перемешалась');
  ChiBranch(IdHash, 'mix');

  Result := Int64(Acc and $7FFFFFFFFFFF);
end;

end.
