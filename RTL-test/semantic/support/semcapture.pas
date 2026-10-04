unit semcapture;
{$IFDEF FPC}{$mode delphi}{$ENDIF}
interface
uses semtrack;
type TRead = reference to function: UnicodeString;
var ReadInit, ReadMain: TRead;
implementation
initialization
  begin
    var S: UnicodeString := 'init';
    var Token: IToken := TToken.Create;
    ReadInit := function: UnicodeString
      begin
        If Token = nil then Exit('nil');
        Result := S + ':' + Chr(Token.Value + 48);
      end;
    S := S + '-live';
  end;
finalization
  ReadMain := nil;
  ReadInit := nil;
end.
