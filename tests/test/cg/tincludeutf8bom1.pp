program tincludeutf8bom1;

{$mode unleashed}
{$codepage cp1252}

const
  { This source is UTF-8 without a BOM, so CP1252 reads each UTF-8 byte. }
  BeforeText: UnicodeString = 'é';
{$I tincludeutf8bom1.inc}
const
  AfterText: UnicodeString = 'é';

begin
  if (Length(BeforeText)<>2) or
     (Ord(BeforeText[1])<>$00c3) or
     (Ord(BeforeText[2])<>$00a9) then
    Halt(1);
  if (Length(IncludedText)<>1) or (Ord(IncludedText[1])<>$0416) then
    Halt(2);
  if (Length(NestedText)<>1) or (Ord(NestedText[1])<>$042f) then
    Halt(3);
  if (AfterText<>BeforeText) then
    Halt(4);
end.
