{
    This file is part of the Free Component Library (FCL)
    Copyright (c) 1999-2000 by Michael Van Canneyt and Florian Klaempfl

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

    Extracted from classes.inc and adapted for ANSI/Unicode inputs by
    MoonCompiler contributors, 2026. Counts are in input characters;
    SetString owns encoding conversion.
}
function ExtractStrings(Separators, WhiteSpace: TSysCharSet; Content: EXTRACTPOINTER; Strings: TStrings; AddEmptyStrings : Boolean = False): Integer;
var
  b, c : EXTRACTPOINTER;

  procedure SkipWhitespace;
    begin
      while (c^ <> #0) and (Ord(c^) <= 255) and (AnsiChar(c^) in Whitespace) do
        inc (c);
    end;

  procedure AddString;
    var
      l : integer;
      s : EXTRACTSTRING;
    begin
      l := c-b;
      if (l > 0) or AddEmptyStrings then
        begin
          if assigned(Strings) then
            begin
              SetString(s, b, l);
              Strings.Add (string(s));
            end;
          inc (result);
        end;
    end;

var
  quoted : EXTRACTCHAR;
begin
  result := 0;
  if Content = nil then
    Exit;
{$ifdef EXTRACTWIDE}
  if Strings = nil then
    Exit;
{$endif}
  c := Content;
  Quoted := #0;
  Separators := Separators + [#13, #10] - ['''','"'];
  SkipWhitespace;
  b := c;
  while (c^ <> #0) do
    begin
      if (c^ = Quoted) then
        begin
          if ((c+1)^ = Quoted) then
            inc (c)
          else
            Quoted := #0
        end
      else if (Quoted = #0) and ((c^ = '''') or (c^ = '"')) then
        Quoted := c^;
      if (Quoted = #0) and (Ord(c^) <= 255) and (AnsiChar(c^) in Separators) then
        begin
          AddString;
          inc (c);
          SkipWhitespace;
          b := c;
        end
      else
        inc (c);
    end;
  if (c <> b) then
    AddString;
end;
