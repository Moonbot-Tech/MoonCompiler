unit JsonReaderScan;

// Разбор выбранных полей неизменяемого UTF-8 JSON. Схему и привязки создаём один
// раз на независимый поток чтения; Parse переиспользует их между пакетами.
// Порядок полей может меняться, неизвестные поля проверяются и пропускаются.
// Результаты используем только после Parse=true. При false все назначения
// недействительны; callbacks синхронные и не должны публиковать частичный пакет.
//
// Текстовые результаты (выбор формата не требует промежуточных строк):
//   Slice('s', Symbol)     — Symbol: TJsonSlice, указатель + длина UTF-8 в пакете.
//   Str('s', Symbol)       — Symbol: string, преобразование UTF-8 в UTF-16.
//
// Для новых программ, в том числе Арбитража, предпочтителен TJsonSlice:
// нет копирования текста, аллокаций под него и изменения счётчиков ссылок.
// Срез НЕ удерживает исходный пакет: тот должен оставаться живым и неизменным
// до окончания обработки среза. Text не заканчивается #0 — читать только Len
// байт. Кавычки JSON в срез не входят. Slice принимает валидный UTF-8 без JSON-
// экранирования; выбранное значение с \uXXXX, \" и т.п. даёт Parse=false.
// Если такие значения нужны, использовать Str: он декодирует escapes.
//
// Str декодирует UTF-8 (и JSON escapes) в string и хранит текст в переиспользуемом
// буфере поля: обычные строки не выделяют память, пока хватает ёмкости
// (изначально 64; рост и escapes могут выделять).
// Результат заимствован до следующего Parse. Присваивание другой строковой
// переменной не отделяет данные: нельзя сохранять такой алиас в очередь/словарь.
// Для независимого хранения нужна явная копия только у потребителя, которому
// она действительно нужна. Str проверяет и убирает Prefix после decoding:
//   Header.Str('topic', Symbol, 'publicTrade.');
//
// Каждый объект схемы запоминает раскладку своих полей из своего удачного разбора (план):
// следующий пакет той же раскладки идёт по плану без поиска ключей. Неудачный разбор
// объекта его план не меняет — чужие сообщения того же соединения (стакан, ликвидации,
// pong) его не сбивают. План вложенного объекта обновляется его успехом, даже если
// весь Read потом отвергнут.
// ASM использует единое Win64-тело: на MoonCompiler, включая Linux, его ABI
// задан модификатором ms_abi_default. Отдельные SysV-копии не нужны.
{$INLINE ON}
{$OPTIMIZATION ON}

interface

uses mormot.core.base, System.SysUtils, System.Generics.Collections;

const
  // Same bound as MoonBot MAX_FRAME_SIZE / MAX_FRAG_SIZE / MAX_INFLATE_SIZE.
  JSON_READER_MAX_BYTES = 4 * 1024 * 1024;

type
  TReaderSchema = class;
  TScanEvent = procedure of object;
  TInt64Convert = function(Value: Int64): TDateTime;
  TJsonSlice = record
    Text: PUtf8Char;
    Len: Integer;
  end;
  PJsonSlice = ^TJsonSlice;
  TScanKind = (skNumber, skInteger, skString, skObject, skRows, skMappedText, skMappedBool, skTime, skSlice);
  TTextChoice = record
    Text: RawUtf8;
    Value: Int64;
    Code, Mask: UInt64;
  end;
  PScanField = ^TScanField;
  TScanField = record
    Name: RawUtf8;
    Dest: Pointer;
    Child: TReaderSchema;
    Kind: TScanKind;
    Required: Boolean;
    Base: PPointer;
    Next: Integer;
    TextPrefix: RawUtf8;
    TextStorage: string;
    TextCapacity: Integer;
    Choices: TArray<TTextChoice>;
    FalseValue, TrueValue, DefaultValue: Int64;
    Width: Integer;
    Convert: TInt64Convert;
  end;
  TScanOp = record
    Prefix: array[0..63] of Byte;
    PrefixCode, PrefixMask: UInt64;
    PrefixLen: Integer;
    Token: AnsiChar;
    Field: PScanField;
  end;

  TReaderSchema = class
  private
    FFields: TList<TScanField>;
    FFirst: array[Byte] of Integer;
    FRequired, FDefaults, FPlanSeen: UInt64;
    FPlan, FDraft: TList<TScanOp>;   // план удачного разбора / черновик текущего
    FPlanReady: Boolean;
    FEndQuote: Boolean;

    procedure Defaults(Seen: UInt64);
    function Child(const Name: RawUtf8; Kind: TScanKind): TReaderSchema;
  public
    BeforeParse, BeforeRow: TScanEvent;
    constructor Create;
    destructor Destroy; override;
    function Add(const Name: RawUtf8; Kind: TScanKind; Dest: Pointer; Required: Boolean): PScanField;
    procedure SetDefault(Field: PScanField; Value: Int64);
    procedure I64(const Name: RawUtf8; var Value: Int64; Required: Boolean = true);
    procedure Str(const Name: RawUtf8; var Value: string; const Prefix: RawUtf8 = '');
    procedure Slice(const Name: RawUtf8; var Value: TJsonSlice; Required: Boolean = true);
    function Obj(const Name: RawUtf8): TReaderSchema;
    function Rows(const Name: RawUtf8): TReaderSchema;
    function Parse(const Text: RawUtf8): Boolean;

  end;

