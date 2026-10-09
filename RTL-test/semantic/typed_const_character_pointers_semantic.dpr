program typed_const_character_pointers_semantic;
{$APPTYPE CONSOLE}
uses System.SysUtils;
type
  TEntry = record
    A: PAnsiChar;
    W: PWideChar;
  end;
const
  Entries: array[0..2] of TEntry = (
    (A: PAnsiChar('Load file'); W: PWideChar('wide '#$2022)),
    (A: PAnsiChar('a'#0'b'); W: PWideChar('x'#0'y')),
    (A: PAnsiChar(''); W: PWideChar('')));
  NullEntry: TEntry = (A: nil; W: nil);
begin
  If (AnsiString(Entries[0].A) <> 'Load file') or (UnicodeString(Entries[0].W) <> 'wide '#$2022) then
    raise Exception.Create('Character pointer cast storage');
  If (Entries[1].A[2] <> 'b') or (Entries[1].W[2] <> 'y') or
     (Entries[1].A[3] <> #0) or (Entries[1].W[3] <> #0) then
    raise Exception.Create('Embedded zero or final terminator');
  If (Entries[2].A = nil) or (Entries[2].W = nil) or
     (Entries[2].A^ <> #0) or (Entries[2].W^ <> #0) then
    raise Exception.Create('Empty literal storage');
  If (NullEntry.A <> nil) or (NullEntry.W <> nil) then
    raise Exception.Create('Nil pointer constant');
  WriteLn('TYPED_CONST_CHARACTER_POINTERS_PASS');
end.
