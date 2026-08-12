program tnestedgenericarray1;

{$mode delphi}
{$modeswitch inlinevars}

uses
  Generics.Collections;

type
  TIntMatrix = TArray<TArray<longint>>;

var
  values: TIntMatrix;

begin
  setlength(values,2,3);
  for var i:=0 to 1 do
    for var j:=0 to 2 do
      values[i,j]:=i*10+j;
  TArray.Sort<longint>(values[0]);
  if (length(values)<>2) or
     (length(values[0])<>3) or
     (values[1,2]<>12) then
    halt(1);
end.
