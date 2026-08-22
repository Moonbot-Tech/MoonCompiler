program char_literal_ansi_semantic;

{ dvl-0029 (non-ASCII part): with a UTF-8 source file under the Delphi
  Unicode ABI, DCC64 36.0 types a quoted non-ASCII character literal
  through the system ANSI codepage: a representable character becomes
  AnsiChar carrying the ANSI byte (Ord('я') = 255 under CP1251), a
  non-representable one stays Char.  #-escapes keep the width their
  written form selects (#$FF is a byte, #$044F and #1103 are wide), and
  widening a byte literal back decodes through the same codepage, so the
  character survives.  The whole matrix depends on the build machine's
  ANSI codepage, exactly like DCC; the pin runs its checks only under
  CP1251 and otherwise just prints the success marker. }

{$APPTYPE CONSOLE}

{$ifdef FPC}
{$mode delphi}{$H+}
{$endif FPC}

uses
  {$ifdef FPC}
  mormot.core.fpcx64mm,
  {$else FPC}
  Winapi.Windows,
  {$endif FPC}
  SysUtils;

function Pick(const V: AnsiChar): string; overload;
begin
  Result := 'ansi:' + IntToStr(Ord(V));
end;

function Pick(const V: Char): string; overload;
begin
  Result := 'wide:' + IntToStr(Ord(V));
end;

function Pick(const V: string): string; overload;
begin
  Result := 'str:' + IntToStr(Length(V));
end;

procedure Check(const Name, Got, Expected: string);
begin
  If Got <> Expected then
    raise Exception.CreateFmt('%s: %s expected %s', [Name, Got, Expected]);
end;

procedure RunMatrix;
var
  AC: AnsiChar;
  WC: Char;
  S: string;
  AS8: AnsiString;
begin
  { quoted non-ASCII: representable in CP1251 -> AnsiChar with ANSI byte }
  Check('quoted ya', Pick('я'), 'ansi:255');
  Check('quoted yo', Pick('ё'), 'ansi:184');
  Check('quoted euro', Pick('€'), 'ansi:136');
  { not representable -> stays wide }
  Check('quoted cjk', Pick('中'), 'wide:20013');
  Check('quoted yuml', Pick('ÿ'), 'wide:255');
  { escapes select width by their written form }
  Check('esc $044F', Pick(#$044F), 'wide:1103');
  Check('esc 1103', Pick(#1103), 'wide:1103');
  Check('esc $FF', Pick(#$FF), 'ansi:255');
  Check('chr 1103', Pick(Chr(1103)), 'wide:1103');
  { two characters make a string }
  Check('concat', Pick('яя'), 'str:2');

  { widening decodes through the codepage - the character survives }
  AC := 'я';
  Check('ansichar var', IntToStr(Ord(AC)), '255');
  WC := 'я';
  Check('widechar var', IntToStr(Ord(WC)), '1103');
  S := 'я';
  Check('string var', IntToStr(Ord(S[1])), '1103');
  AS8 := 'я';
  Check('ansistring var', IntToStr(Ord(AS8[1])), '255');
  Check('ord quoted', IntToStr(Ord('я')), '255');
  Check('ord cjk', IntToStr(Ord('中')), '20013');
end;

function AnsiCodePage: Cardinal;
begin
  {$ifdef FPC}
  Result := DefaultSystemCodePage;
  {$else}
  Result := GetACP;
  {$endif}
end;

begin
  try
    If AnsiCodePage = 1251 then
      RunMatrix;
    WriteLn('CHAR_LITERAL_ANSI_OK');
  except
    on E: Exception do begin
      WriteLn('CHAR_LITERAL_ANSI_FAIL ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
