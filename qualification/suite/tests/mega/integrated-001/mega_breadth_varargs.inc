{ Native C varargs use different call rules from Pascal open arrays. }

{$ifdef MSWINDOWS}
function BreadthCPrint(Buffer: PAnsiChar; Count: NativeUInt; Pattern: PAnsiChar): Integer;
  cdecl; varargs; external 'msvcrt.dll' name '_snprintf';
{$else}
function BreadthCPrint(Buffer: PAnsiChar; Count: NativeUInt; Pattern: PAnsiChar): Integer;
  cdecl; varargs; external 'c' name 'snprintf';
{$endif}

procedure RunBreadthCVarargs;
const
  MixedPattern: AnsiString = '%.0f|%lld|%s|%u|%.0f|%c';
  FloatPattern: AnsiString = '%.0f/%.0f/%.0f/%.0f/%.0f/%.0f/%.0f/%.0f/%.0f';
  MixedExpected: AnsiString = '-325|-3000000521|amber|3000000722|595|X';
  FloatExpected: AnsiString = '13/-17/23/-31/47/-53/61/-79/83';
var
  Buffer: array[0..127] of AnsiChar;
  WordArg, Printed: AnsiString;
  First: Single;
  Count: Integer;
begin
  WordArg := AnsiString('am' + Copy('amber', Integer(OpaqueI(3)), 3));
  First := OpaqueD(-325.0);
  Count := BreadthCPrint(@Buffer[0], SizeOf(Buffer), PAnsiChar(MixedPattern), First,
    OpaqueI(-3000000521), PAnsiChar(WordArg), Cardinal(OpaqueI(3000000722)), OpaqueD(595.0), Byte(OpaqueI(Ord('X'))));
  Check(Count = Length(MixedExpected), 'breadth-c-varargs-mixed-byte-count');
  If (Count >= 0) and (Count < SizeOf(Buffer)) then begin
    SetString(Printed, PAnsiChar(@Buffer[0]), Count);
    Check(Buffer[Count] = #0, 'breadth-c-varargs-mixed-terminator');
  end;
  Check(Printed = MixedExpected, 'breadth-c-varargs-mixed-argument-order');
  Mix(UInt64(Length(Printed)));

  Count := BreadthCPrint(@Buffer[0], SizeOf(Buffer), PAnsiChar(FloatPattern), OpaqueD(13.0), OpaqueD(-17.0),
    OpaqueD(23.0), OpaqueD(-31.0), OpaqueD(47.0), OpaqueD(-53.0), OpaqueD(61.0), OpaqueD(-79.0), OpaqueD(83.0));
  Check(Count = Length(FloatExpected), 'breadth-c-varargs-floating-byte-count');
  Printed := '';
  If (Count >= 0) and (Count < SizeOf(Buffer)) then
    SetString(Printed, PAnsiChar(@Buffer[0]), Count);
  Check(Printed = FloatExpected, 'breadth-c-varargs-floating-spills-preserve-order');
  Mix(UInt64(Length(Printed)));
end;
