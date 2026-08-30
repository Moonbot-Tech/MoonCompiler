unit chimera_hl;

{ Орган «схема действия»: сборка подписываемого тела по описанию полей.

  Источник: `MoonBot/HyperL\HLSigs.pas` — описания схем действий
  биржи на смарт-контрактах и сборка тела по ним. Перенесено дословно по
  форме:

    * схема описывается НАБОРОМ ПОЛЕЙ, приходящим открытым массивом и
      переписываемым в динамический массив поэлементно;
    * видов схем несколько: плоская, вложенная в объект, вложенная в массив.
      Общая часть строится одним построителем, особенная дописывается сверху;
    * при построении СРАЗУ предвычисляются признаки и индексы особых полей —
      поиск идёт сравнением имён БЕЗ учёта регистра, а найденный индекс потом
      используется как готовый, без повторного поиска;
    * тело собирается строго в порядке описания: для подписи порядок полей
      значим, перестановка даёт другой отпечаток и отказ биржи.

  Заменено оснасткой: сама эллиптическая подпись (здесь вместо неё отпечаток
  с известным вектором) и сеть. Предмет проверки — схема и порядок, а не
  математика кривой: её проверяет отдельный слой комплекта.

  Почему это отдельная форма:

    * открытый массив как параметр — отдельный способ передачи, у которого
      своя раскладка и своя граница: `High` от него считается иначе, чем от
      динамического;
    * предвычисленный индекс живёт дольше, чем поиск, который его породил, и
      обязан остаться верным после копирования всей схемы;
    * порядок полей — часть смысла: тело, собранное в другом порядке, есть
      другое тело, даже если поля те же.

  Оракулы:

    1. **точное тело**: для каждой схемы выписано, что обязано получиться —
       строкой целиком, а не по длине;
    2. **независимая сборка**: то же тело собирается обходом описания в
       обратном порядке с последующим разворотом — другая дорога, тот же
       ответ;
    3. **отпечаток**: стандартный вектор для выбранного отпечатка и
       чувствительность к перестановке полей. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch INLINEVARS}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, mormot.core.base, mormot.crypt.core, chimera_body;

type
  TChiFieldType = (ftStr, ftInt, ftBool, ftNum);
  TChiScope = (scPriv, scPub);
  TChiSchemaKind = (skFlat, skContainer);
  TChiContainerKind = (ckNone, ckObject, ckArray);

  TChiFieldSpec = record
    Name:  string;
    FType: TChiFieldType;
  end;

  TChiSigSpec = record
    Scope:         TChiScope;
    Schema:        TChiSchemaKind;
    ContainerKind: TChiContainerKind;
    ActionType:    string;
    ContainerKey:  string;
    EntryFields:   array of TChiFieldSpec;
    ActionFields:  array of TChiFieldSpec;
    { Предвычисленные признаки и индексы особых полей. }
    HasNonce:      Boolean;
    HasTime:       Boolean;
    IndexNonce:    Integer;
    IndexTime:     Integer;
  end;

  TChiValue = record
    Name: string;
    Text: string;
  end;

function ChiHlRun: Int64;

implementation

const
  IdHl = 'CHI-MB-HL-001';

{ ═══ Построители схем ════════════════════════════════════════════════════ }

function F(const AName: string; AType: TChiFieldType): TChiFieldSpec;
begin
  Result.Name := AName;
  Result.FType := AType;
end;

{ Открытый массив переписывается в динамический ПОЭЛЕМЕНТНО — как в живом
  коде, а не одним присваиванием. }
function SigFlat(const AType: string;
  const AEntry: array of TChiFieldSpec): TChiSigSpec;
var
  I: Integer;
begin
  Result.Scope := scPriv;
  Result.Schema := skFlat;
  Result.ContainerKind := ckNone;
  Result.ActionType := AType;
  Result.ContainerKey := '';
  SetLength(Result.EntryFields, Length(AEntry));
  for I := 0 to High(AEntry) do
    Result.EntryFields[I] := AEntry[I];
  SetLength(Result.ActionFields, 0);
  Result.HasNonce := False;
  Result.HasTime := False;
  Result.IndexNonce := -1;
  Result.IndexTime := -1;
