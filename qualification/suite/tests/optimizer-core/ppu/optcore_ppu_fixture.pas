unit optcore_ppu_fixture;

{$mode delphi}

interface

type
  TBox<T> = record
    Item: T;
  end;

  TManagedBox = record
    Text: UnicodeString;
    Values: array of Integer;
  end;

function InlineMix(A, B: Integer): Integer; inline;
function BuildManaged(Seed: Integer): TManagedBox;
function FoldManaged(const Value: TManagedBox): Integer;

implementation

uses
  SysUtils;

function InlineMix(A, B: Integer): Integer;
begin
  Result := ((A * 33) xor B) + 17;
end;

function BuildManaged(Seed: Integer): TManagedBox;
var
  Index: Integer;
begin
  Result.Text := 'ppu-' + IntToStr(Seed);
  SetLength(Result.Values, 4);
  for Index := 0 to High(Result.Values) do
    Result.Values[Index] := (Seed + Index) * 3;
end;

function FoldManaged(const Value: TManagedBox): Integer;
var
  Index: Integer;
begin
  Result := 0;
  for Index := 1 to Length(Value.Text) do
    Inc(Result, Ord(Value.Text[Index]));
  for Index := 0 to High(Value.Values) do
    Inc(Result, Value.Values[Index]);
end;

end.
