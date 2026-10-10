program reader_value_transfer_semantic;
{$APPTYPE CONSOLE}
uses Classes, SysUtils, Variants;

type
  TFragmentedStream = class(TMemoryStream)
    function Read(var Buffer; Count: LongInt): LongInt; override;
  end;

  TRecordingWriter = class(TAbstractObjectWriter)
  public
    CurrencyValue: Currency;
    FloatValue: Extended;
    UnsignedValue: QWord;
    Text: UnicodeString;
    procedure WriteCurrency(const Value: Currency); override;
    procedure WriteFloat(const Value: Extended); override;
    procedure WriteUInt64(Value: QWord); override;
    procedure WriteUnicodeString(const Value: UnicodeString); override;
    procedure WriteIdent(const Ident: string); override;
    procedure Write(const Buffer; Count: LongInt); override;
  end;

  TTypedReader = class(TAbstractObjectReader)
  public
    Kind: TValueType;
    Consumed: Boolean;
    function NextValue: TValueType; override;
    function ReadValue: TValueType; override;
    function ReadWideString: WideString; override;
    function ReadUnicodeString: UnicodeString; override;
    function ReadString(StringType: TValueType): RawByteString; override;
  end;

  TReaderAdapter = class(TReader)
    function CreateDriver(Stream: TStream; BufSize: Integer): TAbstractObjectReader; override;
  end;

function TTypedReader.NextValue: TValueType;
begin
  If Consumed then Result := vaNull else Result := Kind;
end;

function TTypedReader.ReadValue: TValueType;
begin
  Consumed := True;
  Result := Kind;
end;

function TTypedReader.ReadWideString: WideString;
begin
  If Kind <> vaWString then raise Exception.Create('Wrong WideString dispatch');
  Result := WideChar($042F);
end;

function TTypedReader.ReadUnicodeString: UnicodeString;
begin
  If Kind <> vaUString then raise Exception.Create('Wrong UnicodeString dispatch');
  Result := WideChar($042F);
end;

function TTypedReader.ReadString(StringType: TValueType): RawByteString;
begin
  If StringType <> Kind then raise Exception.Create('Wrong string tag dispatch');
  Result := AnsiChar($D0) + AnsiChar($AF);
end;

function TReaderAdapter.CreateDriver(Stream: TStream; BufSize: Integer): TAbstractObjectReader;
var
  Tag: Byte;
  Driver: TTypedReader;
begin
  Stream.ReadBuffer(Tag, 1);
  Driver := TTypedReader.Create;
  Driver.Kind := TValueType(Tag);
  Result := Driver;
end;

procedure TRecordingWriter.WriteCurrency(const Value: Currency);
begin
  CurrencyValue := Value;
end;

procedure TRecordingWriter.WriteFloat(const Value: Extended);
begin
  FloatValue := Value;
end;

procedure TRecordingWriter.WriteUInt64(Value: QWord);
begin
  UnsignedValue := Value;
end;

procedure TRecordingWriter.WriteUnicodeString(const Value: UnicodeString);
begin
  Text := Value;
end;

procedure TRecordingWriter.WriteIdent(const Ident: string);
begin
  Text := Ident;
end;

procedure TRecordingWriter.Write(const Buffer; Count: LongInt);
begin
  raise Exception.Create('Semantic writer received raw binary data');
end;

function TFragmentedStream.Read(var Buffer; Count: LongInt): LongInt;
begin
  If Count > 2 then Count := 2;
  Result := inherited Read(Buffer, Count);
end;

procedure Check(Condition: Boolean; const Detail: string);
begin
  If not Condition then raise Exception.Create(Detail);
end;

procedure Bytes(S: TStream; const Data: array of Byte);
begin
  If Length(Data) > 0 then S.WriteBuffer(Data[0], Length(Data));
end;

