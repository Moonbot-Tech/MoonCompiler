{ %OPT=-O3 }

program tloopopaqueeffects1;

{$mode delphi}
{$R-}{$Q-}

type
  TMutator = procedure;

var
  GlobalIndex: Integer;
  GlobalScale: Integer;
  Values: array[0..2] of Integer;

procedure BumpGlobalScale; noinline;
begin
  Inc(GlobalScale);
end;

procedure SelectLastValue; noinline;
begin
  GlobalIndex := 2;
end;

procedure SelectLastValueThroughPointer(Index: PInteger); noinline;
begin
  Index^ := 2;
end;

function GlobalChangedByCall: Integer; noinline;
var
  I: Integer;
begin
  GlobalScale := 2;
  Result := 0;
  for I := 1 to 3 do
  begin
    Inc(Result, I * GlobalScale);
    If I = 1 then
      BumpGlobalScale;
  end;
end;

function GlobalChangedByProcVar: Integer; noinline;
var
  I: Integer;
  Mutator: TMutator;
begin
  GlobalScale := 2;
  Mutator := BumpGlobalScale;
  Result := 0;
  for I := 1 to 3 do
  begin
    Inc(Result, I * GlobalScale);
    If I = 1 then
      Mutator;
  end;
end;

function LocalChangedByNestedCall: Integer; noinline;
var
  I: Integer;
  Scale: Integer;

  procedure BumpScale;
  begin
    Inc(Scale);
  end;

begin
  Scale := 2;
  Result := 0;
  for I := 1 to 3 do
  begin
    Inc(Result, I * Scale);
    If I = 1 then
      BumpScale;
  end;
end;

function LocalChangedBetweenRepeatedExpressions: Int64; noinline;
var
  I: Integer;
  Inner: Integer;
  Outer: Integer;
  Total: Int64;
  Value: Cardinal;

  procedure BumpValue;
  begin
    Value := Value + Cardinal(3);
  end;

begin
  Value := Cardinal(4);
  Total := 0;
  for Outer := 1 to 2 do
    for Inner := 1 to 3 do
    begin
      I := (Outer - 1) * 3 + Inner;
      Total := Total + Int64(I * Value);
      BumpValue;
      Total := Total + Int64(I * Value);
    end;
  Result := Total;
end;

function GlobalIndexChangedByCall: Integer; noinline;
var
  I: Integer;
begin
  GlobalIndex := 0;
  Result := 0;
  for I := 1 to 2 do
  begin
    Inc(Result, Values[GlobalIndex]);
    If I = 1 then
      SelectLastValue;
  end;
end;

function EscapedLocalIndexChangedByCall: Integer; noinline;
var
  I: Integer;
  Index: Integer;
  IndexPointer: PInteger;
begin
  Index := 0;
  IndexPointer := @Index;
  Result := 0;
  for I := 1 to 2 do
  begin
    Inc(Result, Values[Index]);
    If I = 1 then
      SelectLastValueThroughPointer(IndexPointer);
  end;
end;

function StableLocalControl: Integer; noinline;
var
  I: Integer;
  Scale: Integer;
begin
  Scale := 2;
  Result := 0;
  for I := 1 to 6 do
    Inc(Result, I * Scale);
end;

begin
  Values[0] := 10;
  Values[1] := 20;
  Values[2] := 30;
  If GlobalChangedByCall <> 17 then
    Halt(1);
  If GlobalChangedByProcVar <> 17 then
    Halt(2);
  If LocalChangedByNestedCall <> 17 then
    Halt(3);
  If GlobalIndexChangedByCall <> 40 then
    Halt(4);
  If EscapedLocalIndexChangedByCall <> 40 then
    Halt(5);
  If StableLocalControl <> 42 then
    Halt(6);
  If LocalChangedBetweenRepeatedExpressions <> 651 then
    Halt(7);
end.
