{$ifdef BREADTH_HAS_PRODUCT_IO}
{ Commit a UTF-16 configuration after observing its previous content from a second reader. }

procedure RunBreadthIniDiskCommit;
const
  Initial = '[Strategy]'#13#10 +
    'MaxOrders=17'#13#10 +
    'Caption=before '#$03BB#13#10 +
    'Retired=old'#13#10 +
    '[Neighbor]'#13#10 +
    'Keep=unchanged'#13#10;
var
  Path: string;
  Ini: TMemIniFile;
  Bytes: TBytes;
begin
  Path := TPath.GetTempFileName;
  try
    TFile.WriteAllText(Path, Initial, TEncoding.BigEndianUnicode);
    Ini := TMemIniFile.Create(Path);
    try
      Check((Ini.ReadInt64('strategy', 'MaxOrders', -1) = 17) and
        (Ini.ReadString('Strategy', 'Caption', '') = 'before ' + #$03BB), 'breadth-ini-file-imports-big-endian-settings');
      Ini.WriteInt64('strategy', 'MaxOrders', OpaqueI(930000000011));
      Ini.WriteString('Strategy', 'Caption', 'committed ' + #$D83D + #$DE80 + ' = live');
      Ini.DeleteKey('Strategy', 'Retired');
      Check(TFile.ReadAllText(Path) = Initial, 'breadth-ini-file-staging-keeps-original-disk-state-until-commit');
      Ini.UpdateFile;
    finally
      FreeAndNil(Ini);
    end;

    Bytes := TFile.ReadAllBytes(Path);
    Check((Length(Bytes) > 2) and (Bytes[0] = $FE) and (Bytes[1] = $FF),
      'breadth-ini-file-commit-preserves-big-endian-preamble');
    Ini := TMemIniFile.Create(Path);
    try
      Check((Ini.ReadInt64('Strategy', 'MaxOrders', -1) = 930000000011)
        and (Ini.ReadString('strategy', 'Caption', '') = 'committed ' + #$D83D + #$DE80 + ' = live')
        and (Ini.ReadString('Strategy', 'Retired', 'missing') = 'missing')
        and (Ini.ReadString('Neighbor', 'Keep', '') = 'unchanged'),
        'breadth-ini-file-reopen-keeps-committed-values-removal-and-neighbor');
      Mix(UInt64(Ini.ReadInt64('Strategy', 'MaxOrders', -1)));
    finally
      FreeAndNil(Ini);
    end;
  finally
    DeleteFile(Path);
  end;
end;
{$endif}
