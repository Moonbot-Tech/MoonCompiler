{ HTML encode kernel instantiated for one-byte and two-byte strings.
  Source is an explicit span: embedded NUL is data. }

function HTMLSPAN_ENCODE(Src: HTMLSPAN_PCHAR; Len: SizeInt;
  out Changed: Boolean): HTMLSPAN_STRING;

var
  I, Extra, Delta, OutLen: SizeInt;
  D: HTMLSPAN_PCHAR;

  procedure PutLiteral(const S: RawByteString);
  var
    J: SizeInt;
  begin
    for J := 1 to Length(S) do
    begin
      D^ := HTMLSPAN_CHAR(S[J]);
      Inc(D);
    end;
  end;

begin
  Result := '';
  Extra := 0;
  for I := 0 to Len - 1 do
  begin
    case Src[I] of
      '&': Delta := 4;      { &amp; }
      '<', '>': Delta := 3; { &lt; and &gt; }
      '"': Delta := 5;      { &quot; }
    else
      Delta := 0;
    end;
    if Delta > High(SizeInt) - Len - Extra then
      OutOfMemoryError;
    Inc(Extra,Delta);
  end;
  Changed := Extra <> 0;
  if not Changed then
    Exit;
  OutLen := Len + Extra;
  SetLength(Result, OutLen);
  D := HTMLSPAN_PCHAR(Pointer(Result));
  for I := 0 to Len - 1 do
    case Src[I] of
      '&': PutLiteral('&amp;');
      '<': PutLiteral('&lt;');
      '>': PutLiteral('&gt;');
      '"': PutLiteral('&quot;');
    else
      begin
        D^ := Src[I];
        Inc(D);
      end;
    end;
end;
