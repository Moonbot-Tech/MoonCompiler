{$ifdef BREADTH_HAS_PRODUCT_IO}
{ Apply settings received as JSON and keep the local INI layout outside the imported section. }

procedure RunBreadthCommitExternalStrategy;
const
  Incoming = '{"route":-9007199254740989,"title":"Stage \u03bb","enabled":true,"quota":-37}';
  Prior = '[Trading]'#13#10'RouteId=17'#13#10'Title=Old'#13#10'Enabled=0'#13#10'Quota=9'#13#10
    + '[Local]'#13#10'Theme=dark'#13#10;
var
  Path, TitleText: string;
  Root, RouteToken, TitleToken, EnabledToken, QuotaToken: TJSONValue;
  Obj: TJSONObject;
  Route: Int64;
  Quota: Integer;
  Enabled, Parsed: Boolean;
  Settings: TMemIniFile;
  Bytes: TBytes;
begin
  Route := 0;
  Quota := 0;
  Enabled := False;
  Root := TJSONObject.ParseJSONValue(Incoming);
  try
    Parsed := Root is TJSONObject;
    If Parsed then begin
      Obj := TJSONObject(Root);
      RouteToken := Obj.GetValue('route');
      TitleToken := Obj.GetValue('title');
      EnabledToken := Obj.GetValue('enabled');
      QuotaToken := Obj.GetValue('quota');
      Parsed := (RouteToken is TJSONNumber) and TryStrToInt64(RouteToken.Value, Route)
        and (TitleToken is TJSONString) and (EnabledToken <> nil) and (QuotaToken is TJSONNumber)
        and TryStrToInt(QuotaToken.Value, Quota);
      If Parsed then begin
        TitleText := TitleToken.Value;
        Enabled := EnabledToken.Value = 'true';
      end;
    end;
    Check(Parsed and (Route = -9007199254740989) and (TitleText = 'Stage ' + #$03BB) and Enabled and (Quota = -37),
      'breadth-strategy-commit-reads-typed-wire-values-and-wide-signed-route');
    If not Parsed then
      Exit;
  finally
    Root.Free;
  end;

  Path := TPath.GetTempFileName;
  try
    TFile.WriteAllText(Path, Prior, TEncoding.UTF8);
    Settings := TMemIniFile.Create(Path);
    try
      Settings.WriteInt64('Trading', 'RouteId', Route);
      Settings.WriteString('Trading', 'Title', TitleText);
      Settings.WriteBool('Trading', 'Enabled', Enabled);
      Settings.WriteInteger('Trading', 'Quota', Quota);
      Check(TFile.ReadAllText(Path) = Prior, 'breadth-strategy-commit-staged-import-leaves-current-file-usable');
      Settings.UpdateFile;
    finally
      Settings.Free;
    end;
    Bytes := TFile.ReadAllBytes(Path);
    Check((Length(Bytes) >= 3) and (Bytes[0] = $EF) and (Bytes[1] = $BB) and (Bytes[2] = $BF),
      'breadth-strategy-commit-keeps-existing-utf8-bom');

    Settings := TMemIniFile.Create(Path);
    try
      Check((Settings.ReadInt64('Trading', 'RouteId', 0) = -9007199254740989)
        and (Settings.ReadString('Trading', 'Title', '') = 'Stage ' + #$03BB)
        and Settings.ReadBool('Trading', 'Enabled', False) and (Settings.ReadInteger('Trading', 'Quota', 0) = -37),
        'breadth-strategy-commit-reopened-ini-exposes-all-imported-values');
      Check((Settings.ReadString('Trading', 'Enabled', '') = '1') and (Settings.ReadString('Local', 'Theme', '') = 'dark'),
        'breadth-strategy-commit-keeps-delphi-boolean-wire-and-unrelated-local-preference');
      Mix(UInt64(Settings.ReadInt64('Trading', 'RouteId', 0)));
    finally
      Settings.Free;
    end;
  finally
    DeleteFile(Path);
  end;
end;
{$endif}
