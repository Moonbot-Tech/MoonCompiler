program iconv_unicode_semantic;

{ %TARGET=linux }

{$mode delphiunicode}{$H+}

uses
  mormot.core.fpcx64mm,
{$ifdef linux}
  cthreads,
  iconvenc_dyn,
{$endif}
  SysUtils;

procedure Check(Condition: Boolean; const MessageText: string);
begin
  if not Condition then
    begin
      WriteLn('FAIL ', MessageText);
      Halt(1);
    end;
end;

{$ifdef linux}
procedure CheckIconv;
var
  ErrorText, Input, Output: AnsiString;
begin
  ErrorText := '';
  Check(InitIconv(ErrorText), 'load iconv: ' + string(ErrorText));
  Input := 'Moon-' + AnsiChar($D0) + AnsiChar($9B) +
    AnsiChar($D1) + AnsiChar($83) + AnsiChar($D0) + AnsiChar($BD) +
    AnsiChar($D0) + AnsiChar($B0);
  Output := '';
  Check(Iconvert(Input, Output, 'UTF-8', 'UTF-8') = 0,
    'UTF-8 identity conversion status');
  Check(Output = Input, 'UTF-8 identity conversion payload');
end;
{$endif}

begin
{$ifdef linux}
  CheckIconv;
{$endif}
  WriteLn('ICONV_UNICODE_OK');
end.
