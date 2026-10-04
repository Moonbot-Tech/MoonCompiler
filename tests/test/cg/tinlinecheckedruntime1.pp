{ %OPT=-O3 }

program tinlinecheckedruntime1;

{$mode delphiunicode}
{$INLINE ON}

uses
  SysUtils;

{$Q+}{$R-}
function AddOne(Value: Int64): Int64; inline;
begin
  Result := Value + 1;
end;

function DoubleValue(Value: Int64): Int64; inline;
begin
  Result := Value * 2;
end;

function SubOne(Value: Int64): Int64; inline;
begin
  Result := Value - 1;
end;
{$Q-}

function AddOneUnchecked(Value: Int64): Int64; inline;
begin
  Result := Value + 1;
end;

{$R+}
function Narrow(Value: Integer): Byte; inline;
begin
  Result := Value;
end;
{$R-}

procedure CheckDeferred(Execute: Boolean);
var
  B: Byte;
  I: Int64;
begin
  If Execute then
  begin
    I := AddOne(High(Int64));
    B := Narrow(256);
    If (I = 0) or (B = 0) then
      Halt(90);
  end;
end;

var
  B: Byte;
  I: Int64;
  Seen: Integer;
begin
  { Folding constants exposed by inlining must neither reject compilation nor
    move the checked operation onto a path which is not executed. }
  CheckDeferred(False);

  Seen := 0;
  try
    I := AddOne(High(Int64));
    Halt(1);
  except
    on EIntOverflow do
      Inc(Seen);
  end;
  try
    I := DoubleValue(High(Int64));
    Halt(2);
  except
    on EIntOverflow do
      Inc(Seen);
  end;
  try
    I := SubOne(Low(Int64));
    Halt(3);
  except
    on EIntOverflow do
      Inc(Seen);
  end;
  try
    B := Narrow(256);
    Halt(4);
  except
    on ERangeError do
      Inc(Seen);
  end;

  If AddOne(40) <> 41 then
    Halt(5);
  If DoubleValue(21) <> 42 then
    Halt(6);
  If SubOne(42) <> 41 then
    Halt(7);
  If Narrow(255) <> 255 then
    Halt(8);
  If AddOneUnchecked(High(Int64)) <> Low(Int64) then
    Halt(10);
  If Seen <> 4 then
    Halt(9);
end.
