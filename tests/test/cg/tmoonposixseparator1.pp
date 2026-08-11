{ %TARGET=linux }
{ %OPT=-O2 }
program tmoonposixseparator1;

{$mode delphi}

uses
  SysUtils;

var
  Saved: Boolean;
begin
  Saved := TreatBackslashAsDirectorySeparator;
  try
    TreatBackslashAsDirectorySeparator := False;
    if ToSingleByteFileSystemEncodedFileName(UnicodeString('a\b')) <> 'a\b' then
      Halt(1);
    TreatBackslashAsDirectorySeparator := True;
    if ToSingleByteFileSystemEncodedFileName(UnicodeString('a\b')) <> 'a/b' then
      Halt(2);
  finally
    TreatBackslashAsDirectorySeparator := Saved;
  end;
end.
