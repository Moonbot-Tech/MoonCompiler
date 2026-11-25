{$ifdef BREADTH_HAS_PRODUCT_IO}
{ Import a Windows UTF-16 strategy and publish its typed values as portable UTF-8 JSON. }

procedure RunBreadthStrategyWireBridge;
const
  WindowsIni: array[0..147] of Byte = (
    $FE, $FF, $00, $5B, $00, $54, $00, $72, $00, $61, $00, $64, $00, $69, $00, $6E, $00, $67, $00, $5D,
    $00, $0D, $00, $0A, $00, $52, $00, $6F, $00, $75, $00, $74, $00, $65, $00, $49, $00, $64, $00, $3D,
    $00, $39, $00, $30, $00, $30, $00, $37, $00, $31, $00, $39, $00, $39, $00, $32, $00, $35, $00, $34,
    $00, $37, $00, $34, $00, $30, $00, $39, $00, $39, $00, $33, $00, $0D, $00, $0A, $00, $54, $00, $69,
    $00, $74, $00, $6C, $00, $65, $00, $3D, $00, $47, $00, $72, $00, $69, $00, $64, $00, $20, $03, $BB,
    $00, $0D, $00, $0A, $00, $45, $00, $6E, $00, $61, $00, $62, $00, $6C, $00, $65, $00, $64, $00, $3D,
    $00, $31, $00, $0D, $00, $0A, $00, $51, $00, $75, $00, $6F, $00, $74, $00, $61, $00, $3D, $00, $2D,
    $00, $31, $00, $37, $00, $0D, $00, $0A);
  ExpectedWire: array[0..70] of Byte = (
    $7B, $22, $72, $6F, $75, $74, $65, $22, $3A, $39, $30, $30, $37, $31, $39, $39, $32, $35, $34, $37,
    $34, $30, $39, $39, $33, $2C, $22, $74, $69, $74, $6C, $65, $22, $3A, $22, $47, $72, $69, $64, $20,
    $CE, $BB, $22, $2C, $22, $65, $6E, $61, $62, $6C, $65, $64, $22, $3A, $74, $72, $75, $65, $2C, $22,
    $71, $75, $6F, $74, $61, $22, $3A, $2D, $31, $37, $7D);
var
  SourceFile, ExportFile, TitleText: string;
  SourceBytes, Actual: TBytes;
  Settings: TMemIniFile;
  Route, RoundTrip: Int64;
  Enabled: Boolean;
  Quota: Integer;
  Text: TStringWriter;
  Writer: TJsonTextWriter;
  Exported, Token, NameValue, FlagValue, QuotaValue: TJSONValue;
  ObjectValue: TJSONObject;
begin
  SourceFile := TPath.GetTempFileName;
  try
    ExportFile := TPath.GetTempFileName;
    try
      SetLength(SourceBytes, SizeOf(WindowsIni));
      Move(WindowsIni, SourceBytes[0], SizeOf(WindowsIni));
      TFile.WriteAllBytes(SourceFile, SourceBytes);
      Settings := TMemIniFile.Create(SourceFile);
      try
        Route := Settings.ReadInt64('Trading', 'RouteId', 0);
        TitleText := Settings.ReadString('Trading', 'Title', '');
        Enabled := Settings.ReadBool('Trading', 'Enabled', False);
        Quota := Settings.ReadInteger('Trading', 'Quota', 0);
      finally
        Settings.Free;
      end;
      Check((Route = 9007199254740993) and (TitleText = 'Grid ' + #$03BB) and Enabled and (Quota = -17),
        'breadth-strategy-bridge-loads-typed-values-from-independent-utf16-fixture');

      Text := TStringWriter.Create;
      try
        Writer := TJsonTextWriter.Create(Text, False);
        try
          Writer.WriteStartObject;
          Writer.WritePropertyName('route');
          Writer.WriteValue(Route);
          Writer.WritePropertyName('title');
          Writer.WriteValue(TitleText);
          Writer.WritePropertyName('enabled');
          Writer.WriteValue(Enabled);
          Writer.WritePropertyName('quota');
          Writer.WriteValue(Quota);
          Writer.WriteEndObject;
        finally
          Writer.Free;
        end;
        TFile.WriteAllBytes(ExportFile, TEncoding.UTF8.GetBytes(Text.ToString));
      finally
        Text.Free;
      end;

      Actual := TFile.ReadAllBytes(ExportFile);
      Check((Length(Actual) = SizeOf(ExpectedWire)) and CompareMem(Pointer(Actual), @ExpectedWire[0], SizeOf(ExpectedWire)),
        'breadth-strategy-bridge-publishes-exact-independent-utf8-wire-bytes');
      Exported := TJSONObject.ParseJSONValue(TFile.ReadAllText(ExportFile));
      try
        Check(Exported is TJSONObject, 'breadth-strategy-bridge-export-can-be-opened-by-json-consumer');
        If Exported is TJSONObject then begin
          ObjectValue := TJSONObject(Exported);
          Token := ObjectValue.GetValue('route');
          NameValue := ObjectValue.GetValue('title');
          FlagValue := ObjectValue.GetValue('enabled');
          QuotaValue := ObjectValue.GetValue('quota');
          Check((Token is TJSONNumber) and TryStrToInt64(Token.Value, RoundTrip) and (RoundTrip = 9007199254740993)
            and (NameValue <> nil) and (NameValue.Value = 'Grid ' + #$03BB) and (FlagValue <> nil) and (FlagValue.Value = 'true')
            and (QuotaValue <> nil) and (QuotaValue.Value = '-17'), 'breadth-strategy-bridge-consumer-retains-all-exported-field-values');
        end;
      finally
        Exported.Free;
      end;
      Actual := TFile.ReadAllBytes(SourceFile);
      Check((Length(Actual) = SizeOf(WindowsIni)) and CompareMem(Pointer(Actual), @WindowsIni[0], SizeOf(WindowsIni)),
        'breadth-strategy-bridge-export-leaves-imported-windows-file-unchanged');
      Mix(UInt64(Route));
    finally
      DeleteFile(ExportFile);
    end;
  finally
    DeleteFile(SourceFile);
  end;
end;
{$endif}
