{$ifdef BREADTH_HAS_PRODUCT_IO}
{ Emit a typed JSON packet and independently consume fields after a nested skipped value. }

procedure RunBreadthJsonTokenWriter;
const
  Expected = '{"requests":[9007199254740993,"A\u0000\u00E9",null]}';
var
  Text: TStringWriter;
  Writer: TJsonTextWriter;
  Wire: string;
begin
  Text := TStringWriter.Create;
  try
    Writer := TJsonTextWriter.Create(Text);
    try
      Writer.CloseOutput := False;
      Writer.StringEscapeHandling := TJsonStringEscapeHandling.EscapeNonAscii;
      Writer.WriteStartObject;
      Writer.WritePropertyName('requests');
      Writer.WriteStartArray;
      Writer.WriteValue(OpaqueI(9007199254740993));
      Writer.WriteValue('A' + #0 + #$00E9);
      Writer.WriteNull;
      Writer.WriteEndArray;
      Writer.WriteEndObject;
    finally
      FreeAndNil(Writer);
    end;
    Wire := Text.ToString;
    Check(Wire = Expected,
      'breadth-json-token-writer-emits-wide-integer-escaped-unicode-and-null');
    Mix(UInt64(Length(Wire)));
  finally
    FreeAndNil(Text);
  end;
end;

procedure RunBreadthJsonTokenReader;
const
  Input = '{"ignored":{"a":[1,{"x":"discard"}]},"ticket":-9007199254740989,"note":"A\u0000\u03bb\ud83d\ude80"}';
var
  Reader: TJsonTextReader;
  Ticket: Int64;
begin
  Reader := TJsonTextReader.Create(TStringReader.Create(Input));
  try
    Check(Reader.Read and (Reader.TokenType = TJsonToken.StartObject) and Reader.Read
      and (Reader.TokenType = TJsonToken.PropertyName) and (Reader.Value.AsString = 'ignored'),
      'breadth-json-token-reader-reaches-ignored-property');
    Reader.Skip;
    Check(Reader.Read and (Reader.TokenType = TJsonToken.PropertyName) and (Reader.Value.AsString = 'ticket'),
      'breadth-json-token-reader-skip-resumes-at-next-property');
    Ticket := Reader.ReadAsInt64;
    Check(Ticket = -9007199254740989, 'breadth-json-token-reader-typed-read-retains-wide-negative-integer');
    Check(Reader.Read and (Reader.Value.AsString = 'note') and
      (Reader.ReadAsString = 'A' + #0 + #$03BB + #$D83D + #$DE80) and Reader.Read and
      (Reader.TokenType = TJsonToken.EndObject) and not Reader.Read, 'breadth-json-token-reader-keeps-unicode-and-consumes-packet');
    Mix(UInt64(Ticket));
  finally
    FreeAndNil(Reader);
  end;
end;
{$endif}
