unit uintrinsicresulttype1;

{$mode delphi}

interface

function CrossUnitKinds(const Value: Extended): Integer; inline;
function CrossUnitWidth(const A, B, C: Double): Boolean; inline;

implementation

uses
  Math;

function Kind(Value: Double): Integer; overload;
begin
  Result := 64;
end;

function Kind(Value: Extended): Integer; overload;
begin
  Result := 80;
end;

function CrossUnitKinds(const Value: Extended): Integer;
begin
  Result := Kind(Int(Value)) + Kind(Frac(Value)) + Kind(Exp(Value)) +
    Kind(Ln(Value)) + Kind(Sin(Value)) + Kind(Cos(Value)) +
    Kind(ArcTan(Value)) + Kind(Sqrt(Value));
end;

function CrossUnitWidth(const A, B, C: Double): Boolean;
begin
  Result := IsInfinite(Int(A) * B * C) and
    IsInfinite((Frac(A) + A) * B * C) and
    IsInfinite((Ln(A) + A) * B * C) and
    IsInfinite((Sin(A) + A) * B * C) and
    IsInfinite((Cos(A) + A) * B * C) and
    IsInfinite((ArcTan(A) + A) * B * C) and
    IsInfinite((Sqrt(A) + A) * B * C);
end;

end.
