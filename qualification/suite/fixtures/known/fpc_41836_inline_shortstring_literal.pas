program bug;

{$mode objfpc}

               // string/shortstring, any string type
function sp(s: shortstring): pansichar; inline; // inline    = prints "h"
var p: pansichar;                               // no inline = prints "hello"
begin
  getmem(p, length(s)+1);
  move(s[1], p^, length(s));
  p[length(s)] := #0;
  result := p;
end;

var q: pansichar;
begin
  q := sp('hello');
  if (q[0] <> 'h') or (q[1] <> 'e') or (q[2] <> 'l') or
     (q[3] <> 'l') or (q[4] <> 'o') or (q[5] <> #0) then
  begin
    writeln('FAIL fpc-41836');
    freemem(q);
    halt(1);
  end;
  freemem(q);
  writeln('PASS fpc-41836');
  {$ifdef WINDOWS}readln;{$endif}
end. 
