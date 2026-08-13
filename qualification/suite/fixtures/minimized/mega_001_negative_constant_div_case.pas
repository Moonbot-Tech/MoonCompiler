program mega_001_negative_constant_div_case;

{$mode objfpc}

uses
  SysUtils;

var
  Value, Quotient: LongInt;

begin
  if ParamCount <> 1 then
    Halt(64);
  Value := StrToInt(ParamStr(1));
  Quotient := Value div -19;
  if Quotient <> -8567586 then
    Halt(2);
end.
