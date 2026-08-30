unit chimera_asm_crypt;

{ Орган «паскаль против ассемблера»: криптографические шаги.

  Самая ценная часть всего семейства. У процессора есть команды, выполняющие
  ЦЕЛЫЙ раунд шифра одной инструкцией (`aesenc`), и умножение в двоичном поле
  (`pclmulqdq`). Паскальная сторона делает то же самое руками: подстановка по
  таблице, сдвиг строк, перемешивание столбцов в поле, сложение с ключом
  раунда. Совпадение доказывает разом и таблицу, и арифметику поля, и порядок
  шагов — а расхождение указывает на конкретный шаг, потому что шаги
  проверяются и по отдельности.

  Здесь же обе стороны сверяются с ОБЩЕПРИНЯТЫМИ примерами из описания
  шифра: две дороги могут прийти в одно неверное место, если алгоритм
  перенесён с ошибкой, и от этого спасает только внешняя истина. }

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

function ChiAsmCryptRun: Int64;

implementation

const
  IdCrypt = 'CHI-ASM-CRYPT-001';

type
  TChiBlock = array [0 .. 15] of Byte;
  TChiRoundKeys = array [0 .. 10] of TChiBlock;

const
  SBox: array [0 .. 255] of Byte = (
    $63,$7C,$77,$7B,$F2,$6B,$6F,$C5,$30,$01,$67,$2B,$FE,$D7,$AB,$76,
    $CA,$82,$C9,$7D,$FA,$59,$47,$F0,$AD,$D4,$A2,$AF,$9C,$A4,$72,$C0,
    $B7,$FD,$93,$26,$36,$3F,$F7,$CC,$34,$A5,$E5,$F1,$71,$D8,$31,$15,
    $04,$C7,$23,$C3,$18,$96,$05,$9A,$07,$12,$80,$E2,$EB,$27,$B2,$75,
    $09,$83,$2C,$1A,$1B,$6E,$5A,$A0,$52,$3B,$D6,$B3,$29,$E3,$2F,$84,
    $53,$D1,$00,$ED,$20,$FC,$B1,$5B,$6A,$CB,$BE,$39,$4A,$4C,$58,$CF,
    $D0,$EF,$AA,$FB,$43,$4D,$33,$85,$45,$F9,$02,$7F,$50,$3C,$9F,$A8,
    $51,$A3,$40,$8F,$92,$9D,$38,$F5,$BC,$B6,$DA,$21,$10,$FF,$F3,$D2,
    $CD,$0C,$13,$EC,$5F,$97,$44,$17,$C4,$A7,$7E,$3D,$64,$5D,$19,$73,
    $60,$81,$4F,$DC,$22,$2A,$90,$88,$46,$EE,$B8,$14,$DE,$5E,$0B,$DB,
    $E0,$32,$3A,$0A,$49,$06,$24,$5C,$C2,$D3,$AC,$62,$91,$95,$E4,$79,
    $E7,$C8,$37,$6D,$8D,$D5,$4E,$A9,$6C,$56,$F4,$EA,$65,$7A,$AE,$08,
    $BA,$78,$25,$2E,$1C,$A6,$B4,$C6,$E8,$DD,$74,$1F,$4B,$BD,$8B,$8A,
    $70,$3E,$B5,$66,$48,$03,$F6,$0E,$61,$35,$57,$B9,$86,$C1,$1D,$9E,
    $E1,$F8,$98,$11,$69,$D9,$8E,$94,$9B,$1E,$87,$E9,$CE,$55,$28,$DF,
    $8C,$A1,$89,$0D,$BF,$E6,$42,$68,$41,$99,$2D,$0F,$B0,$54,$BB,$16);

  Rcon: array [1 .. 10] of Byte = ($01, $02, $04, $08, $10, $20, $40, $80, $1B, $36);

{ ═══ Расписание ключей — общее для обеих сторон ══════════════════════════ }