end;

{ Разновидность поверх общей части: предвычисление признаков и индексов. }
function SigFlatUser(const AType: string;
  const AEntry: array of TChiFieldSpec): TChiSigSpec;
var
  I: Integer;
begin
  Result := SigFlat(AType, AEntry);
  for I := 0 to High(Result.EntryFields) do
  begin
    { Сравнение имён БЕЗ учёта регистра — как в живом коде. }
    if SameText(Result.EntryFields[I].Name, 'nonce') then
    begin
      Result.HasNonce := True;
      Result.IndexNonce := I;
    end
    else if SameText(Result.EntryFields[I].Name, 'time') then
    begin
      Result.HasTime := True;
      Result.IndexTime := I;
    end;
  end;
end;

function SigContainer(const AType, AKey: string; Kind: TChiContainerKind;
  const AEntry, AAction: array of TChiFieldSpec): TChiSigSpec;
var
  I: Integer;
begin
  Result.Scope := scPriv;
  Result.Schema := skContainer;
  Result.ContainerKind := Kind;
  Result.ActionType := AType;
  Result.ContainerKey := AKey;
  SetLength(Result.EntryFields, Length(AEntry));
  for I := 0 to High(AEntry) do
    Result.EntryFields[I] := AEntry[I];
  SetLength(Result.ActionFields, Length(AAction));
  for I := 0 to High(AAction) do
    Result.ActionFields[I] := AAction[I];
  Result.HasNonce := False;
  Result.HasTime := False;
  Result.IndexNonce := -1;
  Result.IndexTime := -1;
end;

{ ═══ Сборка тела ═════════════════════════════════════════════════════════ }

function Quoted(const S: string): string; inline;
begin
  Result := '"' + S + '"';
end;

