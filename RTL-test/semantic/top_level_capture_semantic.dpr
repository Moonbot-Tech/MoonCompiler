program top_level_capture_semantic;
{$IFDEF FPC}{$mode delphi}{$ENDIF}
uses semtrack, semcapture;
begin
  Writeln('INIT ', ReadInit());
  If ReadInit() <> 'init-live:Z' then Halt(81);
  ReadInit := nil;
  Writeln('INIT_RELEASE ', Destroyed);
  begin
    var S: UnicodeString := 'main';
    var Token: IToken := TToken.Create;
    ReadMain := function: UnicodeString
      begin
        If Token = nil then Exit('nil');
        Result := S + ':' + Chr(Token.Value + 48);
      end;
    S := S + '-live';
  end;
  Writeln('MAIN ', ReadMain());
  If ReadMain() <> 'main-live:Z' then Halt(82);
  ReadMain := nil;
  Writeln('MAIN_RELEASE ', Destroyed);
  WriteLn('TOP_LEVEL_CAPTURE_PASS');
end.
