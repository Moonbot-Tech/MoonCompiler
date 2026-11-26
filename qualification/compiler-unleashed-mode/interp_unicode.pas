program interp_unicode;

{ An interpolated string with arguments has the type of `string`. It was
  built in an AnsiString, so in a Unicode string profile every non-ASCII
  fragment went through the ANSI code page. }
{$mode unleashed}

var
  N: Integer;
  S: string;
begin
  N := 5;
  S := $'{N}건 조회했습니다.';
  WriteLn(Length(S), ' ', Ord(S[2]), ' ', Ord(S[10]));
end.
