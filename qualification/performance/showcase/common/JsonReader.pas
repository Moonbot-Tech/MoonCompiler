unit JsonReader;

// Configure once per WS reader. Read writes final unmanaged records.
// Array results borrow reusable storage: consume before the next Read.
// Read=false clears Value and invalidates external field destinations.
//
// Path — путь через точку к объекту записи (для массива T — к массиву объектов);
// '' — поля записи лежат в корне пакета (только для одиночной записи).
//
// Для новых программ (в том числе Арбитража) текст в record лучше представлять
// как TJsonSlice: Slice('s', 'Symbol') привязывает JSON к полю Symbol: TJsonSlice.
// Срез — UTF-8 указатель + длина в исходном пакете, без копирования/аллокаций.
// Пакет должен жить и оставаться неизменным до окончания работы со срезами;
// Text не заканчивается #0. JSON escapes в выбранном срезе дают Read=false.
// Если нужна декодированная строка, привязать внешнюю переменную reader:
//   Header.Str('topic', Symbol, 'publicTrade.'); // UTF-8 -> string, префикс проверяется и снимается
// Str использует буфер до следующего Read; присваивание не отделяет копию.
// Управляемые строки внутри T не поддерживаются. Полный контракт — JsonReaderScan.
{$INLINE ON}
{$OPTIMIZATION ON}

interface

uses mormot.core.base, System.SysUtils, System.Rtti, System.TypInfo, JsonReaderScan;

type
  TJsonReader<T> = class
  private
    FRoot, FRow: TReaderSchema;
    FContext: TRttiContext;
    FType: TRttiType;
    FStorage: T;
    FRowBase: Pointer;
    FCapacity, FCount, FItemSize: NativeInt;
    FIsArray: Boolean;
    procedure Reserve(Count: NativeInt);
    procedure Reset;
    procedure NextRow;
    function Bind(const Key, Member: string; Kind: TScanKind; Required: Boolean; Missing: Int64 = 0): PScanField;
  public
    constructor Create(const Path: string);
    destructor Destroy; override;
    procedure Num(const Key, Member: string);
    procedure Slice(const Key, Member: string);
    procedure Int64As(const Key, Member: string; Convert: TInt64Convert);
    procedure MapText(const Key, Member: string; const Texts: array of RawUtf8; const Values: array of Int64);
    procedure MapBool(const Key, Member: string; FalseValue, TrueValue: Int64); overload;
    procedure MapBool(const Key, Member: string; FalseValue, TrueValue, MissingValue: Int64); overload;
    function Read(const Packet: RawUtf8; var Value: T): Boolean;
    property Header: TReaderSchema read FRoot;
    property Fields: TReaderSchema read FRow;
  end;

implementation

uses mormot.core.unicode;

constructor TJsonReader<T>.Create(const Path: string);
var Parts: TArray<string>; Parent: TReaderSchema;
begin
  inherited Create;
  FContext := TRttiContext.Create;
  FType := FContext.GetType(TypeInfo(T));
  FIsArray := FType.TypeKind = tkDynArray;
  If FIsArray then FType := TRttiDynamicArrayType(FType).ElementType;
  If (FType.TypeKind <> tkRecord) or FType.IsManaged then
    raise EArgumentException.Create('Expected an unmanaged record or an array of unmanaged records');
  FItemSize := FType.TypeSize;
  FRoot := TReaderSchema.Create;
  FRow := FRoot;
  If Path <> '' then begin
    Parts := Path.Split(['.']);
    Parent := FRoot;
    for var I := 0 to High(Parts) - 1 do Parent := Parent.Obj(StringToUtf8(Parts[I]));
    If FIsArray then FRow := Parent.Rows(StringToUtf8(Parts[High(Parts)]))
    else FRow := Parent.Obj(StringToUtf8(Parts[High(Parts)]));
  end else If FIsArray then raise EArgumentException.Create('Array result needs a path');
  If FIsArray then begin
    FRoot.BeforeParse := Reset;
    FRow.BeforeRow := NextRow;
    Reserve(32);
  end;
end;

destructor TJsonReader<T>.Destroy;
begin
  FreeAndNil(FRoot);
  FContext.Free;
  inherited;
end;

procedure TJsonReader<T>.Reserve(Count: NativeInt);
begin
  DynArraySetLength(PPointer(@FStorage)^, TypeInfo(T), 1, @Count);
  FCapacity := Count;
end;

