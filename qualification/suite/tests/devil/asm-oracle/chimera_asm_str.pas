unit chimera_asm_str;

{ Орган «паскаль против ассемблера»: текст и его перекодировки.

  Всё, что здесь считается, живёт в проводе обоих продуктов: печатный вид
  подписи, шестнадцатеричный вид отпечатка, приведение имён рынков к одному
  регистру, проверка кадра на правильность кодировки. Паскальная сторона
  переносит эту работу как её пишут, ассемблерная — повторяет по шагам и
  служит эталоном.

  Особенность текстовых форм: почти в каждой есть таблица или диапазон, и
  ошибка на его краю не роняет программу, а тихо портит один символ. Поэтому
  везде, где есть граница диапазона, она перебирается поимённо. }

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

function ChiAsmStrRun: Int64;

implementation

const
  IdStr = 'CHI-ASM-STR-001';

{ ═══ 1. Приведение к верхнему регистру ═══════════════════════════════════ }

procedure UpperPas(P: PByte; N: Integer);
begin
  for var I := 0 to N - 1 do
    if (P[I] >= Ord('a')) and (P[I] <= Ord('z')) then
      P[I] := P[I] - 32;
end;

procedure UpperAsm(P: PByte; N: Integer); assembler; nostackframe;
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
@@loop: movzx   eax, byte ptr [rcx]
        cmp     eax, 'a'
        jb      @@next
        cmp     eax, 'z'
        ja      @@next
        sub     eax, 32
        mov     byte ptr [rcx], al
@@next: inc     rcx
        dec     rdx
        jnz     @@loop
@@done:
end;

{ ═══ 2. Приведение к нижнему регистру ════════════════════════════════════ }

procedure LowerPas(P: PByte; N: Integer);
begin
  for var I := 0 to N - 1 do
    if (P[I] >= Ord('A')) and (P[I] <= Ord('Z')) then
      P[I] := P[I] + 32;
end;

procedure LowerAsm(P: PByte; N: Integer); assembler; nostackframe;
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
@@loop: movzx   eax, byte ptr [rcx]
        cmp     eax, 'A'
        jb      @@next
        cmp     eax, 'Z'
        ja      @@next
        add     eax, 32
        mov     byte ptr [rcx], al
@@next: inc     rcx
        dec     rdx
        jnz     @@loop
@@done:
end;

{ ═══ 3. Сравнение без учёта регистра ═════════════════════════════════════ }

function SameTextPas(A, B: PByte; N: Integer): Boolean;
var
  X, Y: Byte;
begin
  for var I := 0 to N - 1 do
  begin
    X := A[I];
    Y := B[I];
    if (X >= Ord('a')) and (X <= Ord('z')) then X := X - 32;
    if (Y >= Ord('a')) and (Y <= Ord('z')) then Y := Y - 32;
    if X <> Y then Exit(False);
  end;
  Result := True;
end;

function SameTextAsm(A, B: PByte; N: Integer): Boolean; assembler; nostackframe;
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
        test    r8d, r8d
        jle     @@done
        movsxd  r8, r8d
@@loop: movzx   r9d, byte ptr [rcx]
        movzx   r10d, byte ptr [rdx]
        cmp     r9d, 'a'
        jb      @@second
        cmp     r9d, 'z'
        ja      @@second
        sub     r9d, 32
@@second:
        cmp     r10d, 'a'
        jb      @@cmp
        cmp     r10d, 'z'
        ja      @@cmp
        sub     r10d, 32
@@cmp:  cmp     r9d, r10d
        jne     @@differ
        inc     rcx
        inc     rdx
        dec     r8
        jnz     @@loop
        jmp     @@done
@@differ:
        xor     eax, eax
@@done:
end;

{ ═══ 4. Шестнадцатеричный вид ════════════════════════════════════════════ }

const
  HexDigits: array [0 .. 15] of AnsiChar = '0123456789abcdef';

procedure BinToHexPas(Src: PByte; Dst: PByte; N: Integer);
begin
  for var I := 0 to N - 1 do
  begin
    Dst[I * 2] := Byte(HexDigits[Src[I] shr 4]);
    Dst[I * 2 + 1] := Byte(HexDigits[Src[I] and $0F]);
  end;
end;

procedure BinToHexAsm(Src: PByte; Dst: PByte; N: Integer); assembler; nostackframe;
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
@@loop: movzx   eax, byte ptr [rcx]
        mov     r9d, eax
        shr     r9d, 4
        and     eax, $0F
        cmp     r9d, 10
        jb      @@hi9
        add     r9d, 'a' - 10
        jmp     @@hiout
