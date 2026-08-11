{ %OPT=-O2 }
program tmoonuinttostr1;

{$mode delphi}

uses
  SysUtils;

begin
  if UIntToStr(Int64(-1)) <> '18446744073709551615' then
    Halt(1);
end.
