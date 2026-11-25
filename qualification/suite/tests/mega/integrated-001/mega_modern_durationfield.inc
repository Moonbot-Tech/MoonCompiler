{$ifdef BREADTH_HAS_PRODUCT_IO}
{ Read precision and arithmetic for a serialized duration field. }

procedure RunBreadthDurationField;
const
  Stored = '1.03:04:05.0067891';
  StoredTicks = Int64(974450067891);
var
  Parsed, Restored, Delta, Total: TTimeSpan;
begin
  Check(TTimeSpan.TryParse(Stored, Parsed) and (Parsed.Ticks = StoredTicks),
    'breadth-duration-field-keeps-seven-fractional-digits');
  Check((Parsed.Days = 1) and (Parsed.Hours = 3) and (Parsed.Minutes = 4) and (Parsed.Seconds = 5)
    and (Parsed.Milliseconds = 6), 'breadth-duration-field-reports-normalized-components');
  Delta := TTimeSpan.FromMilliseconds(OpaqueI(125));
  Total := Parsed + Delta;
  Check((Delta.Ticks = 1250000) and (Total.Ticks = 974451317891),
    'breadth-duration-field-adds-backoff-in-ticks-without-rounding-original');
  Restored := Total - Delta;
  Check((Restored.Ticks = StoredTicks) and (Restored.ToString = Stored),
    'breadth-duration-field-reversible-change-preserves-wire-format');
  Mix(UInt64(Restored.Ticks));
end;
{$endif}
