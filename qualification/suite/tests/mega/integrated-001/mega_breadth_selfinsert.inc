{ Self insertion reads the original UTF-16 span before it changes the destination. }

procedure RunBreadthSelfInsert;
const
  Original: array[0..4] of Word = ($221A, 0, $D834, $DD1E, $006D);
  Inserted: array[0..9] of Word = ($221A, 0, $221A, 0, $D834, $DD1E, $006D, $D834, $DD1E, $006D);
  Deleted: array[0..6] of Word = ($221A, 0, $221A, $006D, $D834, $DD1E, $006D);
  UniqueResult: array[0..9] of Word = ($221A, 0, $D834, $DD1E, $221A, 0, $D834, $DD1E, $006D, $006D);
var
  Text, Shared, Saved: UnicodeString;
begin
  SetLength(Text, Length(Original));
  Move(Original[0], Text[1], SizeOf(Original));
  Shared := Text;
  Insert(Text, Text, Integer(OpaqueI(3)));
  Check((Length(Text) = Length(Inserted)) and CompareMem(Pointer(Text), @Inserted[0], SizeOf(Inserted)),
    'breadth-unicode-self-insertion-snapshots-overlapping-source');
  Check((Length(Shared) = Length(Original)) and CompareMem(Pointer(Shared), @Original[0], SizeOf(Original)),
    'breadth-unicode-self-insertion-leaves-shared-source-intact');
  Saved := Text;
  Delete(Text, Integer(OpaqueI(4)), Integer(OpaqueI(3)));
  Check((Length(Text) = Length(Deleted)) and CompareMem(Pointer(Text), @Deleted[0], SizeOf(Deleted)),
    'breadth-unicode-delete-after-self-insertion-keeps-code-unit-order');
  Check((Length(Saved) = Length(Inserted)) and CompareMem(Pointer(Saved), @Inserted[0], SizeOf(Inserted)),
    'breadth-unicode-delete-leaves-prior-inserted-result-intact');

  Insert(Shared, Shared, Integer(OpaqueI(5)));
  Check((Length(Shared) = Length(UniqueResult)) and CompareMem(Pointer(Shared), @UniqueResult[0], SizeOf(UniqueResult)),
    'breadth-unicode-self-insertion-on-unique-buffer');
  Mix(UInt64(Length(Shared) * 16 + Length(Text)));
end;
