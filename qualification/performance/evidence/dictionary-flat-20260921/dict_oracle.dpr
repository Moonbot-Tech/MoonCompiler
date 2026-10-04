program dict_oracle;

{ Differential oracle for the flat dictionary: the same deterministic
  operation script runs against TDictionary; the program is built once
  against the base Generics and once against the flat one, and the two
  outputs must be identical (results, enumeration order, notifications,
  ownership, exceptions). }

{$ifndef FPC}
  {$APPTYPE CONSOLE}
{$endif}
{$ifdef FPC}
  {$mode delphi}{$H+}
{$endif}
{$Q-}{$R-}

uses
  {$if defined(FPC) and not defined(PULSE_DEFAULT_MM)}
  mormot.core.fpcx64mm,
  {$ifend}
  SysUtils,
  Generics.Defaults,
  Generics.Collections;

var
  Seed: UInt64 = $9E3779B97F4A7C15;
  Digest: UInt64 = 14695981039346656037;
  Lines: Integer = 0;

function Rnd: UInt32;
begin
  Seed := Seed xor (Seed shl 13);
  Seed := Seed xor (Seed shr 7);
  Seed := Seed xor (Seed shl 17);
  Result := UInt32(Seed shr 11);
end;

procedure Mix(V: UInt64);
begin
  Digest := (Digest xor V) * 1099511628211;
end;

procedure MixStr(const S: string);
var
  i: Integer;
begin
  Mix(Length(S));
  for i := 1 to Length(S) do
    Mix(Ord(S[i]));
end;

procedure Report(const Name: string);
begin
  WriteLn(Name, ' digest=', IntToHex(Digest, 16));
  Digest := 14695981039346656037;
  Inc(Lines);
end;

type
  TEnumKey = (ekA, ekB, ekC, ekD, ekE, ekF, ekG, ekH);
  TRecKey = record
    A: Integer;
    B: Int64;
  end;
  TCounted = class
  public
    Id: Integer;
    destructor Destroy; override;
  end;

var
  Destroyed: Integer = 0;

destructor TCounted.Destroy;
begin
  Inc(Destroyed);
  inherited;
end;

{ ---- generic script over one dictionary type ---- }

type
  TScript<TKey, TValue> = class
  public type
    TMakeKey = function(I: Integer): TKey;
    TMakeValue = function(I: Integer): TValue;
    TMixKey = procedure(const K: TKey);
    TMixValue = procedure(const V: TValue);
  public
    class procedure Run(const Name: string; D: TDictionary<TKey, TValue>;
      MakeKey: TMakeKey; MakeValue: TMakeValue; MixKey: TMixKey; MixValue: TMixValue;
      KeySpace, Ops: Integer; OrderFree: Boolean = False);
  end;

class procedure TScript<TKey, TValue>.Run(const Name: string; D: TDictionary<TKey, TValue>;
  MakeKey: TMakeKey; MakeValue: TMakeValue; MixKey: TMixKey; MixValue: TMixValue;
  KeySpace, Ops: Integer; OrderFree: Boolean);
{$ifdef ORACLE_ORDERFREE}
const
  ForceOrderFree = True;
{$else}
const
  ForceOrderFree = False;
{$endif}
var
  i, k, op: Integer;
  V: TValue;
  P: TPair<TKey, TValue>;
  Arr: TArray<TPair<TKey, TValue>>;
  Key: TKey;
  Saved, Acc: UInt64;
