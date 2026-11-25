{ Read legacy exported options as typed tokens across multiple lines. }

procedure RunBreadthConfigTokens;
const
  Wire: AnsiString = 'Orders = -9007199254740993' + #13#10
    + 'Note = ''alpha''''beta''#0#955'' tail''' + #13#10 + 'Limit = 0.125';
var
  Stream: TMemoryStream;
  Parser: TParser;
begin
  Stream := TMemoryStream.Create;
  try
    Stream.WriteBuffer(PAnsiChar(Wire)^, Length(Wire));
    Stream.Position := 0;
    Parser := TParser.Create(Stream);
    try
      Check(Parser.TokenSymbolIs('orders') and (Parser.NextToken = '=') and (Parser.NextToken = toInteger)
        and (Parser.TokenInt = -9007199254740993), 'breadth-config-tokens-keep-negative-wide-ordinal');
      Parser.NextToken;
      Check(Parser.TokenSymbolIs('note') and (Parser.SourceLine = 2) and (Parser.NextToken = '=')
        and (Parser.NextToken = toWString) and (UnicodeString(Parser.TokenWideString) = 'alpha''beta' + #0 + #$03BB + ' tail'),
        'breadth-config-tokens-combine-quoted-text-escaped-apostrophe-nul-and-unicode');
      Parser.NextToken;
      Check(Parser.TokenSymbolIs('limit') and (Parser.SourceLine = 3) and (Parser.NextToken = '=')
        and (Parser.NextToken = toFloat) and (Parser.TokenFloat = 0.125),
        'breadth-config-tokens-read-invariant-decimal-on-next-line');
      Check(Parser.NextToken = toEOF, 'breadth-config-tokens-end-at-last-complete-value');
      Mix(UInt64(Parser.SourceLine));
    finally
      Parser.Free;
    end;
  finally
    Stream.Free;
  end;
end;
