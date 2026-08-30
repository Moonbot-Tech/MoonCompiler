program seh_regvar_codegen;

{$mode unleashed}
{$Q-}{$R-}

var
  Guard: Integer;

type
  TRangeEnumerator = class
  private
    FCurrent, FLast: Integer;
  public
    constructor Create(ALast: Integer);
    function MoveNext: Boolean;
    property Current: Integer read FCurrent;
  end;

  TRange = record
    Last: Integer;
    function GetEnumerator: TRangeEnumerator;
  end;

constructor TRangeEnumerator.Create(ALast: Integer);
begin
  inherited Create;
  FCurrent := 0;
  FLast := ALast;
end;

function TRangeEnumerator.MoveNext: Boolean;
begin
  Inc(FCurrent);
  Result := FCurrent <= FLast;
end;

function TRange.GetEnumerator: TRangeEnumerator;
begin
  Result := TRangeEnumerator.Create(Last);
end;

function ScanWithIrrelevantTry(const Data: RawByteString): QWord; noinline;
var
  I: Integer;
  Sum: QWord;
begin
  try
    If Guard < 0 then
      Guard := 0;
  except
    Guard := -1;
  end;
  Sum := 0;
  for I := 1 to Length(Data) do
    Inc(Sum, Byte(Data[I]));
  Result := Sum;
end;

function ScanGeneratedCleanup(Limit: Integer): QWord; noinline;
var
  Range: TRange;
  Value: Integer;
  Sum: QWord;
begin
  Range.Last := Limit;
  Sum := 17;
  for Value in Range do
    Inc(Sum, QWord(Value * 3));
  Result := Sum;
end;

var
  Data: RawByteString;
  I: Integer;
begin
  SetLength(Data, 4096);
  for I := 1 to Length(Data) do
    Data[I] := AnsiChar(I);
  WriteLn('SEHREGVAR-CODEGEN:',
    ScanWithIrrelevantTry(Data) + ScanGeneratedCleanup(100));
end.
