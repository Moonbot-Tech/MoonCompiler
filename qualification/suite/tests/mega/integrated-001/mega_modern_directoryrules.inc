{$if defined(BREADTH_HAS_PRODUCT_IO) and defined(HAS_ANON)}
{ A rules loader filters discovered files by size and reloads a renamed file. }

type
  TBreadthFilePredicate = {$ifdef FPC}TFilterPredicateLocal{$else}TDirectory.TFilterPredicate{$endif};

function BreadthDirectoryHasPair(const Paths: array of string; const First, Second: string): Boolean;
begin
  Result := (Length(Paths) = 2) and (((Paths[0] = First) and (Paths[1] = Second))
    or ((Paths[0] = Second) and (Paths[1] = First)));
end;

procedure RunBreadthDirectoryRules;
var
  Unique: TGUID;
  Allocated, RejectedShort: Boolean;
  Root, Nested, MainRule, NestedRule, MovedRule: string;
  Paths: TStringDynArray;
  Predicate: TBreadthFilePredicate;
  MinSize: Int64;
  Bytes: TBytes;
begin
  Allocated := CreateGUID(Unique) = 0;
  Check(Allocated, 'breadth-directory-rules-allocates-unique-workspace');
  If not Allocated then
    Exit;
  Root := TPath.Combine(TPath.GetTempPath, 'mega-rules-' + GUIDToString(Unique));
  Nested := TPath.Combine(Root, 'nested');
  TDirectory.CreateDirectory(Root);
  try
    TDirectory.CreateDirectory(Nested);
    MainRule := TPath.Combine(Root, 'active-' + #$03BB + '.rule');
    NestedRule := TPath.Combine(Nested, 'backup.rule');
    MovedRule := TPath.Combine(Nested, 'armed-' + #$D83D + #$DE80 + '.rule');
    TFile.WriteAllBytes(MainRule, [$A3, 0, $B8, $FE]);
    TFile.WriteAllBytes(NestedRule, [1, 2, 3]);
    TFile.WriteAllBytes(TPath.Combine(Nested, 'short.rule'), [1]);
    TFile.WriteAllBytes(TPath.Combine(Root, 'cache.tmp'), [1, 2, 3, 4]);

    Paths := TDirectory.GetFiles(Root, '*.rule', TSearchOption.soTopDirectoryOnly);
    Check((Length(Paths) = 1) and (Paths[0] = MainRule), 'breadth-directory-rules-top-scan-keeps-unicode-basename');
    Paths := TDirectory.GetFiles(Root, '*.rule', TSearchOption.soAllDirectories);
    Check(Length(Paths) = 3, 'breadth-directory-rules-pattern-descends-through-subdirectory');
    MinSize := OpaqueI(3);
    RejectedShort := False;
    Predicate :=
      function(const Folder: string; const Entry: TSearchRec): Boolean
      begin
        Result := Entry.Size >= MinSize;
        If (Entry.Name = 'short.rule') and not Result then
          RejectedShort := True;
      end;
    Paths := TDirectory.GetFiles(Root, '*.rule', TSearchOption.soAllDirectories, Predicate);
    Check(RejectedShort and BreadthDirectoryHasPair(Paths, MainRule, NestedRule),
      'breadth-directory-rules-closure-filters-recursive-results-using-file-size');
    TFile.Move(MainRule, MovedRule);
    Bytes := TFile.ReadAllBytes(MovedRule);
    Check((Length(Bytes) = 4) and (Bytes[0] = $A3) and (Bytes[1] = 0) and (Bytes[2] = $B8) and (Bytes[3] = $FE),
      'breadth-directory-rules-renamed-file-keeps-exact-payload');
    Paths := TDirectory.GetFiles(Root, '*.rule', TSearchOption.soAllDirectories, Predicate);
    Check(BreadthDirectoryHasPair(Paths, NestedRule, MovedRule), 'breadth-directory-rules-rescan-returns-new-full-path');
    Mix(UInt64(Length(Paths) * 16 + Length(Bytes)));
  finally
    TDirectory.Delete(Root, True);
  end;
end;
{$ifend}
