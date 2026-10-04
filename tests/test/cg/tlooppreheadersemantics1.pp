{ %OPT=-O3 }

program tlooppreheadersemantics1;

{$mode delphiunicode}
{$R-}{$Q-}

uses
  SysUtils;

type
  TIntArray = array of Integer;

var
  Data: array[0..3] of Int64;
  Indices,
  Factors: TIntArray;

function ReadAddress(Count: Integer): Int64;
var
  I: Integer;
begin
  Result := 77;
  for I := 1 to Count do
    Result := Result + Data[Indices[0]];
end;

function ReadGuardedAddress(Count: Integer): Int64;
var
  I: Integer;
begin
  Result := 77;
  for I := 1 to Count do
    If Length(Indices) <> 0 then
      Result := Result + Data[Indices[0]];
end;

function ReadFactor(Count: Integer): Integer;
var
  I: Integer;
begin
  Result := 77;
  for I := 1 to Count do
    Result := I * Factors[0];
end;

{$Q+}
function CheckedProduct(First, Last, Factor: Integer): Integer;
var
  I: Integer;
begin
  Result := 77;
  for I := First to Last do
    Result := I * Factor;
end;
{$Q-}

begin
  Data[2] := 30;

  { A preheader must not evaluate a trapping invariant for an empty loop or
    before the source-level guard inside a non-empty loop. }
  If ReadAddress(0) <> 77 then
    Halt(1);
  If ReadGuardedAddress(4) <> 77 then
    Halt(2);
  If ReadFactor(0) <> 77 then
    Halt(3);

  SetLength(Indices, 1);
  Indices[0] := 2;
  If ReadAddress(4) <> 197 then
    Halt(4);

  SetLength(Factors, 1);
  Factors[0] := 3;
  If ReadFactor(4) <> 12 then
    Halt(5);

  { Checked strength reduction must not create seed/latch operations which
    are absent from the source execution path. }
  If CheckedProduct(High(Integer), 0, 3) <> 77 then
    Halt(6);
  If CheckedProduct(High(Integer), High(Integer), 1) <> High(Integer) then
    Halt(7);
  If CheckedProduct(2, 4, 3) <> 12 then
    Halt(8);
end.