begin
  OrderFree := OrderFree or ForceOrderFree;
  for i := 1 to Ops do
  begin
    k := Rnd mod KeySpace;
    op := Rnd mod 16;
    case op of
      0..3:
        D.AddOrSetValue(MakeKey(k), MakeValue(i));
      4, 5:
        begin
          Mix(Ord(D.TryAdd(MakeKey(k), MakeValue(i))));
        end;
      6:
        D.Remove(MakeKey(k));
      7, 8:
        begin
          If D.TryGetValue(MakeKey(k), V) then
            MixValue(V)
          else
            Mix(7);
        end;
      9:
        Mix(Ord(D.ContainsKey(MakeKey(k))));
      10:
        begin
          try
            V := D[MakeKey(k)];
            MixValue(V);
          except
            on E: EListError do Mix(10);
          end;
        end;
      11:
        begin
          try
            D[MakeKey(k)] := MakeValue(i + 1000000);
            Mix(11);
          except
            on E: EListError do Mix(12);
          end;
        end;
      12:
        begin
          P := D.ExtractPair(MakeKey(k));
          MixKey(P.Key);
          MixValue(P.Value);
        end;
      13:
        begin
          try
            D.Add(MakeKey(k), MakeValue(i));
            Mix(13);
          except
            on E: EListError do Mix(14);
          end;
        end;
      14:
        If (Rnd mod 64) = 0 then
          D.TrimExcess;
      15:
        If (Rnd mod 256) = 0 then
          D.Clear;
    end;
    Mix(D.Count);
  end;
  { enumeration order and contents; address-keyed tables enumerate in an
    address-dependent order, so those fold order-free }
  Mix(D.Count);
  Mix(D.Capacity);
  Acc := 0;
  for P in D do
  begin
    Saved := Digest;
    MixKey(P.Key);
    MixValue(P.Value);
    If OrderFree then
    begin
      Acc := Acc + Digest;
      Digest := Saved;
    end;
  end;
  for Key in D.Keys do
  begin
    Saved := Digest;
    MixKey(Key);
    If OrderFree then
    begin
      Acc := Acc + Digest;
      Digest := Saved;
    end;
  end;
  for V in D.Values do
  begin
    Saved := Digest;
    MixValue(V);
    If OrderFree then
    begin
      Acc := Acc + Digest;
      Digest := Saved;
    end;
  end;
  Arr := D.ToArray;
  Mix(Length(Arr));
  for i := 0 to High(Arr) do
  begin
    Saved := Digest;
    MixKey(Arr[i].Key);
    If OrderFree then
    begin
      Acc := Acc + Digest;
      Digest := Saved;
    end;
  end;
  Mix(Acc);
  Report(Name);
end;

{ ---- key / value makers ---- }

function KInt(I: Integer): Integer; begin Result := I * 7919 - 100; end;
function KI64(I: Integer): Int64; begin Result := Int64(I) * 6364136223846793005; end;
function KCard(I: Integer): Cardinal; begin Result := Cardinal(I) * 2654435761; end;
function KWord(I: Integer): Word; begin Result := Word(I * 31); end;
function KByte(I: Integer): Byte; begin Result := Byte(I * 7); end;
function KEnum(I: Integer): TEnumKey; begin Result := TEnumKey(I mod 8); end;
function KStr(I: Integer): string; begin Result := 'K' + IntToStr(I * 7919) + 'USDT'; end;
function KAnsi(I: Integer): AnsiString; begin Result := AnsiString('a' + IntToStr(I * 13)); end;
function KPtr(I: Integer): Pointer; begin Result := Pointer(NativeUInt(I) * 64 + $10000); end;
function KRec(I: Integer): TRecKey; begin FillChar(Result, SizeOf(Result), 0); Result.A := I; Result.B := Int64(I) * 3; end;  // padding bytes enter the binary hash
function KDbl(I: Integer): Double; begin Result := I * 0.5; end;
function KStrCI(I: Integer): string;
begin
  Result := 'Mixed' + IntToStr(I * 3);
  If (I and 1) = 1 then
    Result := UpperCase(Result);
end;

var
  Objs: TArray<TObject>;
function KObj(I: Integer): TObject; begin Result := Objs[I mod Length(Objs)]; end;
function KClass(I: Integer): TClass;
begin
  case I mod 4 of
    0: Result := TObject;
    1: Result := TCounted;
    2: Result := EListError;
    else Result := TStringBuilder;
  end;
end;

function VInt(I: Integer): Integer; begin Result := I xor $55AA; end;
function VStr(I: Integer): string; begin Result := 'v' + IntToStr(I); end;
function VRec(I: Integer): TRecKey; begin FillChar(Result, SizeOf(Result), 0); Result.A := I; Result.B := -I; end;
function VDbl(I: Integer): Double; begin Result := I / 8; end;

procedure MInt(const V: Integer); begin Mix(Cardinal(V)); end;
procedure MI64(const V: Int64); begin Mix(UInt64(V)); end;
procedure MCard(const V: Cardinal); begin Mix(V); end;
procedure MWord(const V: Word); begin Mix(V); end;
procedure MByte(const V: Byte); begin Mix(V); end;
procedure MEnum(const V: TEnumKey); begin Mix(Ord(V)); end;
procedure MStr(const V: string); begin MixStr(V); end;
procedure MAnsi(const V: AnsiString); begin MixStr(string(V)); end;
procedure MPtr(const V: Pointer); begin Mix(NativeUInt(V)); end;
procedure MRec(const V: TRecKey); begin Mix(Cardinal(V.A)); Mix(UInt64(V.B)); end;
procedure MDbl(const V: Double); begin Mix(PUInt64(@V)^); end;
procedure MObj(const V: TObject);
var
  i: Integer;