procedure Payload(S: TStream; Value: TValueType);
begin
  Bytes(S, [Ord(Value)]);
  case Value of
    vaNull, vaFalse, vaTrue, vaNil: ;
    vaList:
      begin
        Payload(S, vaTrue);
        Payload(S, vaCurrency);
        Payload(S, vaUString);
        Bytes(S, [Ord(vaList), Ord(vaNil), Ord(vaNull), Ord(vaNull)]);
      end;
    vaCollection:
      begin
        { Ordered item; names are short strings, not value tags. }
        Bytes(S, [Ord(vaInt8), 7, Ord(vaList), 4, 78, 97, 109, 101]);
        Payload(S, vaUString);
        Bytes(S, [4, 68, 97, 116, 97]);
        Payload(S, vaList);
        Bytes(S, [6, 78, 101, 115, 116, 101, 100, Ord(vaCollection), Ord(vaList)]);
        Bytes(S, [1, 88, Ord(vaTrue), 0, 0, 0]);
        { Unordered empty item and collection terminator. }
        Bytes(S, [Ord(vaList), 0, 0]);
      end;
    vaInt8: Bytes(S, [$81]);
    vaInt16: Bytes(S, [0, $80]);
    vaInt32: Bytes(S, [0, 0, 0, $80]);
    vaInt64: Bytes(S, [0, 0, 0, 0, 0, 0, 0, $80]);
    vaQWord: Bytes(S, [255, 255, 255, 255, 255, 255, 255, 255]);
    { Preserve signed zero and NaN payloads without floating-point conversion. }
    vaSingle: Bytes(S, [0, 0, 0, $80]);
    vaExtended: Bytes(S, [17, 0, 0, 0, 0, 0, 0, $C0, $FF, $7F]);
    vaDouble: Bytes(S, [23, 0, 0, 0, 0, 0, $F8, $7F]);
    vaDate: Bytes(S, [0, 0, 0, 0, 0, 0, $F0, $3F]);
    vaCurrency: Bytes(S, [1, 0, 0, 0, 0, 0, 0, $80]);
    vaString, vaIdent: Bytes(S, [3, 65, 0, 255]);
    vaBinary, vaLString: Bytes(S, [3, 0, 0, 0, 0, $FF, $80]);
    vaUTF8String: Bytes(S, [6, 0, 0, 0, $D0, $AF, $F0, $9F, $98, $80]);
    vaWString, vaUString: Bytes(S, [4, 0, 0, 0, $2F, $04, 0, 0, $3D, $D8, 0, $DE]);
    vaSet: Bytes(S, [1, 65, 3, 66, 67, 68, 0]);
  end;
end;

procedure Exercise(Value: TMemoryStream; BufferSize: Integer; CopyIt: Boolean);
var
  Source: TFragmentedStream;
  Dest: TMemoryStream;
  Reader: TReader;
  Writer: TWriter;
begin
  Source := TFragmentedStream.Create;
  Dest := TMemoryStream.Create;
  try
    Source.WriteBuffer(Value.Memory^, Value.Size);
    Bytes(Source, [Ord(vaInt32), $78, $56, $34, $12]);
    Source.Position := 0;
    Reader := TReader.Create(Source, BufferSize);
    Writer := TWriter.Create(Dest, 7);
    try
      If CopyIt then Reader.CopyValue(Writer) else Reader.SkipValue;
      If PByte(Value.Memory)^ in [Ord(vaList), Ord(vaCollection)] then
        Check(Reader.Driver.CurrentValue = vaNull, 'Container terminator state lost');
      Check(Reader.ReadInteger = $12345678, 'Reader lost the following value');
      Writer.FlushBuffer;
      If CopyIt then begin
        Check(Dest.Size = Value.Size, 'Copy changed the encoded size');
        Check(CompareMem(Dest.Memory, Value.Memory, Value.Size), 'Copy changed encoded bytes');
      end else Check(Dest.Size = 0, 'Skip wrote output');
    finally
      Writer.Free;
      Reader.Free;
    end;
  finally
    Dest.Free;
    Source.Free;
  end;
end;

procedure Reject(Value: TMemoryStream; Cut: Integer; CopyIt: Boolean);
var
  Source, Dest: TMemoryStream;
  Reader: TReader;
  Writer: TWriter;
  Raised: Boolean;
begin
  Source := TMemoryStream.Create;
  Dest := TMemoryStream.Create;
  try
    If Cut > 0 then Source.WriteBuffer(Value.Memory^, Cut);
    Source.Position := 0;
    Reader := TReader.Create(Source, 3);
    Writer := TWriter.Create(Dest, 5);
    try
      Raised := False;
      try
        If CopyIt then Reader.CopyValue(Writer) else Reader.SkipValue;
      except
        on E: EReadError do Raised := True;
      end;
      Check(Raised, 'Invalid resource accepted at length ' + IntToStr(Cut));
    finally
      Writer.Free;
      Reader.Free;
    end;
  finally
    Dest.Free;
    Source.Free;
  end;
end;

procedure CheckSemanticValues;
var
  Source: TMemoryStream;
  Reader: TReader;
  Writer: TWriter;
  Driver: TRecordingWriter;
  V: Variant;
  Pass: Integer;
