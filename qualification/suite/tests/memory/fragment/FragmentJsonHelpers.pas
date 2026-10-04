unit FragmentJsonHelpers;

interface

uses
  System.Variants,
  mormot.core.base,
  mormot.core.text,
  mormot.core.variants;

type
  TFragmentDocVariantHelper = record helper for TDocVariantData
    function TryLoadI64(const Name: RawUtf8; var Value: Int64): Boolean;
    function TryLoadStr(const Name: RawUtf8; var Value: string): Boolean;
    function SameText(const Name, Value: RawUtf8): Boolean;
  end;

implementation

function TFragmentDocVariantHelper.TryLoadI64(const Name: RawUtf8; var Value: Int64): Boolean;
var
  Error: Integer;
  Data: PVarData;
begin
  Result := False;
  Data := GetVarData(Name);
  If Data = nil then exit;
  Error := 0;
  case Cardinal(Data^.VType) of
    varInteger, varOleInt:
      Value := Data^.VInteger;
    varInt64:
      Value := Data^.VInt64;
    varString:
      begin
        Value := GetInt64(PUtf8Char(Data^.VAny), Error);
        If Error <> 0 then exit;
      end;
    varString or varByRef:
      begin
        Value := GetInt64(PPointer(Data^.VAny)^, Error);
        If Error <> 0 then exit;
      end;
  else
    exit;
  end;
  Result := True;
end;

function TFragmentDocVariantHelper.TryLoadStr(const Name: RawUtf8; var Value: string): Boolean;
var
  Data: PVarData;
begin
  Data := GetVarData(Name);
  Result := (Data <> nil) and (Cardinal(Data^.VType) > varNull);
  If Result then begin
    Value := VariantToString(PVariant(Data)^);
    Result := Value <> '';
  end;
end;

function TFragmentDocVariantHelper.SameText(const Name, Value: RawUtf8): Boolean;
var
  Data: PVarData;
begin
  Data := GetVarData(Name);
  Result := (Data <> nil) and (Cardinal(Data^.VType) > varNull) and
    VariantEquals(PVariant(Data)^, Value, False);
end;

end.
