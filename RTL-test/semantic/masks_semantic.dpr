program masks_semantic;

{$mode delphi}{$H+}

{ System.Masks: the Delphi wildcard mask surface (planning contract 2.4).
  Expected values are those of Delphi 12.2 - RTL-test/oracles/masks_oracle.dpr
  compares the two implementations over every mask of up to three atoms and
  every text of up to four letters - except where Delphi reads the #0 that
  terminates its strings as a character: a negated set at the end of the
  text ("aa[!a]" matches "aa" there), a #0 inside a text or a mask (the rest
  is cut off there).  Here the end of the text is not a character and #0 is
  one; those cases are listed at the end. }

uses
  SysUtils,
  System.Masks;

var
  Failures: Integer;

procedure Check(Cond: Boolean; const Msg: string);
begin
  If not Cond then begin
    Inc(Failures);
    WriteLn('FAIL ', Msg);
  end;
end;

procedure Expect(const Mask, Text: string; Want: Boolean);
var
  M: TMask;
  Got: Boolean;
begin
  Got := MatchesMask(Text, Mask);
  Check(Got = Want, Format('"%s" against "%s": got %s, want %s', [Text, Mask, BoolToStr(Got, True), BoolToStr(Want, True)]));
  { the compiled form gives the same answer and can be reused }
  M := TMask.Create(Mask);
  try
    Check(M.Matches(Text) = Want, Format('TMask "%s" against "%s"', [Mask, Text]));
    Check(M.Matches(Text) = Want, Format('TMask "%s" against "%s" again', [Mask, Text]));
  finally
    M.Free;
  end;
end;

procedure ExpectError(const Mask: string; WantPosition: Integer);
var
  M: TMask;
begin
  try
    M := TMask.Create(Mask);
    M.Free;
    Check(False, Format('mask "%s" accepted, wanted EMaskException', [Mask]));
  except
    on E: EMaskException do begin
      Check(Pos(Mask, E.Message) > 0, 'error names the mask: ' + E.Message);
      Check(Pos(IntToStr(WantPosition), E.Message) > 0, Format('error names position %d: %s', [WantPosition, E.Message]));
    end;
  end;
  { MatchesMask raises the same way; the caller decides that means "no match" }
  try
    MatchesMask('anything', Mask);
    Check(False, 'MatchesMask accepted the broken mask');
  except
    on EMaskException do ;
  end;
end;

var
  Stars: string;
  I: Integer;
begin
  Failures := 0;
  { the contract's table }
  Expect('*.dat', 'a.dat', True);
  Expect('?bc', 'abc', True);
  Expect('?bc', 'bc', False);
  Expect('[a-c]*', 'Bx', True);
  Expect('[!x]*', 'xa', False);
  Expect('*?', 'a', True);
  Expect('*?', '', True);
  Expect('ab*', 'AB', True);
  Expect('[' + #$0430#$0431#$0432 + ']*', #$0411, False);   { Cyrillic: no case folding above ASCII }
  { plain semantics }
  Expect('', '', True);
  Expect('', 'a', False);
  Expect('*', '', True);
  Expect('*', 'anything', True);
  Expect('**', 'ab', True);
  Expect('a*b', 'ab', True);
  Expect('a*b', 'axxxb', True);
  Expect('a*b', 'axxx', False);
  Expect('a*b*c', 'abc', True);
  Expect('a*b*c', 'aXbYc', True);
  Expect('a*b*c', 'acb', False);
  Expect('*.pas', 'unit.pas', True);
  Expect('*.pas', 'unit.pp', False);
  Expect('*.PAS', 'Unit.pas', True);
  Expect('???', 'abc', True);
  Expect('???', 'ab', False);
  Expect('???', 'abcd', False);
  Expect('a?c', 'abc', True);
  Expect('a?c', 'ac', False);
  Expect('[abc]', 'b', True);
  Expect('[abc]', 'B', True);
  Expect('[abc]', 'd', False);
  Expect('[!abc]', 'd', True);
  Expect('[!abc]', 'a', False);
  Expect('[0-9][0-9]', '42', True);
  Expect('[0-9][0-9]', '4x', False);
  Expect('[a-z]', 'M', True);
  Expect('BTC*USDT', 'btcusdt', True);
  Expect('*USDT', 'ETHUSDT', True);
  Expect('*USDT', 'ETHBUSD', False);
  Expect(#$0410#$0411 + '*', #$0410#$0411#$0412, True);     { non-ASCII literals match themselves }
  Expect(#$0410#$0411 + '*', #$0430#$0431#$0412, False);    { but not the other case }
  { a surrogate pair is one literal }
  Expect(#$D83D#$DE00 + '?', #$D83D#$DE00 + 'x', True);
  Expect(#$D83D#$DE00 + '?', #$D83D#$DE00, False);
  { errors, with the 1-based position }
  ExpectError('[', 2);               { the mask ends where a set is open: Length + 1 }
  ExpectError('a[', 3);
  ExpectError('[]', 2);              { the "]" of an empty set }
  ExpectError('[!]', 3);
  ExpectError('[-a]', 2);            { a range without a start }
  ExpectError('[a-]', 3);            { a range without an end (Delphi rejects it too) }
  ExpectError('[abc', 5);
  ExpectError('[a-', 3);
  { sets hold #0..#255 only: a Cyrillic member is dropped, not folded to its low byte }
  Expect('[' + #$0430 + ']', '0', False);
  Expect('[' + #$0430 + ']', #$0430, False);
  Expect('[!' + #$0430 + ']', #$0430, True);
  Expect('[!a]', #$0430, True);
  Expect('[a-' + #$0430 + ']', 'z', True);      { a range is clipped at #255 }
  Expect('[a-' + #$0430 + ']', #$00FF, True);
  Expect('[a-' + #$0430 + ']', #$0100, False);
  { the wildcard limit counts runs of "*", as Delphi does }
  Stars := '';
  for I := 1 to 30 do
    Stars := Stars + 'a*';
  Expect(Stars, StringOfChar('a', 30), True);   { 30 runs are fine }
  Expect(Stars, StringOfChar('a', 29), False);
  Expect(Stars + '*', StringOfChar('a', 30), True);   { "**" is still the 30th run }
  Expect(StringOfChar('*', 40), 'x', True);           { one run }
  ExpectError('*' + Stars, 61);      { the 31st run is not }
  ExpectError(Stars + 'a*', 62);
  { where Delphi's matcher reads its terminator as a character, this one does not }
  Expect('aa[!a]', 'aa', False);
  Expect('[!a]', '', False);
  Expect('a', 'a'#0'b', False);
  Expect('a'#0'b', 'a'#0'b', True);
  Expect('a?b', 'a'#0'b', True);
  Expect('', #0, False);
  If Failures <> 0 then
    Halt(1);
  WriteLn('MASKS_PASS');
end.
