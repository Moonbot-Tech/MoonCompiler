{ %CPU=i386,x86_64 }
{ %OPT=-O2 }

program tpeepholelealea1;

{$mode objfpc}

function RuntimeValue(AValue: PtrInt): PtrInt; noinline;
begin
  Result := AValue;
end;

procedure Check(const AName: ShortString; AActual, AExpected: PtrInt);
begin
  if AActual <> AExpected then
    begin
      WriteLn(AName, ': expected ', AExpected, ', got ', AActual);
      Halt(1);
    end;
end;

var
  S, T: PtrInt;
begin
  S := RuntimeValue(3);
  T := RuntimeValue(5);

  { Doubling an index-only LEA with scale 8 must not produce the invalid
    x86 scale 16. }
  Check('scale-16', S * 8 + S * 8, 48);

  { Doubling a LEA with two independent inputs cannot be represented by one
    LEA.  The old peephole transformation silently discarded S. }
  Check('base-index-2', (S + T * 2) + (S + T * 2), 26);
  Check('base-index-4', (S + T * 4) + (S + T * 4), 46);
  Check('base-index-8', (S + T * 8) + (S + T * 8), 86);

  { Neighbouring representable single-input forms remain legal. }
  Check('single-base', S + S, 6);
  Check('single-index-4', S * 4 + S * 4, 24);

  WriteLn('PEEPHOLE-LEA-LEA:PASS');
end.
