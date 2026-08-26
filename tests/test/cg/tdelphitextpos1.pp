program tdelphitextpos1;

{$ifdef FPC}
  {$mode delphiunicode}
{$endif}

uses
  SysUtils;

procedure Check(Condition: Boolean; ErrorCode: Byte);
begin
  if not Condition then
    Halt(ErrorCode);
end;

var
  AText,
  ANeedle: AnsiString;
  WText,
  WNeedle: UnicodeString;
  AnsiMatch: PAnsiChar;
  WideMatch: PWideChar;
begin
  AText:='abCDef';
  ANeedle:='cd';
  AnsiMatch:=TextPos(PAnsiChar(AText),PAnsiChar(ANeedle));
  Check((AnsiMatch<>nil) and ((AnsiMatch-PAnsiChar(AText))=2),1);
  Check(TextPos(PAnsiChar(AText),PAnsiChar('xy'))=nil,2);

  WText:='abCDef';
  WNeedle:='cd';
  WideMatch:=TextPos(PWideChar(WText),PWideChar(WNeedle));
  Check((WideMatch<>nil) and ((WideMatch-PWideChar(WText))=2),3);
  Check(TextPos(PWideChar(WText),PWideChar('xy'))=nil,4);
end.
