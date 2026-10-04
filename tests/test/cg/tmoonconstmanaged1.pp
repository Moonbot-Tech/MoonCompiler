{ %OPT=-O3 -OoAUTOINLINE }
program tmoonconstmanaged1;
{$mode delphiunicode}{$inline on}
uses SysUtils, umoonconstmanaged1;
var Caught: Integer;
procedure RunRound(Id: Integer; Fail: Boolean);
begin
  if Nested(MakeValue(Id),Fail)<>2*Id then Halt(1);
end;
var I: Integer;
begin
  for I:=1 to 32 do
  begin
    RunRound(I,False);
    try
      RunRound(I,True);
      Halt(2);
    except
      on E: Exception do
        if E.Message='consumer' then Inc(Caught) else raise;
    end;
    if (Created<>Destroyed) or (Initialized<>Finalized) then Halt(3);
  end;
  if Caught<>32 then Halt(4);
  WriteLn('created=',Created,' finalized=',Finalized,' copies=',Copies);
  WriteLn('const managed result ok');
end.
