{ Two property types may use the same configuration word at different ordinals. }

{$SCOPEDENUMS ON}
type
  TBreadthDisplayMode = (Disabled, Preview, Active);
  TBreadthExportMode = (Disabled, Active, Deferred);
{$SCOPEDENUMS OFF}

type
  TBreadthModeSettings = class(TPersistent)
  private
    FDisplay: TBreadthDisplayMode;
    FExport: TBreadthExportMode;
  published
    property DisplayMode: TBreadthDisplayMode read FDisplay write FDisplay;
    property ExportMode: TBreadthExportMode read FExport write FExport;
  end;

procedure RunBreadthScopedModeSettings;
const
  Input: string = 'aCtIvE';
var
  Settings: TBreadthModeSettings;
  DisplayIndex, ExportIndex: Integer;
  Boxed: TValue;
begin
  DisplayIndex := GetEnumValue(TypeInfo(TBreadthDisplayMode), Input);
  ExportIndex := GetEnumValue(TypeInfo(TBreadthExportMode), Input);
  Check((DisplayIndex = 2) and (ExportIndex = 1), 'breadth-scoped-mode-looks-up-token-in-correct-enum-type');
  Boxed := TValue.FromOrdinal(TypeInfo(TBreadthDisplayMode), DisplayIndex);
  Check((Boxed.Kind = tkEnumeration) and (Boxed.AsOrdinal = 2) and (Boxed.AsType<TBreadthDisplayMode> = TBreadthDisplayMode.Active),
    'breadth-scoped-mode-boxes-ordinal-with-exact-type');
  Settings := TBreadthModeSettings.Create;
  try
    SetEnumProp(Settings, 'DisplayMode', Input);
    SetEnumProp(Settings, 'ExportMode', Input);
    Check((Settings.DisplayMode = TBreadthDisplayMode.Active) and (Settings.ExportMode = TBreadthExportMode.Active),
      'breadth-scoped-mode-published-settings-store-distinct-ordinals');
    Check((GetEnumProp(Settings, 'DisplayMode') = 'Active') and (GetEnumProp(Settings, 'ExportMode') = 'Active'),
      'breadth-scoped-mode-export-returns-canonical-member-name');
    Check((GetEnumValue(TypeInfo(TBreadthDisplayMode), 'Deferred') < 0) and (Settings.DisplayMode = TBreadthDisplayMode.Active),
      'breadth-scoped-mode-rejects-member-of-another-enum');
    Mix(UInt64(DisplayIndex * 10 + ExportIndex));
  finally
    Settings.Free;
  end;
end;
