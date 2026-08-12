{ %OPT=-O3 }
program tforunrollfinally2;

{$mode delphiunicode}
{$modeswitch inlinevars}

procedure Exercise(var Trail: AnsiString);
begin
  for var I:=0 to 3 do
    try
      Trail:=Trail+AnsiChar(48+I);
    finally
      Trail:=Trail+'x';
    end;
end;

var
  Trail: AnsiString;
begin
  Exercise(Trail);
  If Trail<>'0x1x2x3x' then
    Halt(1);
end.
