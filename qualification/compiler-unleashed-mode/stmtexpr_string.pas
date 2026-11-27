program stmtexpr_string;

{ An if / case expression whose branches are string constants has the type
  of `string`. It was a ShortString: cut at 255 characters, and in a Unicode
  string profile every non-ASCII character went through the ANSI code page. }
{$mode unleashed}

const
  Long300 = '012345678901234567890123456789012345678901234567890123456789' +
    '012345678901234567890123456789012345678901234567890123456789' +
    '012345678901234567890123456789012345678901234567890123456789' +
    '012345678901234567890123456789012345678901234567890123456789' +
    '012345678901234567890123456789012345678901234567890123456789';

var
  Flag: Boolean;
  S, L, C: string;
begin
  Flag := ParamCount = 0;
  S := if Flag then '한글' else 'other';
  L := if Flag then Long300 else 'short';
  C := case Ord(Flag) of 0: 'zero'; 1: '하나'; else 'many';
  WriteLn(Length(S), ' ', Ord(S[1]), ' ', Length(L), ' ', Length(C), ' ', Ord(C[2]));
end.