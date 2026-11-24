{$ifdef BREADTH_HAS_EXTENDED_METHODS}
{ Produce and consume a stable packet with independent bytes for both directions. }

type
  {$RTTI EXPLICIT FIELDS([vcPublic])}
  TBreadthWireIdentity = class
  public
    Ticket: UInt64;
  end;

  TBreadthWireSettings = class(TBreadthWireIdentity)
  public
    Text: UnicodeString;
    Enabled: Boolean;
  end;
  {$RTTI INHERIT}

const
  BreadthSettingsTicket = UInt64($F123456789ABCDEF);
  BreadthSettingsText: UnicodeString = 'A' + #0 + #$03BB + #$D83D#$DE00;
  BreadthSettingsWire: array[0..17] of Byte =
    ($EF, $CD, $AB, $89, $67, $45, $23, $F1, 1, 8, $41, 0, $CE, $BB, $F0, $9F, $98, $80);

procedure BreadthWriteSettings(Stream: TStream; Settings: TBreadthWireSettings; Schema: TRttiType);
var
  Ticket: UInt64;
  Enabled, Count: Byte;
  Bytes: TBytes;
begin
  Ticket := Schema.GetField('Ticket').GetValue(Settings).AsUInt64;
  Enabled := Ord(Schema.GetField('Enabled').GetValue(Settings).AsBoolean);
  Bytes := TEncoding.UTF8.GetBytes(Schema.GetField('Text').GetValue(Settings).AsString);
  Count := Length(Bytes);
  Stream.WriteBuffer(Ticket, SizeOf(Ticket));
  Stream.WriteBuffer(Enabled, SizeOf(Enabled));
  Stream.WriteBuffer(Count, SizeOf(Count));
  If Count <> 0 then
    Stream.WriteBuffer(Bytes[0], Count);
end;

procedure BreadthReadSettings(Stream: TStream; Settings: TBreadthWireSettings; Schema: TRttiType);
var
  Ticket: UInt64;
  Enabled, Count: Byte;
  Bytes: TBytes;
begin
  Stream.ReadBuffer(Ticket, SizeOf(Ticket));
  Stream.ReadBuffer(Enabled, SizeOf(Enabled));
  Stream.ReadBuffer(Count, SizeOf(Count));
  SetLength(Bytes, Count);
  If Count <> 0 then
    Stream.ReadBuffer(Bytes[0], Count);
  Schema.GetField('Ticket').SetValue(Settings, TValue.From<UInt64>(Ticket));
  Schema.GetField('Enabled').SetValue(Settings, TValue.From<Boolean>(Enabled <> 0));
  Schema.GetField('Text').SetValue(Settings, TValue.From<UnicodeString>(TEncoding.UTF8.GetString(Bytes)));
end;

procedure RunBreadthReflectSettingsWire;
var
  Context: TRttiContext;
  Schema: TRttiType;
  Settings: TBreadthWireSettings;
  Stream: TMemoryStream;
begin
  Context := TRttiContext.Create;
  try
    Schema := Context.GetType(TBreadthWireSettings);
    Check((Schema.GetField('Ticket') <> nil) and (Schema.GetField('Enabled') <> nil) and (Schema.GetField('Text') <> nil),
      'breadth-rtti-settings-discovers-inherited-and-own-fields');
    Settings := TBreadthWireSettings.Create;
    try
      Stream := TMemoryStream.Create;
      try
        Settings.Ticket := BreadthSettingsTicket xor UInt64(OpaqueI(0));
        Settings.Enabled := True;
        Settings.Text := BreadthSettingsText;
        BreadthWriteSettings(Stream, Settings, Schema);
        Check((Stream.Size = SizeOf(BreadthSettingsWire))
          and CompareMem(Stream.Memory, @BreadthSettingsWire[0], SizeOf(BreadthSettingsWire)),
          'breadth-rtti-settings-write-preserves-high-bit-and-utf8-wire-bytes');
        Stream.Size := 0;
        Stream.Position := 0;
        Stream.WriteBuffer(BreadthSettingsWire[0], SizeOf(BreadthSettingsWire));
        Stream.Position := 0;
        Settings.Ticket := 9;
        Settings.Enabled := False;
        Settings.Text := 'earlier';
        BreadthReadSettings(Stream, Settings, Schema);
        Check((Settings.Ticket = BreadthSettingsTicket) and Settings.Enabled and (Settings.Text = BreadthSettingsText),
          'breadth-rtti-settings-read-updates-existing-instance-from-independent-wire');
        Check(Stream.Position = SizeOf(BreadthSettingsWire), 'breadth-rtti-settings-leaves-reader-at-packet-end');
        Mix(Settings.Ticket);
        Mix(UInt64(Length(Settings.Text)));
      finally
        Stream.Free;
      end;
    finally
      Settings.Free;
    end;
  finally
    Context.Free;
  end;
end;
{$endif}
