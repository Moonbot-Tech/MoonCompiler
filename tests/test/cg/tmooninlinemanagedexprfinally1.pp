{ %OPT=-O3 -OoAUTOINLINE }
program tmooninlinemanagedexprfinally1;

{$mode delphiunicode}

uses
  SysUtils;

var
  Trail: AnsiString;

procedure AddChar(C: AnsiChar);
begin
  Trail := Trail + C;
end;

procedure Run;
begin
  try
    Trail := '';
  finally
    AddChar('a');
    AddChar('b');
    AddChar('c');
  end;
end;

begin
  Run;
  if Trail <> 'abc' then
    Halt(1);
end.