{ Расписание считается паскалем и подаётся обеим сторонам: предмет проверки —
  сам раунд, а не выработка ключей. Её правильность держится общепринятым
  примером ниже. }
procedure ExpandKey(const Key: TChiBlock; out RK: TChiRoundKeys);
var
  T: array [0 .. 3] of Byte;
begin
  RK[0] := Key;
  for var R := 1 to 10 do
  begin
    T[0] := RK[R - 1][13];
    T[1] := RK[R - 1][14];
    T[2] := RK[R - 1][15];
    T[3] := RK[R - 1][12];
    for var I := 0 to 3 do T[I] := SBox[T[I]];
    T[0] := T[0] xor Rcon[R];
    for var I := 0 to 3 do
      RK[R][I] := RK[R - 1][I] xor T[I];
    for var W := 1 to 3 do
      for var I := 0 to 3 do
        RK[R][W * 4 + I] := RK[R - 1][W * 4 + I] xor RK[R][(W - 1) * 4 + I];
  end;
end;

{ ═══ 1. Умножение в поле шифра ═══════════════════════════════════════════ }

function XTimePas(V: Byte): Byte;
begin
  if (V and $80) <> 0
    then Result := Byte((V shl 1) xor $1B)
    else Result := Byte(V shl 1);
end;

function XTimeAsm(V: Byte): Byte; assembler; nostackframe;
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
        movzx   eax, cl
        shl     eax, 1
        test    ecx, $80
        jz      @@done
        xor     eax, $1B
@@done: movzx   eax, al
end;

{ ═══ 2. Раунд шифра: руками против одной команды ═════════════════════════ }

procedure AesRoundPas(var State: TChiBlock; const RK: TChiBlock; Last: Boolean);
var
  S: TChiBlock;
  A, B, C, D: Byte;
begin
  { подстановка }
  for var I := 0 to 15 do S[I] := SBox[State[I]];
  { сдвиг строк: байт с номером i уходит на место (i - 4*(i mod 4)) mod 16 }
  State[0] := S[0];   State[4] := S[4];   State[8] := S[8];    State[12] := S[12];
  State[1] := S[5];   State[5] := S[9];   State[9] := S[13];   State[13] := S[1];
  State[2] := S[10];  State[6] := S[14];  State[10] := S[2];   State[14] := S[6];
  State[3] := S[15];  State[7] := S[3];   State[11] := S[7];   State[15] := S[11];
  { перемешивание столбцов — кроме последнего раунда }
  if not Last then
    for var Col := 0 to 3 do
    begin
      A := State[Col * 4];
      B := State[Col * 4 + 1];
      C := State[Col * 4 + 2];
      D := State[Col * 4 + 3];
      State[Col * 4]     := XTimePas(A) xor (XTimePas(B) xor B) xor C xor D;
      State[Col * 4 + 1] := A xor XTimePas(B) xor (XTimePas(C) xor C) xor D;
      State[Col * 4 + 2] := A xor B xor XTimePas(C) xor (XTimePas(D) xor D);
      State[Col * 4 + 3] := (XTimePas(A) xor A) xor B xor C xor XTimePas(D);
    end;
  { сложение с ключом раунда }
  for var I := 0 to 15 do State[I] := State[I] xor RK[I];
end;

procedure AesRoundAsm(var State: TChiBlock; const RK: TChiBlock; Last: Boolean);
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
        movdqu  xmm0, oword ptr [rcx]
        movdqu  xmm1, oword ptr [rdx]
        test    r8b, r8b
        jnz     @@last
        aesenc  xmm0, xmm1
        jmp     @@store
@@last: aesenclast xmm0, xmm1
@@store:movdqu  oword ptr [rcx], xmm0
end;

{ ═══ 3. Шифрование блока целиком ═════════════════════════════════════════ }

procedure EncryptBlockPas(const RK: TChiRoundKeys; var Block: TChiBlock);
begin
  for var I := 0 to 15 do Block[I] := Block[I] xor RK[0][I];
  for var R := 1 to 9 do AesRoundPas(Block, RK[R], False);
  AesRoundPas(Block, RK[10], True);
