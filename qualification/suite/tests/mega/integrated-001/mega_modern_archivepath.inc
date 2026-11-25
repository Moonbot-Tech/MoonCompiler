{$ifdef BREADTH_HAS_PRODUCT_IO}
{ An imported archive resolves its directory before choosing the marker file name. }

procedure RunBreadthArchivePath;
const
  Leaf: UnicodeString = 'edge-' + #$03BB + '.tar.gz';
  Stem: UnicodeString = 'edge-' + #$03BB + '.tar';
var
  Base, Folder, Candidate, Resolved, Marker: string;
begin
  Base := TPath.GetFullPath(TPath.GetTempPath);
  Folder := TPath.Combine(Base, 'cache');
  Candidate := TPath.Combine(Base, 'incoming' + PathDelim + '..' + PathDelim + 'cache' + PathDelim + '.' + PathDelim + Leaf);
  Resolved := TPath.GetFullPath(Candidate);
  Check(TPath.IsPathRooted(Resolved) and (Resolved = TPath.Combine(Folder, Leaf)),
    'breadth-archive-path-normalizes-dot-segments-against-absolute-root');
  Check((TPath.GetDirectoryName(Resolved) = Folder) and (TPath.GetFileName(Resolved) = Leaf),
    'breadth-archive-path-extracts-unicode-leaf-without-moving-folder');
  Check((TPath.GetExtension(Resolved) = '.gz') and (TPath.GetFileNameWithoutExtension(Resolved) = Stem),
    'breadth-archive-path-treats-final-extension-separately');
  Marker := TPath.ChangeExtension(Resolved, '.done');
  Check(Marker = TPath.Combine(Folder, Stem + '.done'), 'breadth-archive-path-marker-keeps-other-name-segments');
  Mix(UInt64(Length(TPath.GetFileName(Marker))));
end;
{$endif}
