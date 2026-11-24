{ Fluent builder calls mutate one receiver while prior UTF-16 snapshots remain independent. }

type
  TBreadthUnicodeBuilder = {$ifdef FPC}TUnicodeStringBuilder{$else}TStringBuilder{$endif};

procedure RunBreadthUnicodeBuilder;
const
  OriginalPrefix: array[0..3] of Word = ($03A9, 0, $D834, $DD1E);
  EditedUnits: array[0..6] of Word = ($005E, $221A, 0, $D834, $DD1E, $0023, $0021);
var
  Builder, Alias: TBreadthUnicodeBuilder;
  Original, Edited, SliceText: UnicodeString;
begin
  Builder := TBreadthUnicodeBuilder.Create(1);
  try
    Alias := Builder.Append(WideChar($03A9)).Append(WideChar(0)).Append(WideChar($D834)).Append(WideChar($DD1E));
    Alias := Alias.Append(OpaqueI(-90000000017));
    Check((Alias = Builder) and (Builder.Length = 16), 'breadth-unicode-builder-fluent-growth-keeps-receiver');
    Original := Alias.ToString;
    Check((Length(Original) = 16) and CompareMem(Pointer(Original), @OriginalPrefix[0], SizeOf(OriginalPrefix))
      and (Copy(Original, 5, 12) = '-90000000017'), 'breadth-unicode-builder-dispatches-wide-char-and-int64-overloads');

    Alias := Builder.Remove(Integer(OpaqueI(4)), Integer(OpaqueI(12)))
      .Insert(Integer(OpaqueI(0)), UnicodeString('^')).Append(WideChar('#'), 2);
    Alias.Chars[Integer(OpaqueI(1))] := WideChar($221A);
    Alias.Replace(WideChar('#'), WideChar('!'), Integer(OpaqueI(6)), 1);
    Edited := Builder.ToString;
    Check((Alias = Builder) and (Length(Edited) = Length(EditedUnits))
      and CompareMem(Pointer(Edited), @EditedUnits[0], SizeOf(EditedUnits)), 'breadth-unicode-builder-edits-exact-code-unit-range');
    SliceText := Builder.ToString(Integer(OpaqueI(1)), Integer(OpaqueI(4)));
    Check((Length(SliceText) = 4) and CompareMem(Pointer(SliceText), @EditedUnits[1], 4 * SizeOf(Word)),
      'breadth-unicode-builder-sliced-result-includes-embedded-zero');
    Builder.Clear;
    Check((Builder.Length = 0) and (Length(Edited) = 7) and (Length(Original) = 16)
      and CompareMem(Pointer(Edited), @EditedUnits[0], SizeOf(EditedUnits))
      and CompareMem(Pointer(Original), @OriginalPrefix[0], SizeOf(OriginalPrefix))
      and (Copy(Original, 5, 12) = '-90000000017'),
      'breadth-unicode-builder-clearing-buffer-preserves-earlier-results');
    Mix(UInt64(Length(Edited) * 32 + Length(Original)));
  finally
    Builder.Free;
  end;
end;
