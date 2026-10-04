program uint64_shl_const_compare_deferred;

{$mode delphi}{$H+}

{ Deferred compiler differential, found 2026-09-21 while writing the
  TLightweightMREW test.  A constant expression built from UInt64 casts and
  shl/or folds as a signed Int64: (UInt64(1) shl 3) or (UInt64(1) shl 63) is
  reported as -9223372036854775800 with a range-check warning, and a
  comparison of a UInt64 variable with that constant is folded to "always
  false" (warning "Comparison might be always false") - the branch is never
  taken although the bits are equal.  Delphi types UInt64(1) shl 63 as
  UInt64 and the comparison is True.  The assignment of the same constant to
  a UInt64 variable keeps the right bits, so only the comparison miscompiles.
  Expected: UINT64_SHL_CONST_OK; MoonCompiler currently prints the FAIL. }

var
  V: UInt64;
begin
  V := UInt64($8000000000000008);
  If V = (UInt64(1) shl 3) or (UInt64(1) shl 63) then
    WriteLn('UINT64_SHL_CONST_OK')
  else begin
    WriteLn('FAIL: UInt64 variable compared with a folded UInt64 shl/or constant');
    Halt(1);
  end;
end.