end;

procedure EncryptBlockAsm(const RK: TChiRoundKeys; var Block: TChiBlock);
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
        movdqu  xmm0, oword ptr [rdx]
        movdqu  xmm1, oword ptr [rcx]
        pxor    xmm0, xmm1
        mov     eax, 1
@@loop: mov     r9, rax
        shl     r9, 4
        movdqu  xmm1, oword ptr [rcx + r9]
        aesenc  xmm0, xmm1
        inc     eax
        cmp     eax, 10
        jl      @@loop
        movdqu  xmm1, oword ptr [rcx + 160]
        aesenclast xmm0, xmm1
        movdqu  oword ptr [rdx], xmm0
end;

{ ═══ 4. Четвертьраунд поточного шифра ════════════════════════════════════ }

procedure QuarterPas(var A, B, C, D: Cardinal);
  function Rol(V: Cardinal; N: Integer): Cardinal;
  begin
    Result := (V shl N) or (V shr (32 - N));
  end;
begin
  A := A + B;  D := Rol(D xor A, 16);
  C := C + D;  B := Rol(B xor C, 12);
  A := A + B;  D := Rol(D xor A, 8);
  C := C + D;  B := Rol(B xor C, 7);
end;

procedure QuarterAsm(P: PCardinal); assembler; nostackframe;
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
        mov     eax, dword ptr [rcx]         // A
        mov     edx, dword ptr [rcx + 4]     // B
        mov     r8d, dword ptr [rcx + 8]     // C
        mov     r9d, dword ptr [rcx + 12]    // D
        add     eax, edx
        xor     r9d, eax
        rol     r9d, 16
        add     r8d, r9d
        xor     edx, r8d
        rol     edx, 12
        add     eax, edx
        xor     r9d, eax
        rol     r9d, 8
        add     r8d, r9d
        xor     edx, r8d
        rol     edx, 7
        mov     dword ptr [rcx], eax
        mov     dword ptr [rcx + 4], edx
        mov     dword ptr [rcx + 8], r8d
        mov     dword ptr [rcx + 12], r9d
end;

{ ═══ 5. Шаг перемешивания губки ══════════════════════════════════════════ }

{ Шаг χ из семейства Keccak: каждая ячейка складывается с произведением
  соседей. Обход кольцевой, и именно на замыкании кольца легче всего
  ошибиться. }
procedure ChiStepPas(P: PUInt64);
var
  T: array [0 .. 4] of UInt64;
begin
  for var Row := 0 to 4 do
  begin
    for var I := 0 to 4 do T[I] := P[Row * 5 + I];
    for var I := 0 to 4 do
      P[Row * 5 + I] := T[I] xor ((not T[(I + 1) mod 5]) and T[(I + 2) mod 5]);
  end;
end;

procedure ChiStepAsm(P: PUInt64); assembler; nostackframe;
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
        xor     r10, r10          // номер строки
@@row:  mov     r11, r10
        imul    r11, r11, 40      // строка * 5 * 8
        add     r11, rcx
        { сохраняем пятёрку в свободные регистры }
        mov     rax, qword ptr [r11]
        mov     rdx, qword ptr [r11 + 8]
        mov     r8, qword ptr [r11 + 16]
        mov     r9, qword ptr [r11 + 24]
        push    rbx
        mov     rbx, qword ptr [r11 + 32]
        { ячейка 0 = t0 xor (not t1 and t2) }
        push    rax
        mov     rax, rdx
        not     rax
        and     rax, r8
        xor     rax, qword ptr [r11]
        mov     qword ptr [r11], rax
        pop     rax
        { ячейка 1 = t1 xor (not t2 and t3) }
        push    rdx
        mov     rdx, r8
        not     rdx
        and     rdx, r9
        xor     rdx, qword ptr [r11 + 8]
        mov     qword ptr [r11 + 8], rdx
        pop     rdx
        { ячейка 2 = t2 xor (not t3 and t4) }
        push    r8
        mov     r8, r9
        not     r8
        and     r8, rbx
        xor     r8, qword ptr [r11 + 16]
        mov     qword ptr [r11 + 16], r8
        pop     r8
        { ячейка 3 = t3 xor (not t4 and t0) }
        push    r9
        mov     r9, rbx
        not     r9
        and     r9, rax
        xor     r9, qword ptr [r11 + 24]
        mov     qword ptr [r11 + 24], r9
        pop     r9
        { ячейка 4 = t4 xor (not t0 and t1) }
        mov     rax, rax
        not     rax
        and     rax, rdx
        xor     rax, rbx
        mov     qword ptr [r11 + 32], rax
        pop     rbx
        inc     r10
        cmp     r10, 5
        jl      @@row