@@hi9:  add     r9d, '0'
@@hiout:mov     byte ptr [rdx], r9b
        cmp     eax, 10
        jb      @@lo9
        add     eax, 'a' - 10
        jmp     @@loout
@@lo9:  add     eax, '0'
@@loout:mov     byte ptr [rdx + 1], al
        inc     rcx
        add     rdx, 2
        dec     r8
        jnz     @@loop
@@done:
end;

{ ═══ 5. Разбор шестнадцатеричного вида ═══════════════════════════════════ }

function HexToBinPas(Src: PByte; Dst: PByte; N: Integer): Boolean;
var
  H, L: Integer;

  function Digit(C: Byte): Integer;
  begin
    if (C >= Ord('0')) and (C <= Ord('9')) then Exit(C - Ord('0'));
    if (C >= Ord('a')) and (C <= Ord('f')) then Exit(C - Ord('a') + 10);
    if (C >= Ord('A')) and (C <= Ord('F')) then Exit(C - Ord('A') + 10);
    Result := -1;
  end;

begin
  for var I := 0 to N - 1 do
  begin
    H := Digit(Src[I * 2]);
    L := Digit(Src[I * 2 + 1]);
    if (H < 0) or (L < 0) then Exit(False);
    Dst[I] := Byte(H * 16 + L);
  end;
  Result := True;
end;

function HexToBinAsm(Src: PByte; Dst: PByte; N: Integer): Boolean; assembler; nostackframe;
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
        test    r8d, r8d
        jle     @@done
        movsxd  r8, r8d
@@loop: movzx   r9d, byte ptr [rcx]
        call    @@digit
        cmp     r9d, 0
        jl      @@bad
        mov     r11d, r9d
        shl     r11d, 4
        movzx   r9d, byte ptr [rcx + 1]
        call    @@digit
        cmp     r9d, 0
        jl      @@bad
        add     r11d, r9d
        mov     byte ptr [rdx], r11b
        add     rcx, 2
        inc     rdx
        dec     r8
        jnz     @@loop
        jmp     @@done
@@bad:  xor     eax, eax
        jmp     @@done
@@digit:
        cmp     r9d, '0'
        jb      @@nodigit
        cmp     r9d, '9'
        ja      @@lower
        sub     r9d, '0'
        ret
@@lower:cmp     r9d, 'a'
        jb      @@upper
        cmp     r9d, 'f'
        ja      @@nodigit
        sub     r9d, 'a' - 10
        ret
@@upper:cmp     r9d, 'A'
        jb      @@nodigit
        cmp     r9d, 'F'
        ja      @@nodigit
        sub     r9d, 'A' - 10
        ret
@@nodigit:
        mov     r9d, -1
        ret
@@done:
end;

{ ═══ 6. Печатный вид ═════════════════════════════════════════════════════ }

const
  B64Digits: array [0 .. 63] of AnsiChar =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

function Base64Pas(Src: PByte; N: Integer; Dst: PByte): Integer;
var
  Chunk: Cardinal;
  I:     Integer;
begin
  Result := 0;
  I := 0;
  while I < N do
  begin
    Chunk := Cardinal(Src[I]) shl 16;
    if I + 1 < N then Chunk := Chunk or (Cardinal(Src[I + 1]) shl 8);
    if I + 2 < N then Chunk := Chunk or Cardinal(Src[I + 2]);
    Dst[Result] := Byte(B64Digits[(Chunk shr 18) and 63]);
    Dst[Result + 1] := Byte(B64Digits[(Chunk shr 12) and 63]);
    if I + 1 < N
      then Dst[Result + 2] := Byte(B64Digits[(Chunk shr 6) and 63])
      else Dst[Result + 2] := Byte('=');
    if I + 2 < N
      then Dst[Result + 3] := Byte(B64Digits[Chunk and 63])
      else Dst[Result + 3] := Byte('=');
    Inc(Result, 4);
    Inc(I, 3);
  end;
end;

{ Ассемблерная сторона берёт буквы из той же таблицы, но собирает тройку
  своими сдвигами — сравнение ловит ошибку в разборе тройки на четвёрки. }
function Base64Asm(Src: PByte; N: Integer; Dst: PByte): Integer; assembler; nostackframe;
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
        xor     r9, r9           // прочитано байтов
@@loop: cmp     r9, rdx
        jge     @@done
        movzx   r10d, byte ptr [rcx + r9]
        shl     r10d, 16
        mov     r11, r9
        inc     r11
        cmp     r11, rdx
        jge     @@one
        movzx   eax, byte ptr [rcx + r11]
        shl     eax, 8
        or      r10d, eax
        inc     r11
        cmp     r11, rdx
        jge     @@two
        movzx   eax, byte ptr [rcx + r11]
        or      r10d, eax
