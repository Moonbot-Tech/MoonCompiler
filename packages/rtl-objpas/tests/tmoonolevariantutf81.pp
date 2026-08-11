{ %OPT=-O2 }
program tmoonolevariantutf81;

{$mode delphi}

uses
  Variants;

type
  TSource = class
  private
    FValue: OleVariant;
    function GetValue: OleVariant;
  public
    property Value: OleVariant read GetValue write FValue;
  end;

function TSource.GetValue: OleVariant;
begin
  Result := FValue;
end;

function Accept(const Value, Expected: UTF8String): Boolean;
begin
  Result := Value = Expected;
end;

var
  Source: TSource;
  Value: OleVariant;
  Expected: UTF8String;
begin
  Source := TSource.Create;
  try
    Expected := UTF8Encode(UnicodeString(WideChar($03BB)) + WideChar($0434));
    Source.Value := UnicodeString(WideChar($03BB)) + WideChar($0434);
    Value := Source.Value;
    if not Accept(Value, Expected) then
      Halt(1);
    if not Accept(Source.Value, Expected) then
      Halt(2);
  finally
    Source.Free;
  end;
end.
