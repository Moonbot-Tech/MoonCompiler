program id_strings;

{ Identity-gate workload: strings, dynamic arrays, COW, concatenation.
  Prints a deterministic digest. }

{$mode delphi}

var
  S, T: AnsiString;
  U: UnicodeString;
  A: array of Integer;
  i, acc: Integer;
begin
  S := 'hello';
  T := S;
  S[1] := 'H';
  U := 'world';
  U[5] := 'D';
  SetLength(A, 64);
  for i := 0 to High(A) do
    A[i] := i * 3;
  acc := 0;
  for i := 0 to High(A) do
    acc := acc + A[i];
  S := S + '-' + T;
  WriteLn('strings:', S, ':', U, ':', acc, ':', Length(S) + Length(U));
end.
