{$ifdef BREADTH_HAS_PRODUCT_IO}
{ A downloaded feed's name is filtered before the import queue sees it. }

procedure RunBreadthImportFileMask;
var
  Mask: TMask;
  Accepted: Integer;
begin
  Mask := TMask.Create('feed-*-*[0-8][!9].rule');
  try
    Accepted := Ord(Mask.Matches('feed-' + #$03BB + '-red-07.RULE'));
    Inc(Accepted, Ord(Mask.Matches('FEED-BLUE-replay-88.rule')));
    Check(Accepted = 2, 'breadth-import-mask-accepts-unicode-and-folds-ascii-in-two-wildcard-groups');
    Check(not Mask.Matches('feed-red-blue-97.rule'), 'breadth-import-mask-positive-range-rejects-outside-digit');
    Check(not Mask.Matches('feed-red-blue-19.rule'), 'breadth-import-mask-negated-set-rejects-terminal-digit');
    Check(not Mask.Matches('feed-red-blue-01.rule.bak'), 'breadth-import-mask-anchors-extension-at-end-of-file-name');
    Mix(UInt64(Accepted));
  finally
    Mask.Free;
  end;
end;
{$endif}
