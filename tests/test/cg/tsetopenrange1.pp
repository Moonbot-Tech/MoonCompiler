{ %OPT=-O3 }
program tsetopenrange1;

{$mode delphi}
{$R-}

uses
  usetopenrange1;

const
  EmptyConstantRange: TByteSet = [Byte(255)..Byte(0)];

var
  S: TByteSet;
  B: TBasedSet;

begin
  if EmptyConstantRange <> [] then
    Halt(1);

  S := [0..255];
  ReplaceByteRange(S, 255, 0);
  if S <> [] then
    Halt(2);

  S := [17..33];
  ReplaceByteRangeChecked(S, 1, 0);
  if S <> [] then
    Halt(3);

  S := [42];
  ExtendByteRange(S, 255, 0);
  if S <> [42] then
    Halt(4);

  S := [0..255];
  ReplaceByteRange(S, 0, 255);
  if S <> [0..255] then
    Halt(5);

  S := [];
  ReplaceByteRange(S, 17, 17);
  if S <> [17] then
    Halt(6);

  B := [120..180];
  ReplaceBasedRange(B, 200, 100);
  if B <> [] then
    Halt(7);

  B := [];
  ReplaceBasedRange(B, 100, 200);
  if B <> [100..200] then
    Halt(8);
end.
