program tdynarraysetlengthroute1;

{$mode delphi}
{$H+}

{ SetLength of a dynamic array has two routines in the RTL: fpc_dynarray_setlength_record, the
  transactional one for records, objects and static arrays with managed contents (they may have a
  custom Initialize or Copy operator), and fpc_dynarray_setlength for every other element type.
  The compiler knows the element type, so it calls the right one directly; the ASM verifier of the
  focused repair gate checks the call in each of the routines below.  At run time every kind of
  array must behave the same whichever routine served it. }

type
  TPlainRecord = record
    A, B: Integer;
  end;

  TManagedRecord = record
    Name: string;
    Value: Integer;
  end;

  TStringPair = array[0..1] of string;

  TDoubles = array of Double;
  TStrings = array of string;
  TPlainRecords = array of TPlainRecord;
  TManagedRecords = array of TManagedRecord;
  TStringPairs = array of TStringPair;
  TNestedRecords = array of array of TManagedRecord;

procedure Fail(Code: Integer);
begin
  WriteLn('FAIL ', Code);
  Halt(Code);
end;

procedure SetDoubles(var Values: TDoubles; Count: Integer);
begin
  SetLength(Values, Count);
end;

procedure SetStrings(var Values: TStrings; Count: Integer);
begin
  SetLength(Values, Count);
end;

procedure SetPlainRecords(var Values: TPlainRecords; Count: Integer);
begin
  SetLength(Values, Count);
end;

procedure SetManagedRecords(var Values: TManagedRecords; Count: Integer);
begin
  SetLength(Values, Count);
end;

procedure SetStringPairs(var Values: TStringPairs; Count: Integer);
begin
  SetLength(Values, Count);
end;

procedure SetNestedRecords(var Values: TNestedRecords; Outer, Inner: Integer);
begin
  SetLength(Values, Outer, Inner);
end;

function BuildManagedRecords(const First, Second: TManagedRecord): TManagedRecords;
begin
  Result := [First, Second];
end;

var
  D: TDoubles;
  S: TStrings;
  P: TPlainRecords;
  M, M2, Built: TManagedRecords;
  Pairs: TStringPairs;
  N: TNestedRecords;
  Text: string;
  R1, R2: TManagedRecord;
begin
  Text := 'text';
  Text := Text + Text;

  SetDoubles(D, 8);
  if (Length(D) <> 8) or (D[7] <> 0) then
    Fail(1);
  D[7] := 1.5;
  SetDoubles(D, 100);
  if (D[7] <> 1.5) or (D[99] <> 0) then
    Fail(2);

  SetStrings(S, 4);
  S[3] := Text;
  SetStrings(S, 50);
  if (S[3] <> Text) or (S[49] <> '') then
    Fail(3);

  SetPlainRecords(P, 3);
  P[2].B := 7;
  SetPlainRecords(P, 30);
  if (P[2].B <> 7) or (P[29].A <> 0) then
    Fail(4);

  SetManagedRecords(M, 3);
  if (M[2].Name <> '') or (M[2].Value <> 0) then
    Fail(5);
  M[2].Name := Text;
  M[2].Value := 9;
  M2 := M;
  SetManagedRecords(M, 40);
  if (Length(M2) <> 3) or (M2[2].Name <> Text) or (M[2].Name <> Text) or (M[2].Value <> 9) or
     (M[39].Name <> '') then
    Fail(6);
  SetManagedRecords(M, 1);
  if (Length(M) <> 1) or (M2[2].Name <> Text) then
    Fail(7);

  SetStringPairs(Pairs, 2);
  Pairs[1][1] := Text;
  SetStringPairs(Pairs, 20);
  if (Pairs[1][1] <> Text) or (Pairs[19][0] <> '') then
    Fail(8);

  SetNestedRecords(N, 2, 3);
  N[1][2].Name := Text;
  SetNestedRecords(N, 4, 5);
  if (Length(N) <> 4) or (Length(N[3]) <> 5) or (N[1][2].Name <> Text) or (N[3][4].Name <> '') then
    Fail(9);

  R1.Name := Text;
  R1.Value := 1;
  R2.Name := 'second';
  R2.Value := 2;
  Built := BuildManagedRecords(R1, R2);
  if (Length(Built) <> 2) or (Built[0].Name <> Text) or (Built[1].Value <> 2) then
    Fail(10);

  WriteLn('ok');
end.
