program tforunrollfinally1;

{$mode delphiunicode}
{$modeswitch inlinevars}

function ExerciseFinallyLoop(Seed: Integer; var Trail: AnsiString): Integer;
begin
  Result:=Seed;
  for var I:=0 to 9 do
    try
      If (I+Seed) mod 4=0 then
        Continue;
      If I=8 then
        Break;
      Inc(Result,I*3);
    finally
      Trail:=Trail+AnsiChar(65+I);
    end;
end;

var
  Trail: AnsiString;
begin
  Trail:='';
  If ExerciseFinallyLoop(107,Trail)<>173 then
    Halt(1);
  If Trail<>'ABCDEFGHI' then
    Halt(2);
end.
