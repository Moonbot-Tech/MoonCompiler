unit devil_gen_unit;

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch anonymousfunctions}
  {$modeswitch functionreferences}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, devil_runtime, devil_gen_second;

type
  TDvlUnitRec = record
    A: Integer;
    B: Int64;
    S: AnsiString;
  end;

  TDvlUnitBox<T> = record
    Value: T;
    function Read: T;
  end;

  TDvlUnitAlias = TDvlUnitRec;

const
  DvlUnitConst00000 = Int64($235A87B6444A8822);
const
  DvlUnitConst00002 = Int64(-1);
function DvlUnitFn00003(X: SmallInt): SmallInt;
const
  DvlUnitConst00004 = SmallInt(32244);
const
  DvlUnitConst00005 = Word(257);
function DvlUnitFn00006(X: Integer): Integer;
function DvlUnitFn00007(const R: TDvlUnitRec): Int64;
function DvlUnitFn00008(const R: TDvlUnitRec): Int64;
function DvlUnitFn00009(X: UInt64): UInt64;
function DvlUnitFn00011(const R: TDvlUnitRec): Int64;
function DvlUnitFn00013(X: ShortInt): ShortInt;
function DvlUnitFn00014(X: SmallInt): SmallInt;
function DvlUnitFn00015(const R: TDvlUnitRec): Int64;
function DvlUnitFn00016(X: ShortInt): ShortInt; inline;
function DvlUnitFn00017(X: Byte): Byte;
const
  DvlUnitConst00019 = SmallInt(32766);
function DvlUnitFn00020(const R: TDvlUnitRec): Int64;
function DvlUnitFn00023(X: UInt64): UInt64;
function DvlUnitFn00024(X: SmallInt): SmallInt; inline;
function DvlUnitFn00025(const R: TDvlUnitRec): Int64;
const
  DvlUnitConst00026 = Integer(1);
function DvlUnitFn00027(const R: TDvlUnitRec): Int64;
function DvlUnitFn00029(X: Integer): Integer;
const
  DvlUnitConst00031 = ShortInt(15);
function DvlUnitFn00032(X: Word): Word; inline;
function DvlUnitFn00034(const R: TDvlUnitRec): Int64;
function DvlUnitFn00036(X: SmallInt): SmallInt; inline;
const
  DvlUnitConst00037 = Integer(-1385784022);
function DvlUnitFn00038(X: Int64): Int64;
function DvlUnitFn00039(const R: TDvlUnitRec): Int64;

implementation

function TDvlUnitBox<T>.Read: T;
begin
  Result := Value;
end;

function DvlUnitFn00003(X: SmallInt): SmallInt;
begin
  Result := DvlSecondEchoi16(X);
end;

function DvlUnitFn00006(X: Integer): Integer;
begin
  Result := DvlSecondEchoi32(X);
end;

function DvlUnitFn00007(const R: TDvlUnitRec): Int64;
begin
  Result := R.A + R.B + Length(R.S);
end;

function DvlUnitFn00008(const R: TDvlUnitRec): Int64;
begin
  Result := R.A + R.B + Length(R.S);
end;

function DvlUnitFn00009(X: UInt64): UInt64;
begin
  Result := DvlSecondEchou64(X);
end;

function DvlUnitFn00011(const R: TDvlUnitRec): Int64;
begin
  Result := R.A + R.B + Length(R.S);
end;

function DvlUnitFn00013(X: ShortInt): ShortInt;
begin
  Result := DvlSecondEchoi8(X);
end;

function DvlUnitFn00014(X: SmallInt): SmallInt;
var
  B: TDvlSecondBox<SmallInt>;
begin
  B.Value := X;
  Result := B.Read;
end;

function DvlUnitFn00015(const R: TDvlUnitRec): Int64;
begin
  Result := R.A + R.B + Length(R.S);
end;

function DvlUnitFn00016(X: ShortInt): ShortInt;
begin
  Result := X;
end;

function DvlUnitFn00017(X: Byte): Byte;
begin
  Result := DvlSecondEchou8(X);
end;

function DvlUnitFn00020(const R: TDvlUnitRec): Int64;
begin
  Result := R.A + R.B + Length(R.S);
end;

function DvlUnitFn00023(X: UInt64): UInt64;
var
  B: TDvlSecondBox<UInt64>;
begin
  B.Value := X;
  Result := B.Read;
end;

function DvlUnitFn00024(X: SmallInt): SmallInt;
begin
  Result := X;
end;

function DvlUnitFn00025(const R: TDvlUnitRec): Int64;
begin
  Result := R.A + R.B + Length(R.S);
end;

function DvlUnitFn00027(const R: TDvlUnitRec): Int64;
begin
  Result := R.A + R.B + Length(R.S);
end;

function DvlUnitFn00029(X: Integer): Integer;
var
  B: TDvlSecondBox<Integer>;
begin
  B.Value := X;
  Result := B.Read;
end;

function DvlUnitFn00032(X: Word): Word;
begin
  Result := X;
end;

function DvlUnitFn00034(const R: TDvlUnitRec): Int64;
begin
  Result := R.A + R.B + Length(R.S);
end;

function DvlUnitFn00036(X: SmallInt): SmallInt;
begin
  Result := X;
end;

function DvlUnitFn00038(X: Int64): Int64;
var
  B: TDvlSecondBox<Int64>;
begin
  B.Value := X;
  Result := B.Read;
end;

function DvlUnitFn00039(const R: TDvlUnitRec): Int64;
begin
  Result := R.A + R.B + Length(R.S);
end;

end.
