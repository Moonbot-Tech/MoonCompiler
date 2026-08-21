program guid2;
{$ifdef FPC}{$mode delphiunicode}{$H+}{$endif}
{$APPTYPE CONSOLE}
uses {$ifdef FPC}mormot.core.fpcx64mm,{$endif} SysUtils;

{ Повторение разбора из RTL двумя указателями: тем, что стоит там сейчас
  (PChar, в этом режиме двухбайтовый), и байтовым, которым он обязан быть.
  ShortString хранит по одному байту на символ, поэтому шаг указателя решает
  всё. }

const
  Scatter: array[0 .. 15] of Integer =
    (8, 6, 4, 2, 13, 11, 18, 16, 21, 23, 26, 28, 30, 32, 34, 36);

function Digit(C: Char; var Ok: Boolean): Byte;
begin
  Result := 0;
  case C of
    '0' .. '9': Result := Byte(C) - Byte('0');
    'a' .. 'f': Result := Byte(C) - Byte('a') + 10;
    'A' .. 'F': Result := Byte(C) - Byte('A') + 10;
  else
    Ok := False;
  end;
end;

function DigitA(C: AnsiChar; var Ok: Boolean): Byte;
begin
  Result := 0;
  case C of
    '0' .. '9': Result := Byte(C) - Byte('0');
    'a' .. 'f': Result := Byte(C) - Byte('a') + 10;
    'A' .. 'F': Result := Byte(C) - Byte('A') + 10;
  else
    Ok := False;
  end;
end;

var
  S: ShortString;
  G: TGUID;
  I: Integer;
  Ok: Boolean;
  Wide: PChar;
  Narrow: PAnsiChar;
  Line: string;
begin
  S := '{4D5A0001-0000-0000-0000-0000524553FF}';
  WriteLn('SizeOf(Char)      = ', SizeOf(Char));
  WriteLn('SizeOf(S[1])      = ', SizeOf(S[1]));
  WriteLn('Length(S)         = ', Length(S));
  WriteLn('S[1]=', S[1], ' S[10]=', S[10], ' S[38]=', S[38]);
  WriteLn;

  { Как в RTL сейчас: шаг PChar вдвое больше, чем шаг символа ShortString. }
  Ok := True;
  Line := '';
  for I := 0 to High(Scatter) do
  begin
    Wide := PChar(Pointer(@S[1])) + Scatter[I] - 1;
    Line := Line + IntToHex(Digit(Wide[0], Ok) shl 4 + Digit(Wide[1], Ok), 2);
  end;
  WriteLn('via PChar   ok=', Ok, ' bytes=', Line);

  { Как должно быть: байтовый указатель по байтовой строке. }
  Ok := True;
  Line := '';
  for I := 0 to High(Scatter) do
  begin
    Narrow := PAnsiChar(Pointer(@S[1])) + Scatter[I] - 1;
    Line := Line + IntToHex(DigitA(Narrow[0], Ok) shl 4 + DigitA(Narrow[1], Ok), 2);
  end;
  WriteLn('via PAnsiChar ok=', Ok, ' bytes=', Line);
  WriteLn;

  { Обратная сторона договора: сборка строки из готового значения. }
  G := TGUID.Empty;
  G.D1 := $4D5A0001;
  WriteLn('GUIDToString(D1=4D5A0001) = ', GUIDToString(G));
  WriteLn('done');
end.