@@two:
@@one:
        { первые две буквы всегда }
        mov     eax, r10d
        shr     eax, 18
        and     eax, 63
        lea     r11, [rip + B64Digits]
        movzx   eax, byte ptr [r11 + rax]
        mov     byte ptr [r8], al
        mov     eax, r10d
        shr     eax, 12
        and     eax, 63
        movzx   eax, byte ptr [r11 + rax]
        mov     byte ptr [r8 + 1], al
        { третья — если был второй байт }
        mov     rax, r9
        add     rax, 1
        cmp     rax, rdx
        jge     @@pad3
        mov     eax, r10d
        shr     eax, 6
        and     eax, 63
        movzx   eax, byte ptr [r11 + rax]
        mov     byte ptr [r8 + 2], al
        jmp     @@third
@@pad3: mov     byte ptr [r8 + 2], '='
@@third:
        { четвёртая — если был третий байт }
        mov     rax, r9
        add     rax, 2
        cmp     rax, rdx
        jge     @@pad4
        mov     eax, r10d
        and     eax, 63
        movzx   eax, byte ptr [r11 + rax]
        mov     byte ptr [r8 + 3], al
        jmp     @@fourth
@@pad4: mov     byte ptr [r8 + 3], '='
@@fourth:
        add     r8, 4
        add     r9, 3
        jmp     @@loop
@@done:
        { длина = число четвёрок * 4 }
        mov     rax, rdx
        add     rax, 2
        xor     rdx, rdx
        mov     r10, 3
        div     r10
        shl     rax, 2
end;

{ ═══ 7. Правильность кодировки ═══════════════════════════════════════════ }

function ValidUtf8Pas(P: PByte; N: Integer): Boolean;
var
  I, Need: Integer;
  B, Lo:   Byte;
begin
  I := 0;
  while I < N do
  begin
    B := P[I];
    if B < $80 then
    begin
      Inc(I);
      Continue;
    end;
    Lo := $80;
    if (B >= $C2) and (B <= $DF) then Need := 1
    else if B = $E0 then begin Need := 2; Lo := $A0; end
    else if (B >= $E1) and (B <= $EF) then Need := 2
    else if B = $F0 then begin Need := 3; Lo := $90; end
    else if (B >= $F1) and (B <= $F4) then Need := 3
    else Exit(False);
    if I + Need >= N then Exit(False);
    if (P[I + 1] < Lo) or (P[I + 1] > $BF) then Exit(False);
    for var K := 2 to Need do
      if (P[I + K] < $80) or (P[I + K] > $BF) then Exit(False);
    Inc(I, Need + 1);
  end;
  Result := True;
end;

function ValidUtf8Asm(P: PByte; N: Integer): Boolean; assembler; nostackframe;
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
        xor     r9, r9           // позиция
@@loop: cmp     r9, rdx
        jge     @@done
        movzx   r10d, byte ptr [rcx + r9]
        cmp     r10d, $80
        jb      @@ascii
        mov     r11d, $80        // нижняя граница второго байта
        cmp     r10d, $C2
        jb      @@bad
        cmp     r10d, $DF
        jbe     @@need1
        cmp     r10d, $E0
        jne     @@e1
        mov     r11d, $A0
        jmp     @@need2
@@e1:   cmp     r10d, $EF
        jbe     @@need2
        cmp     r10d, $F0
        jne     @@f1
        mov     r11d, $90
        jmp     @@need3
@@f1:   cmp     r10d, $F4
        ja      @@bad
        jmp     @@need3
@@ascii:inc     r9
        jmp     @@loop
@@need1:mov     r8d, 1
        jmp     @@tail
@@need2:mov     r8d, 2
        jmp     @@tail
@@need3:mov     r8d, 3
@@tail: mov     rax, r9
        add     rax, r8
        cmp     rax, rdx
        jge     @@bad
        { первый хвостовой байт: своя нижняя граница }
        movzx   eax, byte ptr [rcx + r9 + 1]
        cmp     eax, r11d
        jb      @@bad
        cmp     eax, $BF
        ja      @@bad
        { остальные хвостовые }
        mov     r11d, 2
@@rest: cmp     r11d, r8d
        jg      @@ok
        mov     rax, r9
        add     rax, r11
        movzx   eax, byte ptr [rcx + rax]
        cmp     eax, $80
        jb      @@bad
        cmp     eax, $BF
        ja      @@bad
        inc     r11d
        jmp     @@rest
