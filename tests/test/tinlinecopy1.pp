program tinlinecopy1;

{$mode delphi}

uses
  uinlinecopy1;

function Branch(Depth: LongInt): LongInt; inline;
begin
  if Depth = 0 then
    Result := 1
  else
    Result := Branch(Depth - 1) + Branch(Depth - 1);
end;

var
  Depth: LongInt;

begin
  if TInlineClass.Step(1).Step(2).ReadValue <> 12 then
    Halt(1);
  if Nested(40) <> 42 then
    Halt(2);
  Depth := 4 + (ParamCount and 1);
  if Branch(Depth) <> (1 shl Depth) then
    Halt(3);
end.