implementation

uses mormot.core.json, mormot.core.unicode;

var
  AbsoluteBase: Pointer;

type
  TReader = record
    P, Stop: PUtf8Char;
    procedure Space; inline;
    function ReadString(out Start: PUtf8Char; out Len: Integer; out Escaped: Boolean): Boolean;
    function NumberEnd: Boolean;
    function Value(Field: PScanField; Depth: Integer): Boolean;
    function Container(Schema: TReaderSchema; Closing: AnsiChar; Rows: Boolean; Depth: Integer): Boolean;
    function FastContainer(Schema: TReaderSchema; Closing: AnsiChar; Rows: Boolean; Depth: Integer): Boolean;
  end;

function FieldDest(Field: PScanField): Pointer; inline;
begin
  Result := PByte(Field.Base^) + NativeInt(Field.Dest);
end;

procedure StoreOrdinal(Field: PScanField; Value: Int64); inline;
begin
  case Field.Width of
    1: PByte(FieldDest(Field))^ := Byte(Value);
    2: PWord(FieldDest(Field))^ := Word(Value);
    4: PCardinal(FieldDest(Field))^ := Cardinal(Value);
    8: PInt64(FieldDest(Field))^ := Value;
  end;
end;

procedure TReaderSchema.SetDefault(Field: PScanField; Value: Int64);
begin
  Field.DefaultValue := Value;
  FDefaults := FDefaults or (UInt64(1) shl ((NativeInt(Field) - NativeInt(Pointer(FFields.List))) div SizeOf(TScanField)));
end;

procedure TReaderSchema.Defaults(Seen: UInt64);
var Missing: UInt64;
begin
  Missing := FDefaults and not Seen;
  If Missing = 0 then exit;
  for var I := 0 to FFields.Count - 1 do
    If Missing and (UInt64(1) shl I) <> 0 then
      StoreOrdinal(@FFields.List[I], FFields.List[I].DefaultValue);
end;

function SkipUInt(var P: PUtf8Char; Stop: PUtf8Char): Boolean;
{$ifdef FPC} ms_abi_default; nostackframe; assembler; {$endif}
asm
{$ifndef FPC} .NOFRAME {$endif}
  mov rax, [rcx]
  mov r9, rax
  lea r10, [rax+16]
  cmp r10, rdx
  ja @@loop
  mov r10d, $30303030
  movd xmm1, r10d
  pshufd xmm1, xmm1, 0
  mov r10d, $09090909
  movd xmm2, r10d
  pshufd xmm2, xmm2, 0
@@block:
  movdqu xmm0, [rax]
  psubb xmm0, xmm1
  movdqa xmm3, xmm0
  pminub xmm3, xmm2
  pcmpeqb xmm3, xmm0
  pmovmskb r10d, xmm3
  xor r10d, $ffff
  jnz @@marker
  add rax, 16
  lea r10, [rax+16]
  cmp r10, rdx
  jbe @@block
  jmp @@loop
@@marker:
  bsf r10d, r10d
  add rax, r10
  jmp @@end
@@loop:
  cmp rax, rdx
  jae @@end
  movzx r8d, byte ptr [rax]
  sub r8d, '0'
  cmp r8d, 9
  ja @@end
  inc rax
  jmp @@loop
@@end:
  cmp rax, r9
  je @@bad
  mov [rcx], rax
  sub rax, r9
  cmp rax, 1
  je @@ok
  cmp byte ptr [r9], '0'
  je @@bad
