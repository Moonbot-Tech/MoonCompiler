program lab_005_o3_ansistring_codepage;

{$mode delphi}{$H+}

type
  TAnsi866 = type AnsiString(866);

var
  Text866: TAnsi866;

begin
  Str(123, Text866);
  If StringCodePage(Text866) <> 866 then
    Halt(1);
end.
