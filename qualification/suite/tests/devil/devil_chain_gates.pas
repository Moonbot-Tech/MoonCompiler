unit devil_chain_gates;

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch INLINEVARS}
  {$modeswitch anonymousfunctions}
  {$modeswitch functionreferences}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils, devil_runtime;

type
  TDvlStep = function(X: Int64): Int64;

var
  DvlGateTouched: Int64;

function DvlCrossLoop(X: Int64; Next: TDvlStep): Int64;
function DvlCrossBranch(X: Int64; Next: TDvlStep): Int64;
function DvlCrossGuarded(X: Int64; Next: TDvlStep): Int64;
function DvlCrossCase(X: Int64; Next: TDvlStep): Int64;
function DvlCrossRetry(X: Int64; Next: TDvlStep): Int64;
function DvlCrossText(const V: RawByteString): RawByteString;

implementation

function DvlCrossText(const V: RawByteString): RawByteString;
begin
  { the bytes cross the boundary as bytes: no conversion here }
  Result := V;
end;

function DvlCrossLoop(X: Int64; Next: TDvlStep): Int64;
begin
  Result := 0;
  for var Pass := 1 to 1 do
    Result := Next(X);
end;

function DvlCrossBranch(X: Int64; Next: TDvlStep): Int64;
begin
  If DvlGateTouched >= 0 then
    Result := Next(X)
  else
    Result := not X;
end;

function DvlCrossGuarded(X: Int64; Next: TDvlStep): Int64;
begin
  Result := 0;
  try
    Result := Next(X);
  finally
    Inc(DvlGateTouched);
  end;
end;

function DvlCrossCase(X: Int64; Next: TDvlStep): Int64;
begin
  Result := 0;
  case DvlGateTouched and 1 of
    0, 1: Result := Next(X);
  else
    Result := not X;
  end;
end;

function DvlCrossRetry(X: Int64; Next: TDvlStep): Int64;
begin
  Result := 0;
  for var Attempt := 1 to 2 do
    If Attempt = 2 then
      Result := Next(X);
end;

end.