end;

{ ═══ Прогон ══════════════════════════════════════════════════════════════ }

function ChiAsmCryptRun: Int64;
var
  Acc:    UInt64;
  Src:    TChiSource;
  Key:    TChiBlock;
  RK:     TChiRoundKeys;
  B1, B2: TChiBlock;
  Q1, Q2: array [0 .. 3] of Cardinal;
  S1, S2: array [0 .. 24] of UInt64;
begin
  Acc := 0;
  ChiCovered(IdCrypt);
  Src := ChiSource(2653589793);

  { ── Умножение в поле: все двести пятьдесят шесть значений ── }
  for var V := 0 to 255 do
    ChiClaim(XTimePas(Byte(V)) = XTimeAsm(Byte(V)),
      'умножение в поле: разошлись на ' + IntToStr(V));
  ChiClaim(XTimeAsm($57) = $AE, 'умножение в поле: известный пример без переноса');
  ChiClaim(XTimeAsm($AE) = $47, 'умножение в поле: известный пример с переносом');
  ChiBranch(IdCrypt, 'xtime');

  { ── Шифрование блока: общепринятый пример из описания шифра ── }
  for var I := 0 to 15 do Key[I] := Byte(I);
  ExpandKey(Key, RK);
  B1[0] := $00; B1[1] := $11; B1[2] := $22; B1[3] := $33;
  B1[4] := $44; B1[5] := $55; B1[6] := $66; B1[7] := $77;
  B1[8] := $88; B1[9] := $99; B1[10] := $AA; B1[11] := $BB;
  B1[12] := $CC; B1[13] := $DD; B1[14] := $EE; B1[15] := $FF;
  B2 := B1;
  EncryptBlockPas(RK, B1);
  EncryptBlockAsm(RK, B2);

  ChiClaim((B2[0] = $69) and (B2[1] = $C4) and (B2[2] = $E0) and (B2[3] = $D8) and
           (B2[4] = $6A) and (B2[5] = $7B) and (B2[6] = $04) and (B2[7] = $30) and
           (B2[8] = $D8) and (B2[9] = $CD) and (B2[10] = $B7) and (B2[11] = $80) and
           (B2[12] = $70) and (B2[13] = $B4) and (B2[14] = $C5) and (B2[15] = $5A),
    'шифр: команды процессора не дали общепринятый ответ');
  ChiClaim(CompareMem(@B1[0], @B2[0], 16),
    'шифр: руками и командами процессора вышло разное');
  ChiBranch(IdCrypt, 'aes-known-vector');
  Acc := ChiMix(Acc, B2[0] * 256 + B2[15]);

  { ── Шифрование на случайных ключах и блоках ── }
  for var Round := 1 to 200 do
  begin
    for var I := 0 to 15 do
    begin
      Key[I] := Byte(Src.NextBelow(256));
      B1[I] := Byte(Src.NextBelow(256));
    end;
    ExpandKey(Key, RK);
    B2 := B1;
    EncryptBlockPas(RK, B1);
    EncryptBlockAsm(RK, B2);
    ChiClaim(CompareMem(@B1[0], @B2[0], 16), 'шифр: разошлись на случайном блоке');
    Acc := ChiMix(Acc, B2[0]);
  end;
  ChiBranch(IdCrypt, 'aes-random');

  { ── Отдельный раунд: и обычный, и последний ── }
  for var Round := 1 to 200 do
  begin
    for var I := 0 to 15 do
    begin
      B1[I] := Byte(Src.NextBelow(256));
      Key[I] := Byte(Src.NextBelow(256));
    end;
    B2 := B1;
    AesRoundPas(B1, Key, False);
    AesRoundAsm(B2, Key, False);
    ChiClaim(CompareMem(@B1[0], @B2[0], 16), 'раунд шифра: обычный разошёлся');
    for var I := 0 to 15 do B1[I] := Byte(Src.NextBelow(256));
    B2 := B1;
    AesRoundPas(B1, Key, True);
    AesRoundAsm(B2, Key, True);
    ChiClaim(CompareMem(@B1[0], @B2[0], 16), 'раунд шифра: последний разошёлся');
  end;
  ChiBranch(IdCrypt, 'aes-round');

  { ── Четвертьраунд поточного шифра ── }
  Q1[0] := $11111111; Q1[1] := $01020304; Q1[2] := $9B8D6F43; Q1[3] := $01234567;
  Q2 := Q1;
  QuarterPas(Q1[0], Q1[1], Q1[2], Q1[3]);
  QuarterAsm(@Q2[0]);
  ChiClaim((Q1[0] = Q2[0]) and (Q1[1] = Q2[1]) and (Q1[2] = Q2[2]) and (Q1[3] = Q2[3]),
    'четвертьраунд: разошлись на известном образце');
  ChiClaim(Q2[0] = $EA2A92F4, 'четвертьраунд: известный ответ не сошёлся');
  for var Round := 1 to 300 do
  begin
    for var I := 0 to 3 do Q1[I] := Cardinal(Src.NextWord);
    Q2 := Q1;
    QuarterPas(Q1[0], Q1[1], Q1[2], Q1[3]);
    QuarterAsm(@Q2[0]);
    ChiClaim((Q1[0] = Q2[0]) and (Q1[1] = Q2[1]) and (Q1[2] = Q2[2]) and (Q1[3] = Q2[3]),
      'четвертьраунд: разошлись на случайном');
    Acc := ChiMix(Acc, Int64(Q2[0]));
  end;
  ChiBranch(IdCrypt, 'quarter-round');

  { ── Шаг перемешивания губки ── }
  for var Round := 1 to 200 do
  begin
    for var I := 0 to 24 do S1[I] := Src.NextWord;
    Move(S1[0], S2[0], SizeOf(S1));
    ChiStepPas(@S1[0]);
    ChiStepAsm(@S2[0]);
    ChiClaim(CompareMem(@S1[0], @S2[0], SizeOf(S1)), 'шаг губки: разошлись');
    Acc := ChiMix(Acc, Int64(S2[0]));
  end;
  { Нулевое состояние остаётся нулевым, единичное — известно поимённо. }
  FillChar(S1, SizeOf(S1), 0);
  Move(S1[0], S2[0], SizeOf(S1));
  ChiStepAsm(@S2[0]);
  for var I := 0 to 24 do
    ChiClaim(S2[I] = 0, 'шаг губки: из нуля вышло не ноль');
  for var I := 0 to 24 do S1[I] := UInt64($FFFFFFFFFFFFFFFF);
  Move(S1[0], S2[0], SizeOf(S1));
  ChiStepPas(@S1[0]);
  ChiStepAsm(@S2[0]);
  ChiClaim(CompareMem(@S1[0], @S2[0], SizeOf(S1)), 'шаг губки: разошлись на единицах');
  ChiClaim(S2[0] = UInt64($FFFFFFFFFFFFFFFF), 'шаг губки: единицы изменились');
  ChiBranch(IdCrypt, 'sponge-step');

  Result := Int64(Acc and $7FFFFFFFFFFF);
end;

end.
