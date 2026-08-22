unit rtti_generic_dependency_types;

{$mode delphi}
interface

type
  {$RTTI EXPLICIT METHODS([vcPublic]) PROPERTIES([]) FIELDS([])}
  TGenericPair<TKey, TValue> = record
  public
    Key: TKey;
    Value: TValue;
  end;

  TMethodSubject<TKey, TValue> = record
  public
    function ReadValue: TGenericPair<TKey, TValue>;
  end;

  {$RTTI EXPLICIT METHODS([vcPublic]) PROPERTIES([]) FIELDS([])}
  TMethodArgumentSubject = record
  public
    function ReadValue(const AValue: TGenericPair<Byte, UnicodeString>): Integer;
  end;

  TIndexedKey = TGenericPair<SmallInt, AnsiString>;

  {$RTTI EXPLICIT METHODS([]) PROPERTIES([vcPublic]) FIELDS([])}
  TPropertySubject = record
  private
    FValue: TGenericPair<Word, Double>;
    function GetIndexed(const AKey: TIndexedKey): Integer;
  public
    property Value: TGenericPair<Word, Double> read FValue;
    property Indexed[const AKey: TIndexedKey]: Integer read GetIndexed;
  end;

function TouchExtendedDependency: Int64;

implementation

function TMethodSubject<TKey, TValue>.ReadValue:
  TGenericPair<TKey, TValue>;
begin
  Result.Key:=Default(TKey);
  Result.Value:=Default(TValue);
end;

function TMethodArgumentSubject.ReadValue(
  const AValue: TGenericPair<Byte, UnicodeString>): Integer;
begin
  Result:=AValue.Key+Length(AValue.Value);
end;

function TPropertySubject.GetIndexed(
  const AKey: TIndexedKey): Integer;
begin
  Result:=AKey.Key+Length(AKey.Value);
end;

function TouchExtendedDependency: Int64;
var
  Argument: TGenericPair<Byte, UnicodeString>;
  ArgumentSubject: TMethodArgumentSubject;
  Indexed: TIndexedKey;
  PropertySubject: TPropertySubject;
  Subject: TMethodSubject<Integer, Int64>;
  Pair: TGenericPair<Integer, Int64>;
begin
  if not Assigned(TypeInfo(TMethodSubject<Integer, Int64>)) then
    Exit(-1);
  if not Assigned(TypeInfo(TMethodArgumentSubject)) then
    Exit(-2);
  if not Assigned(TypeInfo(TPropertySubject)) then
    Exit(-3);
  Pair:=Subject.ReadValue;
  Argument.Key:=1;
  Argument.Value:='a';
  Indexed.Key:=2;
  Indexed.Value:='bc';
  PropertySubject.FValue.Key:=0;
  PropertySubject.FValue.Value:=0;
  Result:=Pair.Key+Pair.Value+
    ArgumentSubject.ReadValue(Argument)+
    PropertySubject.Indexed[Indexed]-6;
  if PropertySubject.Value.Key<>0 then
    Inc(Result);
end;

end.
