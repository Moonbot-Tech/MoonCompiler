program rest;

{ Оставшиеся расхождения с Delphi, найденные слоем `resident`: разбор пустой
  строки по разделителю, метка порядка байт при сохранении списка строк и род
  логического типа в сведениях о типах. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
{$endif}
{$APPTYPE CONSOLE}
{$Q-}{$R-}

uses
{$ifdef FPC}
  mormot.core.fpcx64mm,
{$endif}
  SysUtils, Classes, TypInfo;

procedure SplitCases;
var
  Parts: TArray<string>;
  Source: string;
  I: Integer;
begin
  WriteLn('--- split');
  Source := '';
  Parts := Source.Split([',']);
  WriteLn('empty string   -> count=', Length(Parts));
  for I := 0 to High(Parts) do
    WriteLn('   part[', I, '] = [', Parts[I], ']');

  Source := ',';
  Parts := Source.Split([',']);
  WriteLn('single comma   -> count=', Length(Parts));

  Source := 'a';
  Parts := Source.Split([',']);
  WriteLn('no separator   -> count=', Length(Parts));

  Source := 'a,,b';
  Parts := Source.Split([',']);
  WriteLn('empty in middle-> count=', Length(Parts));

  Source := ',a';
  Parts := Source.Split([',']);
  WriteLn('leading sep    -> count=', Length(Parts));

  Source := 'a,';
  Parts := Source.Split([',']);
  WriteLn('trailing sep   -> count=', Length(Parts));

  Source := '';
  Parts := Source.Split([','], TStringSplitOptions.ExcludeEmpty);
  WriteLn('empty, exclude -> count=', Length(Parts));
end;

procedure BomCase;
var
  List: TStringList;
  Stream: TMemoryStream;
  Head: array[0 .. 3] of Byte;
  I: Integer;
  Line: string;
begin
  WriteLn('--- save with UTF8');
  List := TStringList.Create;
  Stream := TMemoryStream.Create;
  try
    List.Add('ab');
    List.SaveToStream(Stream, TEncoding.UTF8);
    WriteLn('size = ', Stream.Size);
    Stream.Position := 0;
    FillChar(Head, SizeOf(Head), 0);
    Stream.Read(Head, 4);
    Line := '';
    for I := 0 to 3 do
      Line := Line + IntToHex(Head[I], 2) + ' ';
    WriteLn('first bytes = ', Line);
    WriteLn('has BOM = ', (Head[0] = $EF) and (Head[1] = $BB) and (Head[2] = $BF));
  finally
    List.Free;
    Stream.Free;
  end;
end;

procedure BoolKind;
var
  Info: PTypeInfo;
begin
  WriteLn('--- kind of Boolean');
  Info := TypeInfo(Boolean);
  WriteLn('Ord(Kind) = ', Ord(Info^.Kind));
  WriteLn('is tkEnumeration = ', Info^.Kind = tkEnumeration);
{$ifdef FPC}
  WriteLn('is tkBool        = ', Info^.Kind = tkBool);
{$endif}
  WriteLn('name = ', string(Info^.Name));
  WriteLn('ByteBool  kind = ', Ord(PTypeInfo(TypeInfo(ByteBool))^.Kind));
  WriteLn('LongBool  kind = ', Ord(PTypeInfo(TypeInfo(LongBool))^.Kind));
end;

begin
  SplitCases;
  BomCase;
  BoolKind;
  WriteLn('done');
end.
