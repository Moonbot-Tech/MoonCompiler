{ The saved form and the loaded form each have an independent expectation. }

procedure RunBreadthIniTransfer;
var
  Ini, Loaded: TMemIniFile;
  Source, Exported: TStringList;
  Venue: string;
  Cursor: Int64;
begin
  Venue := 'feed-' + WideChar(OpaqueI($03BB)) + '=BTC';
  Source := TStringList.Create;
  try
    Exported := TStringList.Create;
    try
      Source.Add('[Trading]');
      Source.Add('Enabled=1');
      Source.Add('Cursor=930000000001');
      Source.Add('Venue=' + Venue);
      Source.Add('[Other]');
      Source.Add('Keep=unmodified');
      Ini := TMemIniFile.Create('');
      try
        Ini.SetStrings(Source);
        Check(Ini.ReadBool('trading', 'enabled', False) and (Ini.ReadInt64('Trading', 'Cursor', 0) = 930000000001)
          and (Ini.ReadString('TRADING', 'VENUE', '') = Venue),
          'breadth-ini-import-retains-typed-values-and-embedded-separator');
        Ini.WriteBool('Trading', 'Enabled', False);
        Ini.WriteInt64('Trading', 'Cursor', OpaqueI(-720000000099));
        Ini.DeleteKey('Trading', 'Venue');
        Check((Ini.ReadString('Trading', 'Venue', 'missing') = 'missing') and not Ini.ReadBool('Trading', 'Enabled', True),
          'breadth-ini-replaces-boolean-and-uses-default-after-removal');
        Ini.GetStrings(Exported);
        Check((Exported.IndexOf('[Trading]') >= 0) and (Exported.IndexOf('Cursor=-720000000099') >= 0)
          and (Exported.IndexOf('Venue=' + Venue) = -1), 'breadth-ini-export-retains-exact-wide-integer-and-omits-deleted-key');
      finally
        Ini.Free;
      end;
      Loaded := TMemIniFile.Create('');
      try
        Loaded.SetStrings(Exported);
        Cursor := Loaded.ReadInt64('Trading', 'Cursor', 0);
        Check((Cursor = -720000000099)
          and (Loaded.ReadString('Other', 'Keep', '') = 'unmodified'), 'breadth-ini-export-load-keeps-neighbor-section');
        Mix(UInt64(Cursor));
      finally
        Loaded.Free;
      end;
    finally
      Exported.Free;
    end;
  finally
    Source.Free;
  end;
end;
