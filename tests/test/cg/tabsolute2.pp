{ %OPT=-O3 }
program tabsolute2;

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

function SumWords(P: QWord): QWord; inline;
var
  Source: TWords absolute P;
  I: Integer;
begin
  Result := 0;
  for I := Low(Source) to High(Source) do
    Inc(Result,Source[I]);
end;

function ReadThroughPointer(P: QWord): QWord; inline;
var
  Ref: ^QWord;
begin
  Ref := @P;
  Result := Ref^;
end;

function AddOne(P: QWord): QWord; inline;
begin
  Result := P+1;
end;

var
  Input: QWord;
begin
  if Rotate(QWord($1122334455667788)) <> QWord($3344556677881122) then
    Halt(1);

  Input := QWord($8877665544332211);
  if Rotate(Input) <> QWord($6655443322118877) then
    Halt(2);

  if SumWords(QWord($1122334455667788)) <> QWord($11154) then
    Halt(3);

  if ReadThroughPointer(QWord($0123456789ABCDEF)) <> QWord($0123456789ABCDEF) then
    Halt(4);

  if AddOne(41) <> 42 then
    Halt(5);
end.