begin
  for i := 0 to High(Objs) do
    If Objs[i] = V then
      Mix(i);
  If V = nil then
    Mix(999);
end;
procedure MClass(const V: TClass);
begin
  If V = nil then
    Mix(0)
  else
    MixStr(V.ClassName);
end;

{ ---- notifications ---- }

type
  TNotifyLog = class
  public
    Count: Integer;
    procedure OnKey(Sender: TObject; const Item: Integer; Action: TCollectionNotification);
    procedure OnValue(Sender: TObject; const Item: string; Action: TCollectionNotification);
  end;

procedure TNotifyLog.OnKey(Sender: TObject; const Item: Integer; Action: TCollectionNotification);
begin
  Inc(Count);
  Mix(1000 + Cardinal(Item));
  Mix(Ord(Action));
end;

procedure TNotifyLog.OnValue(Sender: TObject; const Item: string; Action: TCollectionNotification);
begin
  Inc(Count);
  MixStr(Item);
  Mix(Ord(Action));
end;

type
  TOverridingDict = class(TDictionary<Integer, Integer>)
  public
    KeyCalls, ValueCalls: Integer;
    Acc: UInt64;          // order-free fold: Clear notifies in table order
  protected
    procedure KeyNotify(const AKey: Integer; ACollectionNotification: TCollectionNotification); override;
    procedure ValueNotify(const AValue: Integer; ACollectionNotification: TCollectionNotification); override;
  end;

procedure TOverridingDict.KeyNotify(const AKey: Integer; ACollectionNotification: TCollectionNotification);
begin
  inherited;
  Inc(KeyCalls);
  Acc := Acc + ((UInt64(2000 + Cardinal(AKey)) * 1099511628211) xor UInt64(Ord(ACollectionNotification)));
end;

procedure TOverridingDict.ValueNotify(const AValue: Integer; ACollectionNotification: TCollectionNotification);
begin
  inherited;
  Inc(ValueCalls);
  Acc := Acc + ((UInt64(3000 + Cardinal(AValue)) * 1099511628211) xor UInt64(Ord(ACollectionNotification)));
end;

procedure NotificationTests;
var
  D: TDictionary<Integer, string>;
  Log: TNotifyLog;
  O: TOverridingDict;
  OD: TObjectDictionary<Integer, TCounted>;
  C: TCounted;
  i: Integer;
begin
  { handlers assigned after creation, then removed }
  Log := TNotifyLog.Create;
  D := TDictionary<Integer, string>.Create;
  try
    D.AddOrSetValue(1, 'one');
    D.OnKeyNotify := Log.OnKey;
    D.OnValueNotify := Log.OnValue;
    D.AddOrSetValue(1, 'uno');           // value replaced: removed + added
    D.AddOrSetValue(2, 'two');
    D[2] := 'dos';
    D.Remove(1);
    D.ExtractPair(2);
    D.Add(3, 'three');
    D.OnValueNotify := nil;
    D.AddOrSetValue(3, 'tres');          // key handler only
    D.OnKeyNotify := nil;
    D.AddOrSetValue(4, 'four');          // nothing
    D.Clear;
    Mix(Log.Count);
    Report('notify-handlers count=' + IntToStr(Log.Count));
  finally
    D.Free;
    Log.Free;
  end;

  { subclass overriding the virtuals, no handlers }
  O := TOverridingDict.Create;
  try
    for i := 1 to 50 do
      O.AddOrSetValue(i mod 17, i);
    for i := 1 to 10 do
      O.Remove(i);
    O[11] := 5;
    O.Clear;
    Mix(O.Acc);
    Report('notify-override key=' + IntToStr(O.KeyCalls) + ' value=' + IntToStr(O.ValueCalls));
  finally
    O.Free;
  end;

  { TObjectDictionary owning values: replaced and removed values are freed }
  Destroyed := 0;
  OD := TObjectDictionary<Integer, TCounted>.Create([doOwnsValues]);
  try
    for i := 1 to 20 do
    begin
      C := TCounted.Create;
      C.Id := i;
      OD.AddOrSetValue(i mod 7, C);      // replaces free the old value
    end;
    OD.Remove(3);
    Mix(Destroyed);
    Report('ownership destroyed-before-free=' + IntToStr(Destroyed));
  finally
    OD.Free;
  end;
  Report('ownership destroyed-after-free=' + IntToStr(Destroyed));
end;

