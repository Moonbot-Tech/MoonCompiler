unit devil_gen_second;

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
{$endif}
{$Q-}{$R-}

interface

type
  TDvlSecondBox<T> = record
    Value: T;
    function Read: T;
  end;

function DvlSecondEchoi8(X: ShortInt): ShortInt; inline;
function DvlSecondEchou8(X: Byte): Byte; inline;
function DvlSecondEchoi16(X: SmallInt): SmallInt; inline;
function DvlSecondEchou16(X: Word): Word; inline;
function DvlSecondEchoi32(X: Integer): Integer; inline;
function DvlSecondEchou32(X: Cardinal): Cardinal; inline;
function DvlSecondEchoi64(X: Int64): Int64; inline;
function DvlSecondEchou64(X: UInt64): UInt64; inline;

implementation

function TDvlSecondBox<T>.Read: T;
begin
  Result := Value;
end;

function DvlSecondEchoi8(X: ShortInt): ShortInt;
begin
  Result := X;
end;

function DvlSecondEchou8(X: Byte): Byte;
begin
  Result := X;
end;

function DvlSecondEchoi16(X: SmallInt): SmallInt;
begin
  Result := X;
end;

function DvlSecondEchou16(X: Word): Word;
begin
  Result := X;
end;

function DvlSecondEchoi32(X: Integer): Integer;
begin
  Result := X;
end;

function DvlSecondEchou32(X: Cardinal): Cardinal;
begin
  Result := X;
end;

function DvlSecondEchoi64(X: Int64): Int64;
begin
  Result := X;
end;

function DvlSecondEchou64(X: UInt64): UInt64;
begin
  Result := X;
end;

end.
