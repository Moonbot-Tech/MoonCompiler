{$ifdef BREADTH_HAS_PRODUCT_IO}
{ Publishing a new binary strategy writes the previous active version to the recovery path. }

procedure RunBreadthPublishBinarySettings;
const
  Latest: array[0..3] of Byte = ($E1, 0, $BB, $7A);
  Prior: array[0..4] of Byte = ($F1, $C3, 0, $03, 0);
var
  Candidate, Active, Backup: string;
  Wire: TBytes;
begin
  Candidate := TPath.GetTempFileName;
  try
    Active := TPath.GetTempFileName;
    try
      Backup := TPath.GetTempFileName;
      try
        TFile.WriteAllBytes(Candidate, [$E1, 0, $BB, $7A]);
        TFile.WriteAllBytes(Active, [$F1, $C3, 0, $03, 0]);
        TFile.WriteAllBytes(Backup, [$FF, $AB]);
        TFile.Replace(Candidate, Active, Backup);
        Check(not TFile.Exists(Candidate), 'breadth-publish-settings-consumes-candidate-on-success');
        Wire := TFile.ReadAllBytes(Active);
        Check((Length(Wire) = SizeOf(Latest)) and CompareMem(Pointer(Wire), @Latest[0], SizeOf(Latest)),
          'breadth-publish-settings-activates-exact-new-binary-version');
        Wire := TFile.ReadAllBytes(Backup);
        Check((Length(Wire) = SizeOf(Prior)) and CompareMem(Pointer(Wire), @Prior[0], SizeOf(Prior)),
          'breadth-publish-settings-replaces-stale-backup-with-previous-active-version');
        Mix(UInt64(Length(Wire)));
      finally
        DeleteFile(Backup);
      end;
    finally
      DeleteFile(Active);
    end;
  finally
    DeleteFile(Candidate);
  end;
end;
{$endif}
