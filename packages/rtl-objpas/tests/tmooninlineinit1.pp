{ %OPT=-O2 }
program tmooninlineinit1;

{$mode delphi}
{$modeswitch inlinevars}

uses
  SysUtils,
  Variants;

begin
  const Values = [1, 2, 4, 8];
  if (Length(Values) <> 4) or (Values[3] <> 8) then
    Halt(1);
  var DynamicValue: Variant := 'Alice';
  var Text: string := DynamicValue;
  if Text <> 'Alice' then
    Halt(2);
end.
