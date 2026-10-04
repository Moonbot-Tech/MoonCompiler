program masks_oracle;

{ System.Masks differential oracle: the same program compiled by Delphi 12.2
  and by MoonCompiler prints, for every mask of up to three atoms over a small
  alphabet and every text of up to four characters, whether the mask matches
  or which position the mask is rejected at.  The two outputs are compared
  line by line; the exception text differs by design (only the position is
  printed).  Masks longer than the enumeration and non-ASCII cases follow. }

{$ifndef FPC}
  {$APPTYPE CONSOLE}
{$endif}
{$ifdef FPC}
  {$mode delphi}{$H+}
{$endif}

uses
  SysUtils,
  System.Masks;

const
  Atoms: array[0..9] of string = ('a', 'b', 'A', '*', '?', '[ab]', '[!a]', '[a-c]', '[!b-c]', '[^a]');
  Letters: array[0..3] of Char = ('a', 'b', 'c', 'A');
  Special: array[0..13] of string = ('[a-]', '[a-z-9]', '[-a]', '[]', '[', 'a[', '[abc', '[a-', '[!]', '[!-a]',
    '[z-a]', '[a-a]', '**a', 'a**');

function LastNumber(const S: string): Integer;
var
  I, J: Integer;
begin
  { the position is the last run of digits in the message }
  I := Length(S);
  while (I > 0) and not CharInSet(S[I], ['0'..'9']) do
    Dec(I);
  J := I;
  while (J > 0) and CharInSet(S[J], ['0'..'9']) do
    Dec(J);
  if I = 0 then
    Result := -1
  else
    Result := StrToInt(Copy(S, J + 1, I - J));
end;

var
  Texts: array of string;

{ the console pipe is not a reliable channel for non-ASCII: escape it }
function Escape(const S: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do
    if (Ord(S[I]) >= 32) and (Ord(S[I]) < 127) then
      Result := Result + S[I]
    else
      Result := Result + '#' + IntToHex(Ord(S[I]), 4);
end;

procedure Probe(const Mask: string);
var
  M: TMask;
  T: Integer;
  Line: string;
begin
  try
    M := TMask.Create(Mask);
  except
    on E: EMaskException do
    begin
      WriteLn(Escape(Mask), ' ERR ', LastNumber(E.Message));
      Exit;
    end;
  end;
  try
    Line := '';
    for T := 0 to High(Texts) do
      if M.Matches(Texts[T]) then
        Line := Line + '1'
      else
        Line := Line + '0';
    WriteLn(Escape(Mask), ' ', Line);
  finally
    M.Free;
  end;
end;

procedure BuildTexts;
var
  L, I, K, N, P: Integer;
  S: string;
begin
  N := 0;
  for L := 0 to 4 do
  begin
    K := 1;
    for I := 1 to L do
      K := K * Length(Letters);
    for I := 0 to K - 1 do
    begin
      S := '';
      K := I;
      { mixed radix over the letters }
      SetLength(S, L);
      for P := 1 to L do
      begin
        S[P] := Letters[K mod Length(Letters)];
        K := K div Length(Letters);
      end;
      SetLength(Texts, N + 1);
      Texts[N] := S;
      Inc(N);
    end;
  end;
  { non-ASCII: Cyrillic in both cases, a surrogate pair, a NUL }
  SetLength(Texts, N + 6);
  Texts[N] := #$0430; Texts[N + 1] := #$0410; Texts[N + 2] := #$D83D#$DE00;
  Texts[N + 3] := 'a' + #$D83D#$DE00; Texts[N + 4] := 'a'#0'b'; Texts[N + 5] := #0;
end;

var
  I, J, K, T: Integer;
  Stars: string;
begin
  BuildTexts;
  Write('texts');
  for T := 0 to High(Texts) do
    Write(' ', Length(Texts[T]));
  WriteLn;
  Probe('');
  for I := 0 to High(Atoms) do
  begin
    Probe(Atoms[I]);
    for J := 0 to High(Atoms) do
    begin
      Probe(Atoms[I] + Atoms[J]);
      for K := 0 to High(Atoms) do
        Probe(Atoms[I] + Atoms[J] + Atoms[K]);
    end;
  end;
  for I := 0 to High(Special) do
    Probe(Special[I]);
  { non-ASCII masks }
  Probe(#$0430); Probe(#$0410); Probe('[' + #$0430 + ']'); Probe('[' + #$0430#$0431 + ']');
  Probe(#$D83D#$DE00); Probe(#$D83D#$DE00 + '?'); Probe('[' + #$D83D#$DE00 + 'a]'); Probe('*' + #$DE00);
  Probe('a'#0'b'); Probe(#0);
  { the wildcard limit: runs of stars and alternations }
  Stars := '';
  for I := 1 to 31 do
    Stars := Stars + '*';
  Probe(Stars);
  Stars := '';
  for I := 1 to 30 do
    Stars := Stars + 'a*';
  Probe(Stars);
  Probe(Stars + '*');
  Probe(Stars + 'a');
  Probe(Stars + '?');
  Probe('*' + Stars);
  Probe(StringOfChar('?', 40));
  WriteLn('MASKS_ORACLE_END');
end.
