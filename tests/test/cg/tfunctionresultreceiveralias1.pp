{ %OPT=-O3 }
program tfunctionresultreceiveralias1;

{$mode delphiunicode}

uses SysUtils;

procedure Check(Condition: Boolean);
begin
  If not Condition then Halt(1);
end;

procedure IndependentSource(const Source: UnicodeString);
var
  Dest: TUnicodeStringArray;
  I: Integer;
begin
  for I := 0 to 1 do Dest := Source.Split([',']);
  Check((Length(Dest)=3) and (Dest[0]='a') and (Dest[1]='b') and (Dest[2]='c'));
end;

procedure ReceiverAlias;
const
  Indexes: array[0..1] of Integer = (0,20);
var
  A, Saved: TUnicodeStringArray;
  I, J, Index: Integer;
  Shared: Boolean;
begin
  for Shared in [False,True] do
    for Index in Indexes do
    begin
      Saved := nil;
      SetLength(A,32);
      for I := 0 to High(A) do A[I] := 'retained-'+IntToStr(I);
      { The only owner of the receiver's heap buffer is the destination. }
      SetLength(A[Index],261);
      A[Index][1] := 'a';
      A[Index][2] := ',';
      for J := 3 to 258 do A[Index][J] := 'b';
      A[Index][259] := ',';
      A[Index][260] := 'c';
      A[Index][261] := 'd';
      If Shared then Saved := A;
      A := A[Index].Split([',']);
      Check(Length(A)=3);
      Check((A[0]='a') and (A[1]=StringOfChar('b',256)) and (A[2]='cd'));
      If Shared then
      begin
        Check(Length(Saved)=32);
        Check(Length(Saved[Index])=261);
        for I := 0 to High(Saved) do
          If I<>Index then Check(Saved[I]='retained-'+IntToStr(I));
      end;
    end;
  IndependentSource('a,b,c');
end;

begin
  ReceiverAlias;
  Writeln('OK');
end.
