{ %OPT=-O3 -gt }
program tstrengthresultcountertrace1;

{$mode objfpc}

function CharPos(const S: AnsiString; C: AnsiChar; Index: SizeInt): SizeInt;
begin
  for Result := Index to Length(S) do
    if S[Result] = C then
      Exit;
  Result := 0;
end;

begin
  if CharPos('Hello!', '!', 1) <> 6 then
    Halt(1);
  if CharPos('Hello!', 'H', 1) <> 1 then
    Halt(2);
  if CharPos('Hello!', '?', 1) <> 0 then
    Halt(3);
end.
