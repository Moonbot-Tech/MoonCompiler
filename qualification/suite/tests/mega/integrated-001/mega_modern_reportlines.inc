{$ifdef BREADTH_HAS_PRODUCT_IO}
{ A text report copied across platforms may contain mixed line endings and counted text. }

procedure RunBreadthReadReportLines;
var
  Path: string;
  Lines: TStringDynArray;
begin
  Path := TPath.GetTempFileName;
  try
    TFile.WriteAllBytes(Path, [$EF, $BB, $BF, $41, 0, $42, 13, 10, 13, 10, $CE, $BB, 10, $5A, 13]);
    Lines := TFile.ReadAllLines(Path);
    Check(Length(Lines) = 4, 'breadth-report-lines-keeps-interior-empty-row-and-trims-final-line-ending');
    If Length(Lines) <> 4 then
      Exit;
    Check((Lines[0] = 'A' + #0 + 'B') and (Lines[1] = ''), 'breadth-report-lines-removes-bom-and-keeps-counted-first-row');
    Check((Lines[2] = #$03BB) and (Lines[3] = 'Z'), 'breadth-report-lines-recognizes-lf-and-lone-cr');
    Mix(UInt64(Length(Lines[0]) * 100 + Length(Lines)));
  finally
    DeleteFile(Path);
  end;
end;
{$endif}
