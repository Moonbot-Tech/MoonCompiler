{ %OPT=-Sr }
{$mode iso}
{ test that put(file) advances the file pointer correctly (issue #41609) }
program test(input, output, textfile);
var
  textfile: text;
  s : array[1..100] of char;
begin
  rewrite(textfile);
  textfile^ := 'O';
  put(textfile);
  textfile^ := 'h';
  put(textfile);
  textfile^ := 'a';
  put(textfile);
  textfile^ := 'b';
  put(textfile);
  writeln(textfile);
  close(textfile);

  assign(textfile,'TEXTFILE.txt');
  reset(textfile);
  readln(textfile,s);
  if s[1]<>'O' then
    halt(1);
  if s[2]<>'h' then
    halt(2);
  if s[3]<>'a' then
    halt(3);
  if s[4]<>'b' then
    halt(4);
  close(textfile);
  erase(textfile);

  writeln('ok');
end.