begin
  Source := TMemoryStream.Create;
  Driver := TRecordingWriter.Create;
  Writer := TWriter.Create(Driver);
  try
    Bytes(Source, [Ord(vaCurrency), $10, $27, 0, 0, 0, 0, 0, 0]); { 1.0000 }
    Bytes(Source, [Ord(vaCurrency), $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF]); { -0.0001 }
    Bytes(Source, [Ord(vaDouble), 0, 0, 0, 0, 0, 0, $F0, $3F]); { 1.0 }
    Bytes(Source, [Ord(vaQWord), $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF]);
    Bytes(Source, [Ord(vaTrue), Ord(vaUString), 1, 0, 0, 0, 65, 0, Ord(vaInt8), 42]);
    for Pass := 0 to 1 do begin
      Source.Position := 0;
      Reader := TReader.Create(Source, 3);
      try
        If Pass = 0 then begin
          Check(Reader.ReadCurrency = 1, 'Currency scale lost');
          Check(Reader.ReadCurrency = -0.0001, 'Currency sign or fraction lost');
          Check(Reader.ReadDouble = 1, 'Double value lost');
          V := Reader.ReadVariant;
          Check(VarType(V) = varQWord, 'Unsigned variant type lost');
          Check(QWord(V) = High(QWord), 'Unsigned variant value lost');
          Check(Reader.ReadBoolean, 'Boolean value lost');
          Check(Reader.ReadUnicodeString = 'A', 'Unicode value lost');
        end else begin
          Reader.CopyValue(Writer);
          Check(Driver.CurrencyValue = 1, 'Copied Currency scale lost');
          Reader.CopyValue(Writer);
          Check(Driver.CurrencyValue = -0.0001, 'Copied Currency fraction lost');
          Reader.CopyValue(Writer);
          Check(Driver.FloatValue = 1, 'Copied Double lost');
          Reader.CopyValue(Writer);
          Check(Driver.UnsignedValue = High(QWord), 'Copied unsigned value lost');
          Reader.CopyValue(Writer);
          Check(Driver.Text = 'True', 'Copied Boolean lost');
          Reader.CopyValue(Writer);
          Check(Driver.Text = 'A', 'Copied Unicode lost');
        end;
        Check(Reader.ReadInteger = 42, 'Semantic reader position lost');
      finally
        Reader.Free;
      end;
    end;
  finally
    Writer.Free;
    Driver.Free;
    Source.Free;
  end;
end;

procedure CheckTypedDriver;
var
  Source: TMemoryStream;
  Reader: TReader;
  Writer: TWriter;
  Driver: TRecordingWriter;
  Kind: TValueType;
  Pass: Integer;
begin
  Source := TMemoryStream.Create;
  Driver := TRecordingWriter.Create;
  Writer := TWriter.Create(Driver);
  try
    for Kind in [vaWString, vaUString, vaUTF8String] do
      for Pass := 0 to 2 do begin
        Source.Clear;
        Bytes(Source, [Ord(Kind)]);
        Source.Position := 0;
        Reader := TReaderAdapter.Create(Source, 3);
        try
          If Pass = 2 then begin
            Reader.CopyValue(Writer);
            Check(Driver.Text = WideChar($042F), 'Custom copy string dispatch');
          end else If Pass = 1 then
            Check(Reader.ReadUnicodeString = WideChar($042F), 'Custom read UnicodeString dispatch')
          else Check(Reader.ReadWideString = WideChar($042F), 'Custom read WideString dispatch');
          Check(Reader.NextValue = vaNull, 'Custom reader did not consume tag');
        finally
          Reader.Free;
        end;
      end;
  finally
    Writer.Free;
    Driver.Free;
    Source.Free;
  end;
end;

var
  Value: TMemoryStream;
  Kind: TValueType;
  Mode: Boolean;
  N, BufferSize: Integer;
  B: Byte;
begin
  CheckSemanticValues;
  CheckTypedDriver;
  Value := TMemoryStream.Create;
  try
    for Kind := Low(TValueType) to High(TValueType) do begin
      Value.Clear;
      Payload(Value, Kind);
      for Mode := False to True do begin
        for BufferSize in [1, 3, 17, 128] do Exercise(Value, BufferSize, Mode);
        for N := 0 to Value.Size - 1 do Reject(Value, N, Mode);
      end;
    end;
    { Cross multiple copy chunks; no giant temporary allocation is necessary. }
    Value.Clear;
    Bytes(Value, [Ord(vaBinary), 3, 16, 0, 0]);
    for N := 0 to 4098 do begin
      B := Byte(N);
      Value.WriteBuffer(B, 1);
    end;
    Exercise(Value, 1024, True);
    Exercise(Value, 1024, False);
    for Mode := False to True do Reject(Value, Value.Size - 1, Mode);
    for Kind in [vaBinary, vaLString, vaUTF8String, vaWString, vaUString] do begin
      Value.Clear;
      Bytes(Value, [Ord(Kind), $FF, $FF, $FF, $FF]);
      for Mode := False to True do Reject(Value, Value.Size, Mode);
      Value.Clear;
      Bytes(Value, [Ord(Kind), 0, 0, 0, $40, 1, 2]);
      for Mode := False to True do Reject(Value, Value.Size, Mode);
      Value.Clear;
      Bytes(Value, [Ord(Kind), 0, 0, 0, 0]);
      for Mode := False to True do Exercise(Value, 1, Mode);
    end;
    Value.Clear;
    Bytes(Value, [$FF]);
    for Mode := False to True do Reject(Value, Value.Size, Mode);
    Value.Clear;
    Bytes(Value, [Ord(vaCollection), Ord(vaTrue), 0]);
    for Mode := False to True do Reject(Value, Value.Size, Mode);
  finally
    Value.Free;
  end;
  WriteLn('READER_VALUE_TRANSFER_PASS');
end.
