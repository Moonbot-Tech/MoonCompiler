program utf8_delphi_control;

{ Control: Delphi mode keeps its historical default source code page, so
  the same bytes still read as one character per byte. }
{$mode delphi}

var
  S: string = '한글';

begin
  WriteLn(Length(S));
end.
