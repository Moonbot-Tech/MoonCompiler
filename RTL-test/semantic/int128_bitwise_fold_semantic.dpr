program int128_bitwise_fold_semantic;

{ 128-bit bitwise constant folds must combine the full payload.

  The red form (audit PERF/Devil dvl-0011): the Tconstexprint and/or/xor
  operators work on the low 64-bit lane and then rebuild the high half from
  the sign bit of the result's low half.  For genuine 128-bit operands with
  zero high halves that invented $FFFFFFFFFFFFFFFF up top:
  Int128(1) xor Int128($8000000000000000) folded with high = -1.
  The node-level fold now routes 128-bit result types through lane-exact
  and128/or128/xor128, the same split shl/shr already had.  The runtime
  neighbours pin that folded and non-folded forms agree. }

{$mode delphiunicode}{$H+}
{$Q-}{$R-}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}cthreads,cwstring,{$endif UNIX}
  SysUtils;

var
  Fails: Integer = 0;
  RS: array[0..3] of Int128;
  RU: array[0..3] of UInt128;

procedure Chk(const Name: string; const V: Int128; HiW, LoW: UInt64);
begin
  if (UInt64(V shr 64) <> HiW) or (UInt64(V and High(UInt64)) <> LoW) then
  begin
    WriteLn('FAIL ', Name, ' hi=', IntToHex(UInt64(V shr 64), 16),
      ' lo=', IntToHex(UInt64(V and High(UInt64)), 16));
    Inc(Fails);
  end;
end;

procedure ChkU(const Name: string; const V: UInt128; HiW, LoW: UInt64);
begin
  if (UInt64(V shr 64) <> HiW) or (UInt64(V and High(UInt64)) <> LoW) then
  begin
    WriteLn('FAIL ', Name, ' hi=', IntToHex(UInt64(V shr 64), 16),
      ' lo=', IntToHex(UInt64(V and High(UInt64)), 16));
    Inc(Fails);
  end;
end;

begin
  { the audit repro }
  Chk('xor-signbit', Int128(1) xor Int128($8000000000000000), 0, $8000000000000001);
  { folded matrix: and/or/xor, signed/unsigned, bit-63/64/127 boundaries }
  Chk('and-neg', Int128(-1) and Int128($00FF00FF00FF00FF), 0, $00FF00FF00FF00FF);
  Chk('or-signbit', Int128(0) or Int128($8000000000000000), 0, $8000000000000000);
  Chk('xor-neg-neg', Int128(-1) xor Int128(-2), 0, 1);
  Chk('and-neg-neg', Int128(-4) and Int128(-6), UInt64($FFFFFFFFFFFFFFFF), UInt64($FFFFFFFFFFFFFFF8));
  Chk('or-neg', Int128(-256) or Int128(1), UInt64($FFFFFFFFFFFFFFFF), UInt64($FFFFFFFFFFFFFF01));
  Chk('not-zero', not Int128(0), UInt64($FFFFFFFFFFFFFFFF), UInt64($FFFFFFFFFFFFFFFF));
  Chk('xor-hi-lane', (Int128(1) shl 127) xor (Int128(1) shl 64), UInt64($8000000000000001), 0);
  Chk('shl-cross', Int128(1) shl 100, UInt64($0000001000000000), 0);
  Chk('shl-signbit64', Int128($8000000000000000) shl 1, 1, 0);
  Chk('shr-cross', (Int128(1) shl 100) shr 36, 1, 0);
  ChkU('u-xor', UInt128(1) xor UInt128($8000000000000000), 0, $8000000000000001);
  ChkU('u-not', not UInt128(0), UInt64($FFFFFFFFFFFFFFFF), UInt64($FFFFFFFFFFFFFFFF));
  ChkU('u-and-max', (not UInt128(0)) and UInt128($1234), 0, $1234);

  { runtime neighbours: same values through memory, no folding }
  RS[1] := Int128(1);
  RS[2] := Int128($8000000000000000);
  RS[3] := Int128(-256);
  RU[1] := UInt128(1);
  RU[2] := UInt128($8000000000000000);
  Chk('rt-xor-signbit', RS[1] xor RS[2], 0, $8000000000000001);
  Chk('rt-or-signbit', Int128(0) or RS[2], 0, $8000000000000000);
  Chk('rt-or-neg', RS[3] or RS[1], UInt64($FFFFFFFFFFFFFFFF), UInt64($FFFFFFFFFFFFFF01));
  Chk('rt-and-neg', Int128(-1) and RS[2], 0, $8000000000000000);
  ChkU('rt-u-xor', RU[1] xor RU[2], 0, $8000000000000001);

  if Fails <> 0 then
    Halt(1);
  WriteLn('I128_BITWISE_SEMANTIC_OK');
end.
