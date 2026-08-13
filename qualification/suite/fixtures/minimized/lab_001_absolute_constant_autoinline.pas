program lab_001_absolute_constant_autoinline;

{$mode delphi}

type
  TWords = packed array[0..3] of Word;

function Rotate(P: QWord): QWord; inline;
var
  Source: TWords absolute P;
  Dest: TWords absolute Result;
begin
  Dest[0] := Source[3];
  Dest[1] := Source[0];
  Dest[2] := Source[1];
  Dest[3] := Source[2];
end;

var
  Got: QWord;
begin
  Got := Rotate(QWord($1122334455667788));
  if Got <> QWord($3344556677881122) then
  begin
    WriteLn('FAIL lab-001 got=', HexStr(Got, 16));
    Halt(1);
  end;
  WriteLn('PASS lab-001');
end.
