program dictionary_sparse_ordinal_semantic;

{$mode delphiunicode}{$H+}

uses SysUtils, Generics.Collections, Generics.Defaults;

type
  TLargeKey = record
    Parts: array[0..7] of QWord;
  end;
  TParity = class(TEqualityComparer<Integer>)
    Calls: Integer;
    function Equals(const Left, Right: Integer): Boolean; override;
    function GetHashCode(const Value: Integer): Integer; override;
  end;

function TParity.Equals(const Left, Right: Integer): Boolean;
begin
  Inc(Calls);
  Result := (Left and 1) = (Right and 1);
end;

function TParity.GetHashCode(const Value: Integer): Integer;
begin
  Result := Value and 1;
end;

procedure Check(Value: Boolean);
begin
  if not Value then Halt(1);
end;

var
  D32: TDictionary<Integer, Integer>;
  D64: TDictionary<TLargeKey, QWord>;
  Equality: IEqualityComparer<Integer>;
  Parity: TParity;
  Key: TLargeKey;
  Reserve, I: Integer;
begin
  Parity := TParity.Create;
  Equality := Parity;
  for Reserve in [1, 2, 8, 32] do
  begin
    D32 := TDictionary<Integer, Integer>.Create(64 * Reserve);
    D64 := TDictionary<TLargeKey, QWord>.Create(64 * Reserve);
    try
      Check(not D32.ContainsValue(0));
      Check(not D64.ContainsValue(0));
      for I := 0 to 63 do
      begin
        Key := Default(TLargeKey);
        Key.Parts[0] := I;
        Key.Parts[7] := I xor $55;
        D32.Add(I, I * 2);
        D64.Add(Key, QWord(I) shl 32 or QWord(I));
      end;
      for I := 0 to 63 do
      begin
        Check(D32.ContainsValue(I * 2));
        Check(D64.ContainsValue(QWord(I) shl 32 or QWord(I)));
      end;
      Check(not D32.ContainsValue(-1));
      Check(not D64.ContainsValue(High(QWord)));
      Parity.Calls := 0;
      Check(D32.ContainsValue(10000, Equality));
      Check(Parity.Calls = 1);
      Parity.Calls := 0;
      Check(not D32.ContainsValue(1, Equality));
      Check(Parity.Calls = 64);
      D32.Clear;
      D32.Capacity := 1024;
      D32.Add(1, 0);
      Check(D32.ContainsValue(0) and not D32.ContainsValue(1));
    finally
      D64.Free;
      D32.Free;
    end;
  end;
  WriteLn('DICTIONARY_SPARSE_ORDINAL_OK');
end.
