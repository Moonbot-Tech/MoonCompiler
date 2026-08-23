program delphi_char_cast_semantic;

{$ifdef FPC}
  {$mode delphiunicode}
{$endif}

uses
  {$ifdef FPC}
  mormot.core.fpcx64mm,
  {$ifdef UNIX}cthreads,cwstring,{$endif UNIX}
  {$endif}
  SysUtils;

procedure Fail(const Name: string);
begin
  WriteLn('FAIL: ',Name);
  Halt(1);
end;

var
  A: AnsiChar;
  W: WideChar;
  U: UnicodeString;
begin
  A:=AnsiChar(#233);
  W:=WideChar(A);
  If Ord(W)<>233 then
    Fail('runtime ansi-to-wide explicit');

  W:=WideChar(1081);
  A:=AnsiChar(W);
  If Ord(A)<>57 then
    Fail('runtime wide-to-ansi explicit');

  U:=Format('%s',[AnsiChar(#233)]);
  If (Length(U)<>1) or (Ord(U[1])<>233) then
    Fail('format vtChar ordinal');

  If DefaultSystemCodePage=1251 then begin
    If Ord(WideChar(AnsiChar(#233)))<>1081 then
      Fail('constant ansi-to-wide codepage');
    If Ord(AnsiChar(WideChar(#1081)))<>233 then
      Fail('constant wide-to-ansi codepage');
    U:=AnsiChar(#233);
    If (Length(U)<>1) or (Ord(U[1])<>1081) then
      Fail('implicit ansi-to-unicode codepage');
  end;

  WriteLn('DELPHI_CHAR_CAST_OK');
end.
