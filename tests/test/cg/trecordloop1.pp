{ %OPT=-O3 }
{$mode delphi}
program trecpromote;
type
  TInfo = record
    A: PAnsiChar;
    C: LongInt;
  end;
procedure Step(var P: PAnsiChar);
begin
  if P^ = #0 then
    P := nil
  else
    Inc(P);
end;
procedure Run(Start: PAnsiChar);
var
  Info: TInfo;
  n: Integer;
begin
  Info.A := Start;
  Info.C := 0;
  n := 0;
  while Info.A <> nil do
  begin
    Step(Info.A);
    Inc(Info.C);
    Inc(n);
    if n > 1000 then
    begin
      WriteLn('FAIL endless loop');
      Halt(1);
    end;
  end;
  if Info.C <> 4 then
  begin
    WriteLn('FAIL count=', Info.C);
    Halt(2);
  end;
end;
var S: AnsiString;
begin
  S := chr(97)+chr(98)+chr(99);
  Run(PAnsiChar(S));
end.
