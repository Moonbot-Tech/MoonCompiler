{$ifdef BREADTH_HAS_PRODUCT_IO}
{ Iterate matching filenames and restart the cursor without keeping a borrowed search buffer. }

procedure RunBreadthDirectoryCursor;
const
  First: UnicodeString = 'alpha-' + #$03BB + '.rule';
  Second: UnicodeString = 'beta-' + #$D83D#$DE80 + '.rule';
var
  Root, A, B, Ignored, Name: string;
  Listing: IEnumerable<string>;
  Cursor: IEnumerator<string>;
  Seen, Count: Integer;
begin
  Root := TPath.GetTempFileName;
  DeleteFile(Root);
  TDirectory.CreateDirectory(Root);
  A := TPath.Combine(Root, First);
  B := TPath.Combine(Root, Second);
  Ignored := TPath.Combine(Root, 'archive.txt');
  try
    TFile.WriteAllText(A, 'one');
    TFile.WriteAllText(B, 'two');
    TFile.WriteAllText(Ignored, 'skip');
    Listing := TDirectory.GetFilesEnumerator(Root, '*.rule');
    Cursor := Listing.GetEnumerator;
    Seen := 0;
    Count := 0;
    while Cursor.MoveNext do begin
      Name := TPath.GetFileName(Cursor.Current);
      Inc(Count);
      If Name = First then
        Seen := Seen or 1
      else If Name = Second then
        Seen := Seen or 2;
    end;
    Check((Count = 2) and (Seen = 3), 'breadth-directory-cursor-enumerates-only-matching-unicode-leaves');
    Cursor.Reset;
    Name := '';
    If Cursor.MoveNext then
      Name := TPath.GetFileName(Cursor.Current);
    Check((Name = First) or (Name = Second), 'breadth-directory-cursor-reset-restores-a-valid-first-result');
    Cursor := nil;
    Listing := nil;
    Check((Name = First) or (Name = Second), 'breadth-directory-cursor-name-survives-releasing-search-state');
    Mix(UInt64(Count * 100 + Seen));
  finally
    Cursor := nil;
    Listing := nil;
    DeleteFile(Ignored);
    DeleteFile(B);
    DeleteFile(A);
    TDirectory.Delete(Root, False);
  end;
end;
{$endif}
