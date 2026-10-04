{ %OPT=-O3 }
program tforunrollunleashedcounter1;

{$mode unleashed}

uses
  SysUtils;

type
  TIntegerAlias = type Integer;
  TSmall = 1..10;
  TMarker = (markerZero,markerOne,markerTwo,markerThree,markerFour);

procedure Consume(const Value: Integer); noinline;
begin
  if Value<0 then
    Halt(1);
end;

function Probe: Integer;
var
  Index: Integer;
begin
  Index:=77;
  for Index:=1 to 3 do
    Consume(Index);
  Result:=Index;
end;

function ImplicitResultProbe: Integer;
begin
  Result:=77;
  for Result:=1 to 3 do
    Consume(Result);
end;

function AliasResultProbe: TIntegerAlias;
begin
  Result:=77;
  for Result:=1 to 3 do
    Consume(Integer(Result));
end;

function SmallResultProbe: TSmall;
begin
  Result:=7;
  for Result:=1 to 3 do
    Consume(Result);
end;

function EnumResultProbe: TMarker;
begin
  Result:=markerFour;
  for Result:=markerOne to markerThree do
    Consume(Ord(Result));
end;

procedure RaiseAt(const Value: Integer); noinline;
begin
  if Value=2 then
    raise Exception.Create('counter observation');
end;

function ExceptionalResultProbe: Integer;
begin
  Result:=77;
  try
    for Result:=1 to 3 do
      RaiseAt(Result);
  except
  end;
end;

begin
  if Probe<>3 then
    Halt(2);
  if ImplicitResultProbe<>3 then
    Halt(3);
  if AliasResultProbe<>3 then
    Halt(4);
  if SmallResultProbe<>3 then
    Halt(5);
  if EnumResultProbe<>markerThree then
    Halt(6);
  if ExceptionalResultProbe<>2 then
    Halt(7);
end.
