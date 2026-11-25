program json_writer_escape_semantic;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.Classes, System.JSON.Writers, System.JSON.Types;

function Render(const S: string; Mode: TJsonStringEscapeHandling): string;
var
  Text: TStringWriter;
  Writer: TJsonTextWriter;
begin
  Text := TStringWriter.Create;
  try
    Writer := TJsonTextWriter.Create(Text);
    try
      Writer.CloseOutput := False;
      Writer.StringEscapeHandling := Mode;
      Writer.WriteStartObject;
      Writer.WritePropertyName(S);
      Writer.WriteValue(S);
      Writer.WriteEndObject;
    finally
      Writer.Free;
    end;
    Result := Text.ToString;
  finally
    Text.Free;
  end;
end;

var
  S, Encoded, Wire: string;
begin
  S := 'A' + #0 + #$00FF + #$0100 + #$03BB + #$D83D + #$DE80 + #$FFFF;
  Encoded := 'A\u0000\u00FF\u0100\u03BB\uD83D\uDE80\uFFFF';
  Wire := Render(S, TJsonStringEscapeHandling.EscapeNonAscii);
  if LowerCase(Wire) <> LowerCase('{"' + Encoded + '":"' + Encoded + '"}') then Halt(1);
  if Pos(#$03BB + #$D83D + #$DE80, Render(S, TJsonStringEscapeHandling.Default)) = 0 then Halt(2);
  if Render('json', TJsonStringEscapeHandling.EscapeNonAscii) <> '{"json":"json"}' then Halt(3);
  WriteLn('JSON_WRITER_ESCAPE_OK');
end.