@@ok:   add     r9, r8
        inc     r9
        mov     eax, 1
        jmp     @@loop
@@bad:  xor     eax, eax
@@done:
end;

{ ═══ Прогон ══════════════════════════════════════════════════════════════ }

function ChiAsmStrRun: Int64;
var
  Acc:  UInt64;
  Src:  TChiSource;
  A, B: array [0 .. 511] of Byte;
  H1, H2: array [0 .. 1039] of Byte;
  D1, D2: array [0 .. 511] of Byte;
begin
  Acc := 0;
  ChiCovered(IdStr);
  Src := ChiSource(1414213562);

  { ── Регистр: границы диапазона поимённо ── }
  for var C := 0 to 255 do
  begin
    A[0] := Byte(C);
    B[0] := Byte(C);
    UpperPas(@A[0], 1);
    UpperAsm(@B[0], 1);
    ChiClaim(A[0] = B[0], 'верхний регистр: разошлись на коде ' + IntToStr(C));
    A[0] := Byte(C);
    B[0] := Byte(C);
    LowerPas(@A[0], 1);
    LowerAsm(@B[0], 1);
    ChiClaim(A[0] = B[0], 'нижний регистр: разошлись на коде ' + IntToStr(C));
  end;
  { Соседи границ обязаны остаться нетронутыми. }
  A[0] := Ord('a') - 1;
  A[1] := Ord('z') + 1;
  A[2] := Ord('A') - 1;
  A[3] := Ord('Z') + 1;
  UpperAsm(@A[0], 4);
  ChiClaim((A[0] = Ord('a') - 1) and (A[1] = Ord('z') + 1),
    'верхний регистр: тронул соседей диапазона');
  ChiBranch(IdStr, 'case-bounds');

  for var Round := 1 to 40 do
  begin
    var N := 1 + Src.NextBelow(511);
    for var I := 0 to N - 1 do
    begin
      A[I] := Byte(Src.NextBelow(256));
      B[I] := A[I];
    end;
    UpperPas(@A[0], N);
    UpperAsm(@B[0], N);
    ChiClaim(CompareMem(@A[0], @B[0], N), 'верхний регистр: разошлись на длине');
    LowerPas(@A[0], N);
    LowerAsm(@B[0], N);
    ChiClaim(CompareMem(@A[0], @B[0], N), 'нижний регистр: разошлись на длине');
  end;
  ChiBranch(IdStr, 'case-random');

  { ── Сравнение без учёта регистра ── }
  for var Round := 1 to 60 do
  begin
    var N := 1 + Src.NextBelow(60);
    for var I := 0 to N - 1 do
    begin
      A[I] := Byte(Ord('A') + Src.NextBelow(58));
      if Src.NextBelow(2) = 0
        then B[I] := A[I]
        else if (A[I] >= Ord('A')) and (A[I] <= Ord('Z'))
          then B[I] := A[I] + 32
          else B[I] := A[I];
    end;
    ChiClaim(SameTextPas(@A[0], @B[0], N) = SameTextAsm(@A[0], @B[0], N),
      'сравнение без регистра: разошлись');
  end;
  A[0] := Ord('B'); B[0] := Ord('b');
  ChiClaim(SameTextAsm(@A[0], @B[0], 1), 'сравнение без регистра: буква не признана');
  A[0] := Ord('['); B[0] := Ord('{');   { соседи букв в таблице }
  ChiClaim(not SameTextAsm(@A[0], @B[0], 1), 'сравнение без регистра: соседи букв слились');
  ChiBranch(IdStr, 'sametext');

  { ── Шестнадцатеричный вид ── }
  for var N := 0 to 200 do
  begin
    for var I := 0 to N - 1 do A[I] := Byte(Src.NextBelow(256));
    BinToHexPas(@A[0], @H1[0], N);
    BinToHexAsm(@A[0], @H2[0], N);
    ChiClaim(CompareMem(@H1[0], @H2[0], N * 2),
      'шестнадцатеричный вид: разошлись на длине ' + IntToStr(N));
    ChiClaim(HexToBinPas(@H1[0], @D1[0], N), 'разбор: паскаль отверг свой же вывод');
    ChiClaim(HexToBinAsm(@H2[0], @D2[0], N), 'разбор: ассемблер отверг свой же вывод');
    ChiClaim(CompareMem(@D1[0], @D2[0], N), 'разбор: разошлись');
    ChiClaim(CompareMem(@A[0], @D1[0], N), 'разбор: круговой обход исказил байты');
  end;
  ChiBranch(IdStr, 'hex-roundtrip');

  { Верхний регистр букв в разборе, и негодные символы. }
  H1[0] := Ord('A'); H1[1] := Ord('F');
  ChiClaim(HexToBinAsm(@H1[0], @D1[0], 1) and (D1[0] = $AF),
    'разбор: заглавные буквы не приняты');
  H1[0] := Ord('g'); H1[1] := Ord('0');
  ChiClaim(not HexToBinAsm(@H1[0], @D1[0], 1), 'разбор: негодный символ принят');
  H1[0] := Ord('0'); H1[1] := Ord('/');
  ChiClaim(not HexToBinAsm(@H1[0], @D1[0], 1), 'разбор: символ ниже нуля принят');
  ChiClaim(not HexToBinPas(@H1[0], @D1[0], 1), 'разбор: паскаль принял негодный символ');
  ChiBranch(IdStr, 'hex-bad-input');

  { ── Печатный вид ── }
  for var N := 0 to 120 do
  begin
    for var I := 0 to N - 1 do A[I] := Byte(Src.NextBelow(256));
    var L1 := Base64Pas(@A[0], N, @H1[0]);
    var L2 := Base64Asm(@A[0], N, @H2[0]);
    ChiClaim(L1 = L2, 'печатный вид: длины разошлись на ' + IntToStr(N));
    ChiClaim(CompareMem(@H1[0], @H2[0], L1),
      'печатный вид: байты разошлись на длине ' + IntToStr(N));
  end;
  { Общепринятые примеры: обе дороги могут ошибаться согласованно. }
  Move(PAnsiChar('f')^, A[0], 1);
  Base64Asm(@A[0], 1, @H2[0]);
  ChiClaim(CompareMem(@H2[0], PAnsiChar('Zg=='), 4), 'печатный вид: один байт неверен');
  Move(PAnsiChar('fo')^, A[0], 2);
  Base64Asm(@A[0], 2, @H2[0]);
  ChiClaim(CompareMem(@H2[0], PAnsiChar('Zm8='), 4), 'печатный вид: два байта неверны');
  Move(PAnsiChar('foobar')^, A[0], 6);
  Base64Asm(@A[0], 6, @H2[0]);
  ChiClaim(CompareMem(@H2[0], PAnsiChar('Zm9vYmFy'), 8), 'печатный вид: шесть байт неверны');
  ChiBranch(IdStr, 'base64');
  Acc := ChiMix(Acc, Base64Asm(@A[0], 6, @H2[0]));

  { ── Правильность кодировки ── }
  for var Round := 1 to 300 do
  begin
    var N := 1 + Src.NextBelow(40);
    for var I := 0 to N - 1 do
      case Src.NextBelow(4) of
        0: A[I] := Byte(Src.NextBelow(128));           { простые }
        1: A[I] := Byte($C2 + Src.NextBelow(30));      { начала пар }
        2: A[I] := Byte($80 + Src.NextBelow(64));      { хвосты }
      else A[I] := Byte(Src.NextBelow(256));           { что угодно }
      end;
    ChiClaim(ValidUtf8Pas(@A[0], N) = ValidUtf8Asm(@A[0], N),
      'кодировка: разошлись на случайном образце');
  end;
  { Поимённые образцы. }
  A[0] := $D0; A[1] := $9F;
  ChiClaim(ValidUtf8Asm(@A[0], 2), 'кодировка: правильная пара отвергнута');
  ChiClaim(not ValidUtf8Asm(@A[0], 1), 'кодировка: оборванная пара принята');
  A[0] := $E2; A[1] := $82; A[2] := $AC;
  ChiClaim(ValidUtf8Asm(@A[0], 3), 'кодировка: правильная тройка отвергнута');
  ChiClaim(not ValidUtf8Asm(@A[0], 2), 'кодировка: оборванная тройка принята');
  A[0] := $C0; A[1] := $AF;
  ChiClaim(not ValidUtf8Asm(@A[0], 2), 'кодировка: избыточная запись принята');
  A[0] := $E0; A[1] := $80; A[2] := $80;
  ChiClaim(not ValidUtf8Asm(@A[0], 3), 'кодировка: заниженный хвост принят');
  A[0] := $F5; A[1] := $80; A[2] := $80; A[3] := $80;
  ChiClaim(not ValidUtf8Asm(@A[0], 4), 'кодировка: значение за пределом принято');
  A[0] := $80;
  ChiClaim(not ValidUtf8Asm(@A[0], 1), 'кодировка: хвост без начала принят');
  ChiBranch(IdStr, 'utf8');

  Result := Int64(Acc and $7FFFFFFFFFFF);
end;

end.
