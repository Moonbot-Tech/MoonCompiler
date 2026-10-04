program rtl_api_dictionary_scan_contracts;
{$mode delphiunicode}{$modeswitch functionreferences}{$modeswitch anonymousfunctions}
uses SysUtils, Generics.Collections, Generics.Defaults;
type
  TModuloComparer = class(TEqualityComparer<Integer>)
    function Equals(const Left,Right: Integer): Boolean; override;
    function GetHashCode(const Value: Integer): UInt32; override;
  end;
  TDerivedFactory = class(TGenericsHashFactory);
  TDerivedDictionary = TOpenAddressingLP<Integer,Integer,TDerivedFactory>;
  TOverrideDictionary = class(TDictionary<Integer,Integer>)
    Calls: Integer;
    function ContainsValue(const Value: Integer; const Comparer: IEqualityComparer<Integer>): Boolean; override;
  end;
  TProbe<T> = class
    class procedure Run(const Values: array of T; const Missing: T); static;
  end;
var Checked,EqualsCalls: UInt64;
procedure Require(Condition: Boolean; const Why: ShortString);
begin
  If not Condition then raise Exception.Create(Why);
  Inc(Checked);
end;
function TModuloComparer.Equals(const Left,Right: Integer): Boolean;
begin
  Inc(EqualsCalls);
  Result := (Left and 7)=(Right and 7);
end;
function TModuloComparer.GetHashCode(const Value: Integer): UInt32;
begin
  Result := UInt32(Value and 7);
end;
function TOverrideDictionary.ContainsValue(const Value: Integer; const Comparer: IEqualityComparer<Integer>): Boolean;
begin
  Inc(Calls);
  Result := inherited ContainsValue(Value,Comparer);
end;
class procedure TProbe<T>.Run(const Values: array of T; const Missing: T);
var D: TDictionary<Integer,T>; i: Integer;
begin
  D := TDictionary<Integer,T>.Create;
  try
    Require(not D.ContainsValue(Missing),'empty value lookup');
    D.Capacity := Length(Values);
    Require(not D.ContainsValue(Missing,nil),'nil comparer remains unused in reserved empty table');
    for i := 0 to High(Values) do D.Add(i,Values[i]);
    for i := 0 to High(Values) do
    begin
      Require(D.ContainsValue(Values[i]),'default value hit');
      Require(D.ContainsValue(Values[i],TEqualityComparer<T>.Default),'explicit default value hit');
    end;
    Require(not D.ContainsValue(Missing),'default value miss');
    for i := 0 to High(Values) do If Odd(i) then D.Remove(i);
    for i := 0 to High(Values) do
      Require(D.ContainsValue(Values[i])=not Odd(i),'removed slot visibility');
    D.Clear;
    Require(not D.ContainsValue(Missing),'cleared reserved table');
  finally
    D.Free;
  end;
end;
procedure Correctness;
var D: TOverrideDictionary; E: TDerivedDictionary; C: IEqualityComparer<Integer>; i: Integer;
begin
  TProbe<Integer>.Run([-2147483647,-1,0,1,2147483647],13579);
  TProbe<Cardinal>.Run([0,1,$80000000,$ffffffff],13579);
  TProbe<Int64>.Run([-9223372036854775807,-1,0,1,9223372036854775807],13579);
  TProbe<UInt64>.Run([0,1,$8000000000000000,$ffffffffffffffff],13579);
  TProbe<Byte>.Run([0,1,128,255],13);
  TProbe<Word>.Run([0,1,32768,65535],13);
  TProbe<UnicodeString>.Run(['','alpha','beta',UnicodeString(#0)],'missing');
  D := TOverrideDictionary.Create;
  C := TModuloComparer.Create;
  E := TDerivedDictionary.Create;
  try
    D.Add(1,42);
    Require(D.ContainsValue(42),'virtual overload default');
    Require(D.Calls=1,'one argument preserves virtual overload dispatch');
    Require(D.ContainsValue(50,C),'custom value equality');
    Require(not D.ContainsValue(51,C),'custom value inequality');
    Require(EqualsCalls=2,'custom equality remains observable');
    D.Add(2,0);
    Require(D.ContainsValue(0),'default zero in occupied slot');
    D.Remove(2);
    Require(not D.ContainsValue(0),'deleted zero and empty slots do not match');
    for i := 0 to 31 do E.Add(i,i*3);
    for i := 0 to 31 do Require(E.ContainsValue(i*3),'nondefault factory value hit');
    Require(not E.ContainsValue(-1),'nondefault factory value miss');
  finally
    E.Free;
    C := nil;
    D.Free;
  end;

end;
procedure DenseValues;
type TIntValues = array of Integer;
  TUIntValues = array of Cardinal;
  TInt64Values = array of Int64;
  TUInt64Values = array of UInt64;
var A: TIntValues; B: TUIntValues; C: TInt64Values; D: TUInt64Values; I: Integer;
begin
  SetLength(A,256);
  SetLength(B,256);
  SetLength(C,256);
  SetLength(D,256);
  for I := 0 to 255 do
  begin
    A[I] := I-128;
    B[I] := Cardinal($80000000)+Cardinal(I);
    C[I] := -Int64($100000000)+I;
    D[I] := UInt64($8000000000000000)+UInt64(I);
  end;
  B[0] := 0;
  C[0] := 0;
  D[0] := 0;
  TProbe<Integer>.Run(A,13579);
  TProbe<Cardinal>.Run(B,13579);
  TProbe<Int64>.Run(C,13579);
  TProbe<UInt64>.Run(D,13579);
end;
begin
  Correctness;
  DenseValues;
  Writeln('RTL_API_DICTIONARY_SCAN_CONTRACTS_OK');
end.