@@ok:
  mov eax, 1
  ret
@@bad:
  xor eax, eax
end;

// SSE2 leaf: scan ASCII and validate UTF-8 in the same traversal. Return on
// quote, backslash, control or invalid UTF-8. All multi-byte reads are bounded.
function StringMarker(P, Stop: PUtf8Char): PUtf8Char;
{$ifdef FPC} ms_abi_default; nostackframe; assembler; {$endif}
asm
{$ifndef FPC} .NOFRAME {$endif}
  mov rax, rcx
  mov r8d, $22222222
  movd xmm1, r8d
  pshufd xmm1, xmm1, 0
  mov r8d, $5c5c5c5c
  movd xmm2, r8d
  pshufd xmm2, xmm2, 0
  mov r8d, $20202020
  movd xmm3, r8d
  pshufd xmm3, xmm3, 0
  lea r9, [rdx-16]
@@block:
  cmp rax, r9
  ja @@tail
  movdqu xmm0, [rax]
  movdqa xmm4, xmm0
  pcmpeqb xmm4, xmm1
  movdqa xmm5, xmm0
  pcmpeqb xmm5, xmm2
  por xmm4, xmm5
  movdqa xmm5, xmm3
  pcmpgtb xmm5, xmm0
  por xmm4, xmm5
  pmovmskb r8d, xmm4
  test r8d, r8d
  jnz @@found
  add rax, 16
  jmp @@block
@@found:
  bsf r8d, r8d
  add rax, r8
  cmp byte ptr [rax], $80
  jae @@utf8
  ret
@@tail:
  cmp rax, rdx
  jae @@done
  movzx r8d, byte ptr [rax]
  cmp r8d, $22
  je @@done
  cmp r8d, $5c
  je @@done
  cmp r8d, $20
  jb @@done
  cmp r8d, $80
  jae @@utf8
  inc rax
  jmp @@tail
@@utf8:
  movzx r8d, byte ptr [rax]
  cmp r8d, $c2
  jb @@done
  cmp r8d, $df
  jbe @@two
  cmp r8d, $ef
  jbe @@three
  cmp r8d, $f4
  ja @@done
  lea r10, [rax+4]
  cmp r10, rdx
  ja @@done
  mov ecx, [rax]
  and ecx, $c0c0c000
  cmp ecx, $80808000
  jne @@done
  cmp r8d, $f0
  jne @@fourMax
  cmp byte ptr [rax+1], $90
  jb @@done
@@fourMax:
  cmp r8d, $f4
  jne @@advance
  cmp byte ptr [rax+1], $8f
  ja @@done
  jmp @@advance
@@three:
  lea r10, [rax+3]
  cmp r10, rdx
  ja @@done
  movzx ecx, word ptr [rax+1]
  and ecx, $c0c0
  cmp ecx, $8080
  jne @@done
  cmp r8d, $e0
  jne @@surrogate
  cmp byte ptr [rax+1], $a0
  jb @@done
@@surrogate:
  cmp r8d, $ed
  jne @@advance
  cmp byte ptr [rax+1], $9f
  ja @@done
  jmp @@advance
@@two:
  lea r10, [rax+2]
  cmp r10, rdx
  ja @@done
  movzx ecx, byte ptr [rax+1]
  and ecx, $c0
  cmp ecx, $80
  jne @@done
@@advance:
  mov rax, r10
  jmp @@block
@@done:
end;

