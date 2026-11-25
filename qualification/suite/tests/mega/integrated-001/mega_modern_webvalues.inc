{$ifdef BREADTH_HAS_PRODUCT_IO}
{ Binary values and text fields retain their data through different wire encodings. }

procedure RunBreadthBase64Window;
const
  FramePrefix: Byte = $19;
  TripleCount = 257;
  EncodedTriple: array[0..3] of AnsiChar = ('Q', 'U', 'J', 'D');
var
  Body: array[0..TripleCount * 3 + 1] of Byte;
  Expected: AnsiString;
  Data, Wire, Received: TMemoryStream;
  I, Count: Integer;
begin
  for I := 0 to TripleCount - 1 do begin
    Body[I * 3] := $41;
    Body[I * 3 + 1] := $42;
    Body[I * 3 + 2] := $43;
  end;
  Body[High(Body) - 1] := $FB;
  Body[High(Body)] := $FF;
  Expected := AnsiString(StringOfChar(' ', TripleCount * 4)) + '+/8=';
  for I := 0 to TripleCount - 1 do
    Move(EncodedTriple, Expected[I * 4 + 1], SizeOf(EncodedTriple));

  Data := TMemoryStream.Create;
  Wire := nil;
  Received := nil;
  try
    Wire := TMemoryStream.Create;
    Received := TMemoryStream.Create;
    Data.WriteBuffer(FramePrefix, 1);
    Data.WriteBuffer(Body, SizeOf(Body));
    Data.Position := 1;
    Wire.WriteBuffer(FramePrefix, 1);
    Count := TNetEncoding.Base64String.Encode(Data, Wire);
    Check((Count = Length(Expected)) and (Data.Position = Data.Size) and (Wire.Position = Length(Expected) + 1),
      'breadth-base64-encode-consumes-current-window-and-reports-output-count');
    Check((Wire.Size > 0) and (PByte(Wire.Memory)^ = FramePrefix),
      'breadth-base64-encode-preserves-existing-output-prefix');
    Check((Wire.Size = Length(Expected) + 1) and CompareMem(PByte(Wire.Memory) + 1, PAnsiChar(Expected), Length(Expected)),
      'breadth-base64-stream-crosses-buffer-and-flushes-two-byte-tail');

    Wire.Position := 1;
    Received.WriteBuffer(FramePrefix, 1);
    Count := TNetEncoding.Base64String.Decode(Wire, Received);
    Check((Count = SizeOf(Body)) and (Received.Position = SizeOf(Body) + 1) and (PByte(Received.Memory)^ = FramePrefix),
      'breadth-base64-decode-appends-and-reports-only-decoded-bytes');
    Check((Received.Size = SizeOf(Body) + 1) and CompareMem(PByte(Received.Memory) + 1, @Body[0], SizeOf(Body)),
      'breadth-base64-stream-decodes-exact-binary-body');
    Mix(UInt64(Received.Size));
  finally
    Received.Free;
    Wire.Free;
    Data.Free;
  end;
end;

procedure RunBreadthBase64Alphabet;
const
  Data: array[0..6] of Byte = ($81, $FB, $FF, $00, $3F, $C3, $31);
var
  Start: Integer;
  Encoded: UnicodeString;
  Decoded: TBytes;
begin
  Start := Integer(OpaqueI(1));
  Check(TNetEncoding.Base64String.EncodeBytesToString(@Data[Start], 5) = '+/8AP8M=',
    'breadth-base64-pointer-window-keeps-binary-values-and-standard-padding');
  Encoded := TNetEncoding.Base64URL.EncodeBytesToString(@Data[Start], 5);
  Check(Encoded = '-_8AP8M', 'breadth-base64-url-uses-distinct-alphabet-and-omits-padding');
  Decoded := TNetEncoding.Base64URL.DecodeStringToBytes(UnicodeString('-_8AP8M'));
  Check((Length(Decoded) = 5) and CompareMem(@Decoded[0], @Data[Start], 5),
    'breadth-base64-url-decoder-keeps-nul-and-high-bytes-without-padding');
end;

procedure RunBreadthWebText;
const
  FormWire: UnicodeString = 'lambda+%CE%BB+%2B+%F0%9F%9A%80+%26';
var
  Field: UnicodeString;
begin
  Field := 'lambda ' + #$03BB + ' + ' + #$D83D + #$DE80 + ' &';
  Check(TNetEncoding.URL.EncodeForm(Field, [], TEncoding.UTF8) = FormWire,
    'breadth-form-url-encodes-utf8-and-distinguishes-space-from-literal-plus');
  Check(TNetEncoding.URL.FormDecode(FormWire, TEncoding.UTF8) = Field,
    'breadth-form-url-recovers-surrogate-pair-literal-plus-and-field-separator');
  Check(TNetEncoding.HTML.Encode(UnicodeString('<"') + #$03BB + '&>') = '&lt;&quot;' + #$03BB + '&amp;&gt;',
    'breadth-html-encodes-delimiters-and-keeps-visible-unicode');
  Check(TNetEncoding.HTML.Decode(UnicodeString('&amp;lt;&#955;&#x20AC;')) = '&lt;' + #$03BB + #$20AC,
    'breadth-html-decoder-resolves-numeric-text-and-does-not-decode-twice');
end;
{$endif}
