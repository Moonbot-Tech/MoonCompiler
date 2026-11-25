{ Reload a range of managed entries from a snapshot that can outlive the live list. }

type
  TBreadthListEntry = record
    Ticket: Int64;
    Text: UnicodeString;
    Owner: IBreadthTaggedOwner;
  end;

procedure BreadthSpliceManagedEntries;
var
  Live: TList<TBreadthListEntry>;
  Before: TArray<TBreadthListEntry>;
  Entry: TBreadthListEntry;
begin
  Live := TList<TBreadthListEntry>.Create;
  try
    Entry.Ticket := OpaqueI(-640000000009);
    Entry.Text := 'first' + #0 + #$03BB;
    Entry.Owner := TBreadthTaggedOwner.Create;
    Live.Add(Entry);
    Entry.Ticket := OpaqueI(740000000033);
    Entry.Text := 'second';
    Entry.Owner := TBreadthTaggedOwner.Create;
    Live.Add(Entry);
    Entry.Owner := nil;
    Before := Live.ToArray;
    Live.InsertRange(Integer(OpaqueI(1)), Before);
    Check((Live.Count = 4) and (Live[0].Ticket = -640000000009) and (Live[1].Ticket = -640000000009)
      and (Live[2].Ticket = 740000000033) and (Live[3].Ticket = 740000000033),
      'breadth-list-range-insertion-preserves-prefix-inserted-block-and-tail');
    Live.DeleteRange(0, 2);
    Check((Live.Count = 2) and (Live[0].Ticket = 740000000033) and (Live[1].Ticket = 740000000033),
      'breadth-list-range-deletion-compacts-managed-survivors');
    Entry := Live[0];
    Entry.Text[1] := 'S';
    Live[0] := Entry;
    Check((Live[0].Text = 'Second') and (Live[1].Text = 'second') and (Before[1].Text = 'second'),
      'breadth-list-range-replacement-detaches-text-from-other-copies');
  finally
    FreeAndNil(Live);
  end;
  Check((Length(Before) = 2) and (Before[0].Ticket = -640000000009) and (Before[0].Text = 'first' + #0 + #$03BB)
    and (Before[0].Owner <> nil) and (Before[1].Owner <> nil) and (Before[0].Owner <> Before[1].Owner)
    and (Before[0].Owner.Tag = 74000000051) and (Before[1].Owner.Tag = 74000000051)
    and (TBreadthTaggedOwner.Destroyed = 0), 'breadth-list-managed-snapshot-remains-valid-after-list-is-freed');
  Mix(UInt64(Before[0].Ticket) xor UInt64(Before[1].Ticket));
end;

procedure RunBreadthManagedListSplice;
begin
  TBreadthTaggedOwner.Destroyed := 0;
  BreadthSpliceManagedEntries;
  Check(TBreadthTaggedOwner.Destroyed = 2, 'breadth-list-snapshot-releases-both-owners-on-scope-exit');
end;
