program qualified;

{ Приведение к типу, записанному с квалификацией пространства имён, против того
  же приведения без неё. Имя одно и то же, значение обязано быть одно и то же. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
{$endif}
{$APPTYPE CONSOLE}
{$Q-}{$R-}

uses
{$ifdef FPC}
  mormot.core.fpcx64mm,
{$endif}
  SysUtils;

procedure Pair(const Name: string; Bare, Qualified: Int64);
begin
  if Bare = Qualified then
    WriteLn(Name, ': bare=', Bare, ' qualified=', Qualified, '  same')
  else
    WriteLn(Name, ': bare=', Bare, ' qualified=', Qualified, '  <-- DIFFER');
end;

var
  W: Word;
  B: Byte;
  C: Cardinal;
  S: SmallInt;
  Bare, Qual: Integer;
begin
  W := 65535;
  Pair('Integer(Word 65535)   ', Integer(W), System.Integer(W));
  Pair('Int64(Word 65535)     ', Int64(W), System.Int64(W));
  Pair('Cardinal(Word 65535)  ', Cardinal(W), System.Cardinal(W));
  Pair('NativeInt(Word 65535) ', NativeInt(W), System.NativeInt(W));

  W := 32768;
  Pair('Integer(Word 32768)   ', Integer(W), System.Integer(W));
  W := 32767;
  Pair('Integer(Word 32767)   ', Integer(W), System.Integer(W));

  B := 255;
  Pair('Integer(Byte 255)     ', Integer(B), System.Integer(B));
  Pair('Int64(Byte 255)       ', Int64(B), System.Int64(B));

  C := $FFFFFFFF;
  Pair('Int64(Cardinal max)   ', Int64(C), System.Int64(C));

  S := -1;
  Pair('Integer(SmallInt -1)  ', Integer(S), System.Integer(S));
  Pair('Word(SmallInt -1)     ', Int64(Word(S)), Int64(System.Word(S)));

  { То же самое, но значение приходит через переменную-посредника: не меняет ли
    дело промежуточное присваивание. }
  W := 65535;
  Bare := Integer(W);
  Qual := System.Integer(W);
  Pair('via variables         ', Bare, Qual);

  { И в выражении, а не в присваивании. }
  Pair('in expression         ', Integer(W) + 0, System.Integer(W) + 0);
  Pair('as argument           ', Int64(Integer(W)), Int64(System.Integer(W)));
  WriteLn('done');
end.