function ValueOf(const Values: array of TChiValue; const Name: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(Values) do
    if Values[I].Name = Name then Exit(Values[I].Text);
end;

function RenderField(const Spec: TChiFieldSpec;
  const Values: array of TChiValue): string;
var
  V: string;
begin
  V := ValueOf(Values, Spec.Name);
  case Spec.FType of
    ftStr:  Result := Quoted(Spec.Name) + ':' + Quoted(V);
    ftInt:  Result := Quoted(Spec.Name) + ':' + V;
    ftNum:  Result := Quoted(Spec.Name) + ':' + V;
    ftBool: Result := Quoted(Spec.Name) + ':' + V;
  end;
end;

{ Порядок полей — часть смысла: тело собирается строго по описанию. }
function BuildBody(const Spec: TChiSigSpec;
  const Values: array of TChiValue): string;
var
  I: Integer;
  Entry, Action: string;
begin
  Entry := '';
  for I := 0 to High(Spec.EntryFields) do
  begin
    if I > 0 then Entry := Entry + ',';
    Entry := Entry + RenderField(Spec.EntryFields[I], Values);
  end;

  if Spec.Schema = skFlat then
    Exit('{' + Quoted('type') + ':' + Quoted(Spec.ActionType) + ','
         + Entry + '}');

  Action := '';
  for I := 0 to High(Spec.ActionFields) do
  begin
    if I > 0 then Action := Action + ',';
    Action := Action + RenderField(Spec.ActionFields[I], Values);
  end;

  case Spec.ContainerKind of
    ckObject:
      Result := '{' + Quoted('type') + ':' + Quoted(Spec.ActionType) + ','
                + Quoted(Spec.ContainerKey) + ':{' + Action + '},'
                + Entry + '}';
    ckArray:
      Result := '{' + Quoted('type') + ':' + Quoted(Spec.ActionType) + ','
                + Quoted(Spec.ContainerKey) + ':[{' + Action + '}],'
                + Entry + '}';
  else
    Result := '';
  end;
end;

{ Независимая сборка: поля обходятся с конца, куски копятся в список и
  склеиваются в обратном порядке. Другая дорога к тому же телу. }
function BuildBodyBackwards(const Spec: TChiSigSpec;
  const Values: array of TChiValue): string;
var
  I: Integer;
  Parts: array of string;
  Entry: string;
begin
  if Spec.Schema <> skFlat then Exit(BuildBody(Spec, Values));
  SetLength(Parts, Length(Spec.EntryFields));
  for I := High(Spec.EntryFields) downto 0 do
    Parts[High(Spec.EntryFields) - I] := RenderField(Spec.EntryFields[I], Values);
  Entry := '';
  for I := High(Parts) downto 0 do
  begin
    Entry := Entry + Parts[I];
    if I > 0 then Entry := Entry + ',';
  end;
  Result := '{' + Quoted('type') + ':' + Quoted(Spec.ActionType) + ','
            + Entry + '}';
end;

{ ═══ Отпечаток ═══════════════════════════════════════════════════════════ }

function Digest(const S: string): string;
var
  Sha: TSha3;
  Hash: THash256;
  Raw: RawByteString;
  I: Integer;
begin
  Raw := RawByteString(S);
  Sha.Init(SHA3_256);
  if Length(Raw) > 0 then Sha.Update(Pointer(Raw), Length(Raw));
  Sha.Final(@Hash, 256);
  Result := '';
  for I := 0 to 31 do
    Result := Result + LowerCase(IntToHex(THash256Rec(Hash).b[I], 2));
end;

{ ═══ Проверка ════════════════════════════════════════════════════════════ }

function ChiHlRun: Int64;
var
  Spec, Spec2: TChiSigSpec;
  Values: array of TChiValue;
  Body, Other: string;
  Acc: UInt64;
  I: Integer;
  Swapped: TChiSigSpec;
  Tmp: TChiFieldSpec;
begin
  ChiCovered(IdHl);
  Acc := ChiOffset;

  SetLength(Values, 6);
  Values[0].Name := 'asset';      Values[0].Text := '5';
  Values[1].Name := 'isBuy';      Values[1].Text := 'true';
  Values[2].Name := 'limitPx';    Values[2].Text := '64250.15';
  Values[3].Name := 'sz';         Values[3].Text := '0.0035';
  Values[4].Name := 'nonce';      Values[4].Text := '1735689600123';
  Values[5].Name := 'time';       Values[5].Text := '1735689600000';

  { ── Внешняя истина для отпечатка ── }
  ChiClaim(Digest('') =
    'a7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a',
    'схема: отпечаток пустого не совпал со стандартным вектором');
  ChiClaim(Digest('abc') =
    '3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532',
    'схема: отпечаток вектора не тот');
  ChiBranch(IdHl, 'digest-vector');

  { ── Плоская схема: тело предъявляется целиком ── }
  Spec := SigFlat('order', [F('asset', ftInt), F('isBuy', ftBool),
                            F('limitPx', ftStr), F('sz', ftStr)]);
  Body := BuildBody(Spec, Values);
  ChiClaim(Body = '{"type":"order","asset":5,"isBuy":true,'
                  + '"limitPx":"64250.15","sz":"0.0035"}',
    'схема: плоское тело собрано не так: ' + Body);
  ChiBranch(IdHl, 'flat-body');
  Acc := ChiMix(Acc, Length(Body));

  { Независимая сборка обязана дать то же. }
  ChiClaim(BuildBodyBackwards(Spec, Values) = Body,
    'схема: обратная сборка дала другое тело');
  ChiBranch(IdHl, 'backwards-build');

  { ── Предвычисленные признаки и индексы ── }
  Spec2 := SigFlatUser('withdraw', [F('destination', ftStr),
                                    F('Nonce', ftInt), F('TIME', ftInt)]);
  ChiClaim(Spec2.HasNonce, 'схема: признак числа-однократника не выставлен');
  ChiClaim(Spec2.HasTime, 'схема: признак времени не выставлен');
  ChiClaim(Spec2.IndexNonce = 1, 'схема: индекс однократника не тот');
  ChiClaim(Spec2.IndexTime = 2, 'схема: индекс времени не тот');
  ChiClaim(Spec2.EntryFields[Spec2.IndexNonce].Name = 'Nonce',
    'схема: предвычисленный индекс указывает не на то поле');
  ChiBranch(IdHl, 'precomputed-index');

  { Схема без особых полей обязана оставить признаки снятыми. }
  ChiClaim(not Spec.HasNonce, 'схема: признак выставлен без поля');
  ChiClaim(Spec.IndexNonce = -1, 'схема: индекс задан без поля');
  ChiBranch(IdHl, 'no-special-fields');

  { Копирование всей схемы не имеет права сбить предвычисленное. }
  Swapped := Spec2;
  ChiClaim(Swapped.IndexNonce = Spec2.IndexNonce,
    'схема: копия схемы потеряла индекс');
  ChiClaim(Swapped.EntryFields[Swapped.IndexNonce].Name = 'Nonce',
    'схема: копия схемы указывает не на то поле');
  ChiBranch(IdHl, 'copy-keeps-index');

  { ── Вложенные схемы ── }
  Spec := SigContainer('modify', 'order', ckObject,
    [F('nonce', ftInt)],
    [F('asset', ftInt), F('limitPx', ftStr)]);
  Body := BuildBody(Spec, Values);
  ChiClaim(Body = '{"type":"modify","order":{"asset":5,"limitPx":"64250.15"},'
                  + '"nonce":1735689600123}',
    'схема: тело с вложенным объектом собрано не так: ' + Body);
  ChiBranch(IdHl, 'container-object');
  Acc := ChiMix(Acc, Length(Body));

  Spec := SigContainer('batch', 'orders', ckArray,
    [F('nonce', ftInt)],
    [F('asset', ftInt), F('sz', ftStr)]);
  Body := BuildBody(Spec, Values);
  ChiClaim(Body = '{"type":"batch","orders":[{"asset":5,"sz":"0.0035"}],'
                  + '"nonce":1735689600123}',
    'схема: тело с вложенным массивом собрано не так: ' + Body);
  ChiBranch(IdHl, 'container-array');

  { ── Порядок полей значим ── }
  Spec := SigFlat('order', [F('asset', ftInt), F('isBuy', ftBool)]);
  Swapped := SigFlat('order', [F('isBuy', ftBool), F('asset', ftInt)]);
  Body := BuildBody(Spec, Values);
  Other := BuildBody(Swapped, Values);
  ChiClaim(Body <> Other, 'схема: перестановка полей дала то же тело');
  ChiClaim(Digest(Body) <> Digest(Other),
    'схема: перестановка полей дала тот же отпечаток');
  ChiBranch(IdHl, 'order-matters');
  Acc := ChiMix(Acc, Length(Body) + Length(Other));

  { ── Открытый массив: граница и пустой случай ── }
  Spec := SigFlat('ping', []);
  ChiClaim(Length(Spec.EntryFields) = 0, 'схема: пустое описание дало поля');
  Body := BuildBody(Spec, Values);
  ChiClaim(Body = '{"type":"ping",}',
    'схема: тело без полей собрано не так: ' + Body);
  ChiBranch(IdHl, 'empty-schema');

  { Длинное описание: перепись поэлементно не имеет права потерять край. }
  SetLength(Values, 40);
  for I := 0 to 39 do
  begin
    Values[I].Name := 'f' + IntToStr(I);
    Values[I].Text := IntToStr(I * 3);
  end;
  Spec := SigFlat('long', [F('f0', ftInt), F('f1', ftInt), F('f2', ftInt),
    F('f3', ftInt), F('f4', ftInt), F('f5', ftInt), F('f6', ftInt),
    F('f7', ftInt), F('f8', ftInt), F('f9', ftInt)]);
  ChiClaim(Length(Spec.EntryFields) = 10, 'схема: длинное описание урезано');
  ChiClaim(Spec.EntryFields[0].Name = 'f0', 'схема: первое поле потеряно');
  ChiClaim(Spec.EntryFields[9].Name = 'f9', 'схема: последнее поле потеряно');
  Body := BuildBody(Spec, Values);
  ChiClaim(Pos('"f9":27', Body) > 0, 'схема: последнее поле не в теле');
  ChiClaim(BuildBodyBackwards(Spec, Values) = Body,
    'схема: обратная сборка длинного тела разошлась');
  ChiBranch(IdHl, 'long-schema');
  Acc := ChiMix(Acc, Length(Body));

  Result := Int64(Acc and $7FFFFFFFFFFF);
end;

end.
