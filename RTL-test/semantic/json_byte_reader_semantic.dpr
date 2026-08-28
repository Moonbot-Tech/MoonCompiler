program json_byte_reader_semantic;

{ R-007: TJSONByteReader growth and flush without the width bug.
  The old code grew an empty buffer by 2*0=0 and wrote FString[0] into a
  nil array (the first AddChar ever crashed), copied FStringLen BYTES of
  a WideChar payload on flush (half the string, garbage tail) and
  inverted a value-copy of aCache instead of any cache policy.
  DCC64 canvas (System.JSON source): FlushString = SetString + reset +
  dictionary interning gated by aCache AND input>1MB; growth is geometric.
  Our constructor stays zero-allocation: the buffer appears at the first
  AddChar, the dictionary at the first interned flush. }

{$mode delphiunicode}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}cthreads,cwstring,{$endif UNIX}
  SysUtils, System.JSON;

var
  Fails: Integer = 0;

procedure Check(const Name: AnsiString; Cond: Boolean);
begin
  if not Cond then
  begin
    WriteLn('FAIL ', Name);
    Inc(Fails);
  end;
end;

const
  SmallJSON: AnsiString = '{"k":"v"}';

var
  R: TJSONByteReader;
  S, S2: UnicodeString;
  Big: TBytes;
  I: Integer;
  Offset: Integer;
  V: TJSONValue;
begin
  { direct reader: first AddChar on the empty buffer, exact growth
    boundary at 16, ASCII/non-ASCII/surrogate pair, double flush }
  R := TJSONByteReader.Create(PByte(SmallJSON), 0, Length(SmallJSON));
  try
    R.AddChar('A');
    R.FlushString(S, False);
    Check('first-char', S = 'A');

    for I := 1 to 16 do
      R.AddChar(WideChar(Ord('a') + I - 1)); { crosses the 16 boundary }
    R.AddChar(#$0416);                        { Ж }
    R.AddChar(#$D83D);                        { surrogate pair D83D DE00 }
    R.AddChar(#$DE00);
    R.FlushString(S, False);
    Check('growth-and-width', (Length(S) = 19) and (S[1] = 'a') and (S[16] = 'p') and
      (S[17] = #$0416) and (S[18] = #$D83D) and (S[19] = #$DE00));

    { flush resets: the second flush is empty (DCC canvas) }
    R.FlushString(S2, False);
    Check('double-flush-empty', S2 = '');

    { reset then flush }
    R.AddChar('x');
    R.ResetString;
    R.FlushString(S, False);
    Check('reset-flush', S = '');

    { small input: aCache=True must NOT intern (gate is >1MB) }
    R.AddChar('q');
    R.FlushString(S, True);
    R.AddChar('q');
    R.FlushString(S2, True);
    Check('small-no-intern', (S = 'q') and (S2 = 'q') and
      (Pointer(S) <> Pointer(S2)));
  finally
    R.Free;
  end;

  { large input: aCache=True interns - the same content comes back as the
    same string instance }
  SetLength(Big, 1100000);
  FillChar(Big[0], Length(Big), Ord(' '));
  R := TJSONByteReader.Create(PByte(Big), 0, Length(Big));
  try
    R.AddChar('k');
    R.AddChar('1');
    R.FlushString(S, True);
    R.AddChar('k');
    R.AddChar('1');
    R.FlushString(S2, True);
    Check('intern-same-instance', (S = 'k1') and (Pointer(S) = Pointer(S2)));
    R.AddChar('k');
    R.AddChar('1');
    R.FlushString(S2, False);
    Check('no-cache-flag-new-instance', (S2 = 'k1') and (Pointer(S) <> Pointer(S2)));
  finally
    R.Free;
  end;

  { the public parse path end to end; the Unicode facade now runs the
    scanner in UTF-8 mode, so a \u escape above $7F survives (it used to
    decay to U+FFFD because the facade encoded UTF-8 but never told the
    scanner) }
  V := TJSONValue.ParseJSONValue(UnicodeString('{"name":"\u0416\u0435\u0441\u0442"}'));
  try
    Check('parse-value', (V <> nil) and
      (V.GetValue<UnicodeString>('name') = #$0416#$0435#$0441#$0442));
  finally
    V.Free;
  end;

  { ParseJSONFragment returns an absolute byte offset, not a position
    relative to the non-zero starting offset.  The Unicode facade keeps the
    same byte-oriented contract after its UTF-8 conversion. }
  S := '  1 {"k":"' + #$0416 + '"} true';
  Big := TEncoding.UTF8.GetBytes(S);
  Offset := 2;
  V := TJSONValue.ParseJSONFragment(Big, Offset,
    [TJSONValue.TJSONParseOption.IsUTF8,
     TJSONValue.TJSONParseOption.RaiseExc]);
  try
    Check('fragment-first-offset', (V <> nil) and (V.ToJSON = '1') and
      (Offset = 3));
  finally
    V.Free;
  end;
  V := TJSONValue.ParseJSONFragment(Big, Offset,
    [TJSONValue.TJSONParseOption.IsUTF8,
     TJSONValue.TJSONParseOption.RaiseExc]);
  try
    Check('fragment-object-offset', (V <> nil) and
      (V.GetValue<UnicodeString>('k') = #$0416) and (Offset = 14));
  finally
    V.Free;
  end;
  V := TJSONValue.ParseJSONFragment(Big, Offset,
    [TJSONValue.TJSONParseOption.IsUTF8,
     TJSONValue.TJSONParseOption.RaiseExc]);
  try
    Check('fragment-final-offset', (V <> nil) and
      (V.ToJSON = 'true') and (Offset = 19));
  finally
    V.Free;
  end;

  if Fails <> 0 then
    Halt(1);
  WriteLn('JSON_BYTE_READER_OK');
end.
