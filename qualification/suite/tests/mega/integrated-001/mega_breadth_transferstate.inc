{ Transfer a snapshot, replace a keyed value, and transcode only a byte span. }

procedure RunBreadthThreadListSnapshot;
var
  Shared: TThreadList<UnicodeString>;
  Locked: TList<UnicodeString>;
  Snapshot: TArray<UnicodeString>;
  Topic: UnicodeString;
begin
  Topic := 'feed/' + WideChar(OpaqueI($03BB));
  Shared := TThreadList<UnicodeString>.Create;
  try
    Shared.Duplicates := dupIgnore;
    Shared.Add(Topic);
    Shared.Add(Topic);
    Shared.Add('tail');
    Locked := Shared.LockList;
    try
      Check((Locked.Count = 2) and (Locked[0] = Topic) and (Locked[1] = 'tail'),
        'breadth-thread-list-duplicate-policy-retains-order-in-locked-view');
      Snapshot := Locked.ToArray;
    finally
      Shared.UnlockList;
    end;
    Shared.Remove(Topic);
    Topic[1] := 'R';
    Shared.Add(Topic);
    Locked := Shared.LockList;
    try
      Check((Locked.Count = 2) and (Locked[0] = 'tail') and (Locked[1] = 'Reed/' + #$03BB),
        'breadth-thread-list-shared-view-reflects-replacement-and-order');
      Check((Length(Snapshot) = 2) and (Snapshot[0] = 'feed/' + #$03BB) and (Snapshot[1] = 'tail'),
        'breadth-thread-list-detached-snapshot-survives-mutation-and-release');
      Mix(UInt64(Length(Snapshot[0]) + Locked.Count));
    finally
      Shared.UnlockList;
    end;
  finally
    Shared.Free;
  end;
end;

procedure RunBreadthKeyedStrings;
var
  List: TStringList;
  Key, Value: string;
begin
  Key := 'signal';
  Value := string(WideChar(OpaqueI($03BB))) + ':wide';
  List := TStringList.Create;
  try
    List.NameValueSeparator := ':';
    List.CaseSensitive := False;
    List.Add('Market:BTC');
    List.Add('Signal:' + Value);
    List.Add('Tail:unchanged');
    Check((List.IndexOfName('SIGNAL') = 1) and (List.Values[Key] = Value),
      'breadth-keyed-strings-match-key-without-splitting-value-separator');
    List.ValueFromIndex[List.IndexOfName(Key)] := 'next:entry';
    Check((List.Count = 3) and (List.ValueFromIndex[1] = 'next:entry') and (List.Names[1] = 'Signal'),
      'breadth-keyed-strings-indexed-value-update-preserves-name-and-slot');
    List.Values[Key] := '';
    Check((List.Count = 2) and (List.IndexOfName(Key) = -1) and (List[0] = 'Market:BTC')
      and (List[1] = 'Tail:unchanged'), 'breadth-keyed-strings-delete-keeps-neighbor-entries-in-order');
    Mix(UInt64(List.Count));
  finally
    List.Free;
  end;
end;

procedure RunBreadthEncodingSpan;
const
  Wire: array[0..10] of Byte = ($FF, $FE, $41, 0, $CE, $BB, $F0, $9F, $98, $80, $FD);
  Expected: array[0..9] of Byte = (0, $41, 0, 0, 3, $BB, $D8, $3D, $DE, 0);
var
  Input, Converted: TBytes;
  Start, Count: Integer;
begin
  SetLength(Input, SizeOf(Wire));
  Move(Wire, Input[0], SizeOf(Wire));
  Start := Integer(OpaqueI(2));
  Count := Integer(OpaqueI(8));
  Converted := TEncoding.Convert(TEncoding.UTF8, TEncoding.BigEndianUnicode, Input, Start, Count);
  Check((Length(Converted) = SizeOf(Expected)) and CompareMem(@Converted[0], @Expected[0], SizeOf(Expected)),
    'breadth-encoding-span-transcodes-requested-byte-slice-with-no-preamble');
  Check((Input[0] = $FF) and (Input[1] = $FE) and (Input[High(Input)] = $FD),
    'breadth-encoding-span-leaves-neighboring-bytes-unmodified');
  Mix(UInt64(Length(Converted)));
end;