procedure TReader.Space;
begin
  while (P < Stop) and (P^ in [#9, #10, #13, ' ']) do Inc(P);
end;

function Hex4(P: PUtf8Char): Integer;
begin
  Result := 0;
  for var I := 0 to 3 do begin
    var Digit := Ord(P[I]);
    case P[I] of
      '0'..'9': Dec(Digit, Ord('0'));
      'a'..'f': Dec(Digit, Ord('a') - 10);
      'A'..'F': Dec(Digit, Ord('A') - 10);
    else exit(-1);
    end;
    Result := (Result shl 4) or Digit;
  end;
end;

function TReader.ReadString(out Start: PUtf8Char; out Len: Integer; out Escaped: Boolean): Boolean;
var Code: Integer;
begin
  Result := false;
  If (P = Stop) or (P^ <> '"') then exit;
  Inc(P);
  Start := P;
  Escaped := false;
  repeat
    P := StringMarker(P, Stop);
    If P = Stop then exit;
    If P^ = '"' then begin
      Len := P - Start;
      Inc(P);
      exit(true);
    end;
    If P^ <> '\' then exit;
    Escaped := true;
    Inc(P);
    If P = Stop then exit;
    If P^ = 'u' then begin
      If Stop - P < 5 then exit;
      Code := Hex4(P + 1);
      // mORMot substitutes '?' for NUL or unmatched surrogates. Fail closed
      // instead of silently changing a market name or a selected key.
      If (Code <= 0) or ((Code >= $dc00) and (Code <= $dfff)) then exit;
      Inc(P, 5);
      If (Code >= $d800) and (Code <= $dbff) then begin
        If (Stop - P < 6) or (PWord(P)^ <> $755c) then exit;
        Code := Hex4(P + 2);
        If (Code < $dc00) or (Code > $dfff) then exit;
        Inc(P, 6);
      end;
    end else begin
      If not (P^ in ['"', '\', '/', 'b', 'f', 'n', 'r', 't']) then exit;
      Inc(P);
    end;
  until false;
end;

function Unescape(Start: PUtf8Char; Len: Integer): RawUtf8;
var Work: RawUtf8; Info: TGetJsonField;
begin
  SetLength(Work, Len + 18);
  Work[1] := '"';
  Move(Start^, Work[2], Len);
  Work[Len + 2] := '"';
  FillChar(Work[Len + 3], 16, 0);
  Info.Json := Pointer(Work);
  Info.GetJsonField;
  If Info.Json = nil then raise EConvertError.Create('Invalid JSON escape');
  FastSetString(Result, Info.Value, Info.ValueLen);
end;

function TReader.NumberEnd: Boolean;
begin
  Result := false;
  If (P < Stop) and (P^ = '-') then Inc(P);
  If P = Stop then exit;
  If P^ = '0' then Inc(P)
  else begin
    If not (P^ in ['1'..'9']) then exit;
    repeat Inc(P) until (P = Stop) or not (P^ in ['0'..'9']);
  end;
  If (P < Stop) and (P^ = '.') then begin
    Inc(P);
    If (P = Stop) or not (P^ in ['0'..'9']) then exit;
    repeat Inc(P) until (P = Stop) or not (P^ in ['0'..'9']);
  end;
  If (P < Stop) and (P^ in ['e','E']) then begin
    Inc(P);
    If (P < Stop) and (P^ in ['+','-']) then Inc(P);
    If (P = Stop) or not (P^ in ['0'..'9']) then exit;
    repeat Inc(P) until (P = Stop) or not (P^ in ['0'..'9']);
  end;
  Result := true;
end;

function StoreText(Field: PScanField; Start: PUtf8Char; Len: Integer): Boolean;
var N, Chars: Integer; Dest: PString; Buffer: Pointer;
begin
  N := Length(Field.TextPrefix);
  Result := (Len >= N) and ((N = 0) or CompareMem(Start, Pointer(Field.TextPrefix), N));
  If not Result then exit;
  Inc(Start, N);
  Dec(Len, N);
  Dest := FieldDest(Field);
  If Len = 0 then begin
    Dest^ := '';
    exit;
  end;
  Buffer := Pointer(Field.TextStorage);
  If Field.TextCapacity < Len then begin
    Dest^ := '';
    SetLength(Field.TextStorage, Len);
    Field.TextCapacity := Len;
    Buffer := Pointer(Field.TextStorage);
  end;
  Chars := Utf8ToWideChar(Buffer, Start, Len) shr 1;
  PStrLen(PByte(Buffer) - _STRLEN)^ := Chars;
  PWideChar(Buffer)[Chars] := #0;
  If Pointer(Dest^) <> Buffer then Dest^ := Field.TextStorage;
end;

function StoreChoice(Field: PScanField; Start: PUtf8Char; Len: Integer): Boolean;
begin
  for var I := 0 to High(Field.Choices) do
    If (Length(Field.Choices[I].Text) = Len) and CompareMem(Start, Pointer(Field.Choices[I].Text), Len) then begin
      StoreOrdinal(Field, Field.Choices[I].Value);
      exit(true);
    end;
  Result := false;
end;

function TReader.Value(Field: PScanField; Depth: Integer): Boolean;
var
  Err: Integer;
  Start: PUtf8Char;
  Len: Integer;
  IntegerValue: Int64;
  Escaped, Quoted: Boolean;
  Text: RawUtf8;
  Closing: AnsiChar;
begin
  Result := false;
  Space;
  If P = Stop then exit;
  If P^ in ['{','['] then begin
    If P^ = '{' then Closing := '}' else Closing := ']';
    If Field = nil then exit(Container(nil, Closing, false, Depth + 1));
    case Field.Kind of
      skObject: If Closing <> '}' then exit;
      skRows: If Closing <> ']' then exit;
    else exit;
    end;
    exit(Container(Field.Child, Closing, Field.Kind = skRows, Depth + 1));
  end;
  Quoted := P^ = '"';

  If (Field <> nil) and (Field.Kind = skNumber) and (P^ <> 'n') then begin
    Start := P;
    If Quoted then begin
      Inc(P);
      PDouble(FieldDest(Field))^ := GetNextExtended(P, Err, ord('"'));
    end else PDouble(FieldDest(Field))^ := GetNextExtended(P, Err, NUMBER_ENDING_JSON);
    If Err = 0 then begin
      If Quoted then Inc(P);
      exit(true);
    end;
    If not Quoted then exit;
    // Only escaped numeric strings need decoding. Ordinary tokens never get
    // scanned for an endpoint before their numeric conversion.
    P := Start;
    If not ReadString(Start, Len, Escaped) or not Escaped then exit;
    Text := Unescape(Start, Len);
    exit(ToDouble(Text, PDouble(FieldDest(Field))^));
  end;

  If (Field <> nil) and (Field.Kind in [skInteger, skTime]) and (P^ <> 'n') then begin
    Start := P;
    If Quoted then begin
      Inc(P);
      IntegerValue := GetNextInt64(P, Err, ord('"'));
    end else IntegerValue := GetNextInt64(P, Err, NUMBER_ENDING_JSON);
    If Err <> 0 then begin
      If not Quoted then exit;
      P := Start;
      If not ReadString(Start, Len, Escaped) or not Escaped then exit;
      Text := Unescape(Start, Len);
      If not ToInt64(Text, IntegerValue) then exit;
    end else If Quoted then Inc(P);
    If Field.Kind = skInteger then PInt64(FieldDest(Field))^ := IntegerValue
    else PDouble(FieldDest(Field))^ := Field.Convert(IntegerValue);
    exit(true);
  end;

  If Quoted then begin
    If not ReadString(Start, Len, Escaped) then exit;
    If (Field <> nil) and Escaped then begin
      If Field.Kind = skSlice then exit;
      Text := Unescape(Start, Len);
      Start := Pointer(Text);
      Len := Length(Text);
    end;
  end else begin
    Start := P;
    case P^ of
      't': begin
        If (Stop - P < 4) or (PCardinal(P)^ <> $65757274) then exit;
        Inc(P, 4);
      end;
      'f': begin
        If (Stop - P < 5) or (PCardinal(P)^ <> $736c6166) or (P[4] <> 'e') then exit;
        Inc(P, 5);
      end;
      'n': begin
        If (Stop - P < 4) or (PCardinal(P)^ <> $6c6c756e) then exit;
        Inc(P, 4);
        If (Field <> nil) and (Field.Kind = skMappedBool) and not Field.Required then
          StoreOrdinal(Field, Field.DefaultValue);
        exit((Field = nil) or not Field.Required);
      end;
    else
      If not NumberEnd then exit;
    end;
    Len := P - Start;
  end;
  If Field = nil then exit(true);
  case Field.Kind of
    skString: begin
      If not Quoted then exit;
      If not StoreText(Field, Start, Len) then exit;
    end;
    skMappedText: begin
      If not Quoted or not StoreChoice(Field, Start, Len) then exit;
    end;
    skMappedBool: begin
      If Quoted or not (Start^ in ['t','f']) then exit;
      If Start^ = 't' then StoreOrdinal(Field, Field.TrueValue) else StoreOrdinal(Field, Field.FalseValue);
    end;
    skSlice: begin
      If not Quoted then exit;
      PJsonSlice(FieldDest(Field)).Text := Start;
      PJsonSlice(FieldDest(Field)).Len := Len;
    end;

  else exit;
  end;
  Result := true;
end;

function TReader.Container(Schema: TReaderSchema; Closing: AnsiChar; Rows: Boolean; Depth: Integer): Boolean;
var
  Key, PrefixStart: PUtf8Char;
  Len, Index: Integer;
  Escaped, Plan, CanPlan, EndQuote: Boolean;
  Name: RawUtf8;
  Field: PScanField;
  Seen, Bit: UInt64;
  Op: TScanOp;
begin
  Result := false;
  If Depth > 64 then exit;
  Inc(P);
  Space;
  Seen := 0;
  Plan := (Schema <> nil) and not Rows;   // план ведёт объект схемы; черновик станет планом только при успехе
  CanPlan := true;
  EndQuote := false;
  If Plan then begin
    Schema.FDraft.Count := 0;
    If Assigned(Schema.BeforeRow) then Schema.BeforeRow;
  end;
  PrefixStart := P;
  If (P < Stop) and (P^ <> Closing) then repeat
    Field := nil;
    Index := -1;
    If Closing = '}' then begin
      If not ReadString(Key, Len, Escaped) then exit;
      If Schema <> nil then begin
        If Escaped then begin
          Name := Unescape(Key, Len);
          Key := Pointer(Name);
          Len := Length(Name);
        end;
        If Len > 0 then begin
          Index := Schema.FFirst[Byte(Key^)];
          while Index >= 0 do begin
            Field := @Schema.FFields.List[Index];
            If (Length(Field.Name) = Len) and CompareMem(Pointer(Field.Name), Key, Len) then break;
            Index := Field.Next;
          end;
          If Index < 0 then Field := nil;
        end;
      end;
      Space;
      If (P = Stop) or (P^ <> ':') then exit;
      Inc(P);
    end;
    If Index >= 0 then begin
      Bit := UInt64(1) shl Index;
      If Seen and Bit <> 0 then exit; // selected duplicates never silently overwrite
      Seen := Seen or Bit;
    end;
    Space;
    If Plan then begin
      If P = Stop then exit;
      Op.Token := P^;
      Op.PrefixLen := P - PrefixStart + Ord(Op.Token = '"');
      If Op.PrefixLen > SizeOf(Op.Prefix) then CanPlan := false;
      If CanPlan and (Op.PrefixLen > 0) then Move(PrefixStart^, Op.Prefix, Op.PrefixLen);
      Op.PrefixCode := 0;
      Op.PrefixMask := 0;
      If Op.PrefixLen <= 8 then begin
        If Op.PrefixLen > 0 then Move(PrefixStart^, Op.PrefixCode, Op.PrefixLen);
        If Op.PrefixLen = 8 then Op.PrefixMask := High(UInt64)
        else Op.PrefixMask := (UInt64(1) shl (Op.PrefixLen * 8)) - 1;
      end;
      Op.Field := Field;
      If CanPlan and (Schema.FDraft.Count = Schema.FDraft.Capacity) then CanPlan := false;
      If CanPlan then Schema.FDraft.Add(Op);
    end;
    If Rows then begin
      Space;
      If (P = Stop) or (P^ <> '{') or not Container(Schema, '}', false, Depth + 1) then exit;
    end else If not Value(Field, Depth) then exit;
    PrefixStart := P;
    If Plan then begin
      EndQuote := Op.Token = '"';
      If EndQuote then Dec(PrefixStart);
    end;
    Space;
    If P = Stop then exit;
    If P^ = Closing then break;
    If P^ <> ',' then exit;
    Inc(P);
    Space;
    If (P = Stop) or (P^ = Closing) then exit;
  until false;
  If (P = Stop) or (P^ <> Closing) then exit;
  Inc(P);
  If Plan then begin
    If Seen and Schema.FRequired <> Schema.FRequired then exit;
    Schema.Defaults(Seen);
    Schema.FPlanReady := CanPlan;
    If CanPlan then begin
      var Draft := Schema.FDraft;
      Schema.FDraft := Schema.FPlan;
      Schema.FPlan := Draft;
      Schema.FPlanSeen := Seen;
      Schema.FEndQuote := EndQuote;
    end;
  end;
  Result := true;
end;

function TReader.FastContainer(Schema: TReaderSchema; Closing: AnsiChar; Rows: Boolean; Depth: Integer): Boolean;
var
  Err: Integer;
  Op: ^TScanOp;
  Field: PScanField;
  Start: PUtf8Char;
  Len, I, Choice: Integer;
  IntegerValue: Int64;
  Quoted: Boolean;

begin
  Result := false;
  If (Depth > 64) or (Schema = nil) or (P = Stop) then exit;
  If (Closing = '}') and (P^ <> '{') then exit;
  If (Closing = ']') and (P^ <> '[') then exit;
  Inc(P);
  If Rows then begin
    If (P < Stop) and (P^ = ']') then begin
      Inc(P);
      exit(true);
    end;
    repeat
      If not FastContainer(Schema, '}', false, Depth + 1) then exit;
      If P = Stop then exit;
      If P^ = ']' then begin
        Inc(P);
        exit(true);
      end;
      If P^ <> ',' then exit;
      Inc(P);
    until false;
  end;
  If not Schema.FPlanReady then exit;
  If Assigned(Schema.BeforeRow) then Schema.BeforeRow;
  for I := 0 to Schema.FPlan.Count - 1 do begin
    Op := @Schema.FPlan.List[I];
    Len := Op.PrefixLen;
    If (Len <= 8) and (Stop - P >= 8) then begin
      If PUInt64(P)^ and Op.PrefixMask <> Op.PrefixCode then exit;
    end else If (Stop - P < Len) or not CompareMem(P, @Op.Prefix, Len) then exit;
    Inc(P, Len);
    If P = Stop then exit;
    Field := Op.Field;
    If (Field <> nil) and (Field.Kind in [skObject, skRows]) then begin
      If Field.Kind = skObject then begin
        If not FastContainer(Field.Child, '}', false, Depth + 1) then exit;
      end else If not FastContainer(Field.Child, ']', true, Depth + 1) then exit;
      continue;
    end;
    Quoted := Op.Token = '"';
    If Field = nil then begin
      case Op.Token of
        '"': begin
          P := StringMarker(P, Stop);
          If (P = Stop) or (P^ <> '"') then exit;
        end;
        '-', '0'..'9': begin
          Start := P;
          If not SkipUInt(P, Stop) or ((P < Stop) and (P^ in ['.', 'e', 'E'])) then begin
            P := Start;
            If not NumberEnd then exit;
          end;
        end;
        't','f': begin
          If (Stop - P >= 4) and (PCardinal(P)^ = $65757274) then Inc(P, 4)
          else If (Stop - P >= 5) and (PCardinal(P)^ = $736c6166) and (P[4] = 'e') then Inc(P, 5)
          else exit;
        end;
      else
        If not Value(nil, Depth) then exit;
      end;
    end else case Field.Kind of
      skNumber: begin
        If Quoted then PDouble(FieldDest(Field))^ := GetNextExtended(P, Err, ord('"'))
        else PDouble(FieldDest(Field))^ := GetNextExtended(P, Err, NUMBER_ENDING_JSON);
        If Err <> 0 then exit;
      end;
      skInteger: begin
        If Quoted then PInt64(FieldDest(Field))^ := GetNextInt64(P, Err, ord('"'))
        else PInt64(FieldDest(Field))^ := GetNextInt64(P, Err, NUMBER_ENDING_JSON);
        If Err <> 0 then exit;
      end;
      skTime: begin
        If Quoted then IntegerValue := GetNextInt64(P, Err, ord('"'))
        else IntegerValue := GetNextInt64(P, Err, NUMBER_ENDING_JSON);
        If Err <> 0 then exit;
        PDouble(FieldDest(Field))^ := Field.Convert(IntegerValue);
      end;
      skMappedText: begin
        If not Quoted then exit;
        Choice := 0;
        while Choice < Length(Field.Choices) do begin
          Len := Length(Field.Choices[Choice].Text);
          If (Len < 8) and (Stop - P >= 8) then begin
            If PUInt64(P)^ and Field.Choices[Choice].Mask = Field.Choices[Choice].Code then break;
          end else If ((Len = 0) or (P^ = Field.Choices[Choice].Text[1])) and
            (Stop - P > Len) and (P[Len] = '"') and CompareMem(P, Pointer(Field.Choices[Choice].Text), Len) then break;
          Inc(Choice);
        end;
        If Choice = Length(Field.Choices) then exit;
        StoreOrdinal(Field, Field.Choices[Choice].Value);
        Inc(P, Len);
      end;
      skMappedBool: begin
        If Quoted then exit;
        If (Stop - P >= 4) and (PCardinal(P)^ = $65757274) then begin
          StoreOrdinal(Field, Field.TrueValue);
          Inc(P, 4);
        end else If (Stop - P >= 5) and (PCardinal(P)^ = $736c6166) and (P[4] = 'e') then begin
          StoreOrdinal(Field, Field.FalseValue);
          Inc(P, 5);
        end else If not Field.Required and (Stop - P >= 4) and (PCardinal(P)^ = $6c6c756e) then begin
          StoreOrdinal(Field, Field.DefaultValue);
          Inc(P, 4);
        end else exit;
      end;
      skSlice: begin
        If not Quoted then exit;
        Start := P;
        P := StringMarker(P, Stop);
        If (P = Stop) or (P^ <> '"') then exit;
        PJsonSlice(FieldDest(Field)).Text := Start;
        PJsonSlice(FieldDest(Field)).Len := P - Start;
      end;
      skString: begin
        If not Quoted then exit;
        Start := P;
        P := StringMarker(P, Stop);
        If (P = Stop) or (P^ <> '"') then exit;
        If not StoreText(Field, Start, P - Start) then exit;
      end;
    else exit;
    end;
  end;
  If Schema.FEndQuote then begin
    If (P = Stop) or (P^ <> '"') then exit;
    Inc(P);
  end;
  If (P = Stop) or (P^ <> Closing) then exit;
  Inc(P);
  Schema.Defaults(Schema.FPlanSeen);
  Result := true;
end;

constructor TReaderSchema.Create;
begin
  inherited Create;
  FFields := TList<TScanField>.Create;
  FPlan := TList<TScanOp>.Create;
  FPlan.Capacity := 32;
  FDraft := TList<TScanOp>.Create;
  FDraft.Capacity := 32;
  FillChar(FFirst, SizeOf(FFirst), $ff);
end;

destructor TReaderSchema.Destroy;
begin
  for var F in FFields do F.Child.Free;
  FreeAndNil(FFields);
  FreeAndNil(FPlan);
  FreeAndNil(FDraft);
  inherited;
end;

function TReaderSchema.Add(const Name: RawUtf8; Kind: TScanKind; Dest: Pointer; Required: Boolean): PScanField;
var F: TScanField; N: Integer;
begin
  N := FFields.Count;
  FPlanReady := false;
  If (N = 64) or (Name = '') then raise EArgumentException.Create('Schema field limit/name');
  F := Default(TScanField);
  F.Name := Name;
  F.Kind := Kind;
  F.Dest := Dest;
  F.Base := @AbsoluteBase;
  F.Required := Required;
  F.Next := FFirst[Byte(Name[1])];
  FFields.Add(F);
  FFirst[Byte(Name[1])] := N;
  If Required then FRequired := FRequired or (UInt64(1) shl N);
  Result := @FFields.List[N];
end;

procedure TReaderSchema.I64(const Name: RawUtf8; var Value: Int64; Required: Boolean);
begin
  Add(Name, skInteger, @Value, Required);
end;
procedure TReaderSchema.Str(const Name: RawUtf8; var Value: string; const Prefix: RawUtf8);
begin
  var F := Add(Name, skString, @Value, true);
  F.TextPrefix := Prefix;
  F.TextCapacity := 64;
  SetLength(F.TextStorage, F.TextCapacity);
end;
procedure TReaderSchema.Slice(const Name: RawUtf8; var Value: TJsonSlice; Required: Boolean);
begin
  Add(Name, skSlice, @Value, Required);
end;
function TReaderSchema.Obj(const Name: RawUtf8): TReaderSchema;
begin
  Result := Child(Name, skObject);
end;
function TReaderSchema.Rows(const Name: RawUtf8): TReaderSchema;
begin
  Result := Child(Name, skRows);
end;

function TReaderSchema.Child(const Name: RawUtf8; Kind: TScanKind): TReaderSchema;
begin
  var Added := Add(Name, Kind, nil, true);
  Result := TReaderSchema.Create;
  Added.Child := Result;
end;
function TReaderSchema.Parse(const Text: RawUtf8): Boolean;
var R: TReader;
begin
  Result := false;
  If (Length(Text) = 0) or (Length(Text) > JSON_READER_MAX_BYTES) then exit;

  try
    R.P := Pointer(Text);
    R.Stop := R.P + Length(Text);
    If Assigned(BeforeParse) then BeforeParse;
    If R.FastContainer(Self, '}', false, 0) and (R.P = R.Stop) then exit(true);
    R.P := Pointer(Text);
    If Assigned(BeforeParse) then BeforeParse;
    R.Space;
    If (R.P = R.Stop) or (R.P^ <> '{') then exit;
    Result := R.Container(Self, '}', false, 0);
    R.Space;
    Result := Result and (R.P = R.Stop);
  except
    on E: EOutOfMemory do Result := false;
    on E: EConvertError do Result := false;
  end;
end;

end.
