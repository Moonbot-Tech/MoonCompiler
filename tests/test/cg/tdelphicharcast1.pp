{ %OPT=-O2 }

program tdelphicharcast1;

{$mode delphiunicode}

uses
  SysUtils;

var
  A: AnsiChar;
  W: WideChar;
  U: UnicodeString;
begin
  A:=AnsiChar(#233);
  W:=WideChar(A);
  if Ord(W)<>233 then
    Halt(1);

  W:=WideChar(1081);
  A:=AnsiChar(W);
  if Ord(A)<>57 then
    Halt(2);

  U:=Format('%s',[AnsiChar(#233)]);
  if (Length(U)<>1) or (Ord(U[1])<>233) then
    Halt(3);

  if DefaultSystemCodePage=1251 then
    begin
      if Ord(WideChar(AnsiChar(#233)))<>1081 then
        Halt(4);
      if Ord(AnsiChar(WideChar(#1081)))<>233 then
        Halt(5);
      U:=AnsiChar(#233);
      if (Length(U)<>1) or (Ord(U[1])<>1081) then
        Halt(6);
    end;
end.