procedure TJsonReader<T>.Reset;
begin
  FCount := 0;
end;

procedure TJsonReader<T>.NextRow;
begin
  If FCount = FCapacity then begin
    Reserve(FCapacity * 2);
  end;
  FRowBase := PByte(PPointer(@FStorage)^) + FCount * FItemSize;
  Inc(FCount);
end;

function TJsonReader<T>.Bind(const Key, Member: string; Kind: TScanKind; Required: Boolean; Missing: Int64): PScanField;
var Field: TRttiField;
begin
  Field := FType.GetField(Member);
  If Field = nil then raise EArgumentException.Create('Record field/RTTI missing: ' + Member);
  case Kind of
    skNumber, skTime:
      If (Field.FieldType.TypeKind <> tkFloat) or
        (GetTypeData(Field.FieldType.Handle).FloatType <> ftDouble) then
        raise EArgumentException.Create('Expected Double: ' + Member);
    skMappedText, skMappedBool:
      If not (Field.FieldType.TypeKind in [tkEnumeration, tkInteger, tkInt64 {$ifdef FPC}, tkBool {$endif}]) then
        raise EArgumentException.Create('Expected ordinal: ' + Member);
    skSlice:
      If Field.FieldType.Handle <> TypeInfo(TJsonSlice) then raise EArgumentException.Create('Expected TJsonSlice: ' + Member);
  end;
  Result := FRow.Add(StringToUtf8(Key), Kind, Pointer(Field.Offset), Required);
  Result.Base := @FRowBase;
  Result.Width := Field.FieldType.TypeSize;
  If not Required then FRow.SetDefault(Result, Missing);
end;

procedure TJsonReader<T>.Num(const Key, Member: string);
begin
  Bind(Key, Member, skNumber, true);
end;

procedure TJsonReader<T>.Slice(const Key, Member: string);
begin
  Bind(Key, Member, skSlice, true);
end;

procedure TJsonReader<T>.Int64As(const Key, Member: string; Convert: TInt64Convert);
begin
  If not Assigned(Convert) then raise EArgumentException.Create('Missing integer converter');
  Bind(Key, Member, skTime, true).Convert := Convert;
end;

procedure TJsonReader<T>.MapText(const Key, Member: string; const Texts: array of RawUtf8; const Values: array of Int64);
var Field: PScanField;
begin
  If (Length(Texts) = 0) or (Length(Texts) <> Length(Values)) then raise EArgumentException.Create('Text/value mapping');
  Field := Bind(Key, Member, skMappedText, true);
  SetLength(Field.Choices, Length(Texts));
  for var I := 0 to High(Texts) do begin
    Field.Choices[I].Text := Texts[I];
    Field.Choices[I].Value := Values[I];
    var Len := Length(Texts[I]);
    If Len < 8 then begin
      If Len <> 0 then Move(Pointer(Texts[I])^, Field.Choices[I].Code, Len);
      Field.Choices[I].Code := Field.Choices[I].Code or (UInt64(34) shl (Len * 8));
      If Len = 7 then Field.Choices[I].Mask := High(UInt64)
      else Field.Choices[I].Mask := (UInt64(1) shl ((Len + 1) * 8)) - 1;
    end;
  end;
end;

procedure TJsonReader<T>.MapBool(const Key, Member: string; FalseValue, TrueValue: Int64);
var Field: PScanField;
begin
  Field := Bind(Key, Member, skMappedBool, true);
  Field.FalseValue := FalseValue;
  Field.TrueValue := TrueValue;
end;

procedure TJsonReader<T>.MapBool(const Key, Member: string; FalseValue, TrueValue, MissingValue: Int64);
var Field: PScanField;
begin
  Field := Bind(Key, Member, skMappedBool, false, MissingValue);
  Field.FalseValue := FalseValue;
  Field.TrueValue := TrueValue;
end;

function TJsonReader<T>.Read(const Packet: RawUtf8; var Value: T): Boolean;
begin
  If FIsArray then begin
    Value := Default(T);
    DynArrayFakeLength(PPointer(@FStorage)^, FCapacity);
  end else
    FRowBase := @Value;
  Result := FRoot.Parse(Packet);
  If not Result then begin
    If not FIsArray then Value := Default(T);
    exit;
  end;
  If FIsArray and (FCount <> 0) then begin
    DynArrayFakeLength(PPointer(@FStorage)^, FCount);
    Value := FStorage;
  end;
end;

end.
