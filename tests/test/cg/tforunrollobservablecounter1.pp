{ %OPT=-O3 }
program tforunrollobservablecounter1;

{$mode delphiunicode}
{$modeswitch inlinevars}
{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}

type
  TIntFunc = reference to function: Integer;

var
  GlobalCounter: Integer;
  GlobalTrail: Integer;

procedure ObserveGlobal; noinline;
begin
  GlobalTrail:=GlobalTrail*10+GlobalCounter;
end;

function CapturedCounter: Integer;
var
  Index: Integer;
  Steps: array[1..3] of TIntFunc;
begin
  for Index:=1 to 3 do
    Steps[Index]:=function: Integer
      begin
        Result:=Index;
      end;
  Result:=Steps[1]()*100+Steps[3]();
end;

begin
  if CapturedCounter<>404 then
    Halt(1);
  GlobalTrail:=0;
  for GlobalCounter:=1 to 3 do
    ObserveGlobal;
  if GlobalTrail<>123 then
    Halt(2);
end.
