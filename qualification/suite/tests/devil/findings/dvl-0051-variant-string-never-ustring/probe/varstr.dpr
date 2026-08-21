program varstr;

{ Строка, положенная в Variant: каким типом она там оказывается и переживает ли
  перегон содержимое за пределами ASCII.

  Символы задаются кодами, а не буквами в исходнике: иначе проверялась бы
  кодировка файла, а не работа варианта. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch INLINEVARS}
{$endif}
{$APPTYPE CONSOLE}
{$Q-}{$R-}

uses
{$ifdef FPC}
  mormot.core.fpcx64mm,
{$endif}
  SysUtils, Variants;

procedure Codes(const Name: string; const S: string);
var
  I: Integer;
  Line: string;
begin
  Line := '';
  for I := 1 to Length(S) do
    Line := Line + IntToHex(Word(S[I]), 4) + ' ';
  WriteLn(Name, ': len=', Length(S), ' codes=', Line);
end;

var
  Box: Variant;
  Source, Back: string;
begin
  { Строка из символов вне ASCII: кириллическая А (0410), знак евро (20AC),
    и звёздочка из старших планов не берётся нарочно — суррогаты отдельная
    тема, здесь проверяется базовая плоскость. }
  Source := WideChar($0410) + WideChar($20AC) + WideChar($0041);
  Codes('source        ', Source);

  Box := Source;
  WriteLn('vartype       : ', VarType(Box),
          '   (varString=', varString, ' varUString=', varUString,
          ' varOleStr=', varOleStr, ')');

  Back := Box;
  Codes('back          ', Back);
  WriteLn('roundtrip ok  : ', Back = Source);

  { То же самое, но через явный тип варианта. }
  Box := VarAsType(Source, varOleStr);
  WriteLn('as varOleStr  : ', VarType(Box));
  Back := Box;
  Codes('back from OleStr', Back);
  WriteLn('roundtrip ok  : ', Back = Source);

  { Чистый ASCII для сравнения. }
  Source := 'abc';
  Box := Source;
  Back := Box;
  WriteLn('ascii vartype : ', VarType(Box), '  roundtrip ok: ', Back = Source);

  { Литерал против переменной: литерал с кодами вне ASCII записан escape-ами,
    поэтому кодировка файла тут ни при чём. }
  Box := #$0410#$20AC#$0041;
  WriteLn('literal vartype: ', VarType(Box));
  Back := Box;
  Codes('literal back  ', Back);
  WriteLn('literal ok    : ', Back = (WideChar($0410) + WideChar($20AC) + WideChar($0041)));

  Box := 'abc';
  WriteLn('ascii literal vartype: ', VarType(Box));

  { Явно широкая и явно байтовая строки. }
  var U: UnicodeString := #$0410#$20AC;
  Box := U;
  WriteLn('unicodestring vartype: ', VarType(Box));
  var Wd: WideString := #$0410#$20AC;
  Box := Wd;
  WriteLn('widestring vartype   : ', VarType(Box));

  { Сравнение вариантов между собой. }
  Box := WideChar($0410) + WideChar($0411);
  WriteLn('compare equal : ', Box = (WideChar($0410) + WideChar($0411)));
  WriteLn('done');
end.