procedure Run;
var
  i: Integer;
  DInt: TDictionary<Integer, Integer>;
  DI64: TDictionary<Int64, string>;
  DCard: TDictionary<Cardinal, Double>;
  DWord: TDictionary<Word, Integer>;
  DByte: TDictionary<Byte, string>;
  DEnum: TDictionary<TEnumKey, Integer>;
  DStr: TDictionary<string, Integer>;
  DStrV: TDictionary<string, string>;
  DAnsi: TDictionary<AnsiString, TRecKey>;
  DPtr: TDictionary<Pointer, Integer>;
  DObj: TDictionary<TObject, string>;
  DClass: TDictionary<TClass, Integer>;
  DRec: TDictionary<TRecKey, Integer>;
  DDbl: TDictionary<Double, Integer>;
  DStrCI: TDictionary<string, Integer>;
  DIntCap: TDictionary<Integer, Integer>;
begin
  SetLength(Objs, 40);
  for i := 0 to High(Objs) do
    Objs[i] := TObject.Create;

  DInt := TDictionary<Integer, Integer>.Create;
  TScript<Integer, Integer>.Run('int', DInt, KInt, VInt, MInt, MInt, 300, 20000);
  DInt.Free;
  DI64 := TDictionary<Int64, string>.Create;
  TScript<Int64, string>.Run('i64', DI64, KI64, VStr, MI64, MStr, 500, 20000);
  DI64.Free;
  DCard := TDictionary<Cardinal, Double>.Create;
  TScript<Cardinal, Double>.Run('cardinal', DCard, KCard, VDbl, MCard, MDbl, 200, 10000);
  DCard.Free;
  DWord := TDictionary<Word, Integer>.Create;
  TScript<Word, Integer>.Run('word', DWord, KWord, VInt, MWord, MInt, 100, 10000);
  DWord.Free;
  DByte := TDictionary<Byte, string>.Create;
  TScript<Byte, string>.Run('byte', DByte, KByte, VStr, MByte, MStr, 40, 5000);
  DByte.Free;
  DEnum := TDictionary<TEnumKey, Integer>.Create;
  TScript<TEnumKey, Integer>.Run('enum', DEnum, KEnum, VInt, MEnum, MInt, 8, 3000);
  DEnum.Free;
  DStr := TDictionary<string, Integer>.Create;
  TScript<string, Integer>.Run('string', DStr, KStr, VInt, MStr, MInt, 400, 20000);
  DStr.Free;
  DStrV := TDictionary<string, string>.Create(1000);
  TScript<string, string>.Run('string-string-cap', DStrV, KStr, VStr, MStr, MStr, 2000, 30000);
  DStrV.Free;
  DAnsi := TDictionary<AnsiString, TRecKey>.Create;
  TScript<AnsiString, TRecKey>.Run('ansistring', DAnsi, KAnsi, VRec, MAnsi, MRec, 300, 10000);
  DAnsi.Free;
  DPtr := TDictionary<Pointer, Integer>.Create;
  TScript<Pointer, Integer>.Run('pointer', DPtr, KPtr, VInt, MPtr, MInt, 300, 10000);
  DPtr.Free;
  DObj := TDictionary<TObject, string>.Create;
  TScript<TObject, string>.Run('object', DObj, KObj, VStr, MObj, MStr, 40, 10000, True);
  DObj.Free;
  DClass := TDictionary<TClass, Integer>.Create;
  TScript<TClass, Integer>.Run('classref', DClass, KClass, VInt, MClass, MInt, 4, 2000, True);
  DClass.Free;
  DRec := TDictionary<TRecKey, Integer>.Create;
  TScript<TRecKey, Integer>.Run('record', DRec, KRec, VInt, MRec, MInt, 300, 10000);
  DRec.Free;
  DDbl := TDictionary<Double, Integer>.Create;
  TScript<Double, Integer>.Run('double', DDbl, KDbl, VInt, MDbl, MInt, 300, 10000);
  DDbl.Free;
  DStrCI := TDictionary<string, Integer>.Create(TIStringComparer.Ordinal);
  TScript<string, Integer>.Run('string-ci', DStrCI, KStrCI, VInt, MStr, MInt, 300, 10000);
  DStrCI.Free;
  DIntCap := TDictionary<Integer, Integer>.Create(4096);
  TScript<Integer, Integer>.Run('int-cap4096', DIntCap, KInt, VInt, MInt, MInt, 100000, 30000);
  DIntCap.Free;

  NotificationTests;

  for i := 0 to High(Objs) do
    Objs[i].Free;
  WriteLn('ORACLE_END lines=', Lines, ' digest=', IntToHex(Digest, 16));
end;

begin
  Run;
end.
