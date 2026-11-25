{$ifdef BREADTH_HAS_PRODUCT_IO}
{ A copied archive retains its explicit whole-second UTC mtime. }

procedure RunBreadthArchiveTimestamp;
const
  Expected = '2020-02-29T14:51:26.000Z';
var
  Orig, CopyPath: string;
  Stamp: TDateTime;
begin
  Orig := TPath.GetTempFileName;
  try
    CopyPath := TPath.GetTempFileName;
    try
      TFile.WriteAllBytes(Orig, [1, 2, 3]);
      Stamp := EncodeDate(2020, 2, 29) + EncodeTime(14, 51, Word(OpaqueI(26)), 0);
      TFile.SetLastWriteTimeUtc(Orig, Stamp);
      Check(DateToISO8601(TFile.GetLastWriteTimeUtc(Orig), True) = Expected,
        'breadth-archive-mtime-accepted-on-source-in-utc');
      TFile.Copy(Orig, CopyPath, True);
      Check(DateToISO8601(TFile.GetLastWriteTimeUtc(CopyPath), True) = Expected,
        'breadth-archive-mtime-copy-keeps-exact-even-second');
      Check(DateToISO8601(TFile.GetLastWriteTimeUtc(Orig), True) = Expected,
        'breadth-archive-mtime-copy-does-not-rewrite-source-mtime');
      Mix(UInt64(DateTimeToUnix(Stamp, True)));
    finally
      DeleteFile(CopyPath);
    end;
  finally
    DeleteFile(Orig);
  end;
end;
{$endif}
