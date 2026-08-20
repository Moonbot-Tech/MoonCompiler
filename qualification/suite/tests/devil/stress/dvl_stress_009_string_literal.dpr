program dvl_stress_009_string_literal;
{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch anonymousfunctions}
  {$modeswitch functionreferences}
  {$modeswitch INLINEVARS}
{$endif}
{$APPTYPE CONSOLE}
{$Q-}{$R-}
uses
{$ifdef FPC}
  mormot.core.fpcx64mm,
  {$ifdef UNIX}cthreads,{$endif}
{$endif}
  SysUtils;
var
  S: string;
begin
  S := 'aaaaaaaa' + 'bbbbbbbb' + 'cccccccc' + 'dddddddd' + 'eeeeeeee' + 'ffffffff' + 'gggggggg' + 'hhhhhhhh' + 'iiiiiiii' + 'jjjjjjjj' + 'kkkkkkkk' + 'llllllll' + 'mmmmmmmm' + 'nnnnnnnn' + 'oooooooo' + 'pppppppp' + 'qqqqqqqq' + 'rrrrrrrr' + 'ssssssss' + 'tttttttt' + 'uuuuuuuu' + 'vvvvvvvv' + 'wwwwwwww' + 'xxxxxxxx' + 'yyyyyyyy' + 'zzzzzzzz' + 'aaaaaaaa' + 'bbbbbbbb' + 'cccccccc' + 'dddddddd' + 'eeeeeeee' + 'ffffffff' + 'gggggggg' + 'hhhhhhhh' + 'iiiiiiii' + 'jjjjjjjj' + 'kkkkkkkk' + 'llllllll' + 'mmmmmmmm' + 'nnnnnnnn' + 'oooooooo' + 'pppppppp' + 'qqqqqqqq' + 'rrrrrrrr' + 'ssssssss' + 'tttttttt' + 'uuuuuuuu' + 'vvvvvvvv' + 'wwwwwwww' + 'xxxxxxxx' + 'yyyyyyyy' + 'zzzzzzzz' + 'aaaaaaaa' + 'bbbbbbbb' + 'cccccccc' + 'dddddddd' + 'eeeeeeee' + 'ffffffff' + 'gggggggg' + 'hhhhhhhh' + 'iiiiiiii' + 'jjjjjjjj' + 'kkkkkkkk' + 'llllllll' + 'mmmmmmmm' + 'nnnnnnnn' + 'oooooooo' + 'pppppppp' + 'qqqqqqqq' + 'rrrrrrrr' + 'ssssssss' + 'tttttttt' + 'uuuuuuuu' + 'vvvvvvvv' + 'wwwwwwww' + 'xxxxxxxx' + 'yyyyyyyy' + 'zzzzzzzz' + 'aaaaaaaa' + 'bbbbbbbb';
  WriteLn(Length(S));
end.
