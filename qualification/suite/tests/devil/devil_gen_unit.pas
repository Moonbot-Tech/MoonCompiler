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

function DvlUnitFn00000(X: ShortInt): ShortInt; inline;
const
  DvlUnitConst00001 = ShortInt(17);
const
  DvlUnitConst00002 = Word(1);
function DvlUnitFn00003(X: Byte): Byte;
function DvlUnitFn00004(X: Cardinal): Cardinal;
function DvlUnitFn00005(X: Cardinal): Cardinal; inline;
function DvlUnitFn00008(const R: TDvlUnitRec): Int64;
const
  DvlUnitConst00009 = Int64($7FFFFFFFFFFFFFFF);
const
  DvlUnitConst00010 = UInt64($A2A0DF0F5566107B);
function DvlUnitFn00012(X: ShortInt): ShortInt; inline;
const
  DvlUnitConst00014 = UInt64($7FA0172D7B56F129);
function DvlUnitFn00015(X: Byte): Byte;
function DvlUnitFn00018(X: Word): Word;
const
  DvlUnitConst00019 = Cardinal(2);
function DvlUnitFn00021(const R: TDvlUnitRec): Int64;
function DvlUnitFn00022(const R: TDvlUnitRec): Int64;
function DvlUnitFn00023(X: Integer): Integer;
function DvlUnitFn00024(const R: TDvlUnitRec): Int64;
function DvlUnitFn00025(X: ShortInt): ShortInt;
function DvlUnitFn00026(const R: TDvlUnitRec): Int64;
function DvlUnitFn00028(const R: TDvlUnitRec): Int64;

implementation

function TDvlUnitBox<T>.Read: T;
begin
  Result := Value;
end;

function DvlUnitFn00000(X: ShortInt): ShortInt;
begin
  Result := X;
end;

function DvlUnitFn00003(X: Byte): Byte;
var
  B: TDvlSecondBox<Byte>;
begin
  B.Value := X;
  Result := B.Read;
end;

function DvlUnitFn00004(X: Cardinal): Cardinal;
var
  B: TDvlSecondBox<Cardinal>;
begin
  B.Value := X;
  Result := B.Read;
end;

function DvlUnitFn00005(X: Cardinal): Cardinal;
begin
  Result := X;
end;

function DvlUnitFn00008(const R: TDvlUnitRec): Int64;
begin
  Result := R.A + R.B + Length(R.S);
end;

function DvlUnitFn00012(X: ShortInt): ShortInt;
begin
  Result := X;
end;

function DvlUnitFn00015(X: Byte): Byte;
var
  B: TDvlSecondBox<Byte>;
begin
  B.Value := X;
  Result := B.Read;
end;

function DvlUnitFn00018(X: Word): Word;
var
  B: TDvlSecondBox<Word>;
begin
  B.Value := X;
  Result := B.Read;
end;

function DvlUnitFn00021(const R: TDvlUnitRec): Int64;
begin
  Result := R.A + R.B + Length(R.S);
end;

function DvlUnitFn00022(const R: TDvlUnitRec): Int64;
begin
  Result := R.A + R.B + Length(R.S);
end;

function DvlUnitFn00023(X: Integer): Integer;
begin
  Result := DvlSecondEchoi32(X);
end;

function DvlUnitFn00024(const R: TDvlUnitRec): Int64;
begin
  Result := R.A + R.B + Length(R.S);
end;

function DvlUnitFn00025(X: ShortInt): ShortInt;
begin
  Result := DvlSecondEchoi8(X);
end;

function DvlUnitFn00026(const R: TDvlUnitRec): Int64;
begin
  Result := R.A + R.B + Length(R.S);
end;

function DvlUnitFn00028(const R: TDvlUnitRec): Int64;
begin
  Result := R.A + R.B + Length(R.S);
end;

end.
