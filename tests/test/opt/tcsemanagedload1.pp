{ %OPT=-O3 }

program tcsemanagedload1;

{$mode delphi}

type
  TValues = array of QWord;

  TManagedPair = record
    Text: AnsiString;
  end;

threadvar
  ThreadText: AnsiString;

function ArrayProduct(const Values: TValues; I, J: LongInt): QWord; noinline;
var
  LocalValues: TValues;
begin
  LocalValues := Values;
  Result := LocalValues[I] * LocalValues[J];
end;

function TextProduct(const Value: AnsiString; I, J: LongInt): QWord; noinline;
var
  LocalValue: AnsiString;
begin
  LocalValue := Value;
  Result := Ord(LocalValue[I]) * Ord(LocalValue[J]);
end;

function RecordTextProduct(const Value: TManagedPair;
  I, J: LongInt): QWord; noinline;
var
  LocalValue: TManagedPair;
begin
  LocalValue := Value;
  Result := Ord(LocalValue.Text[I]) * Ord(LocalValue.Text[J]);
end;

function ThreadTextProduct(I, J: LongInt): QWord; noinline;
begin
  Result := Ord(ThreadText[I]) * Ord(ThreadText[J]);
end;

var
  Digest: QWord;
  I: LongInt;
  Pair: TManagedPair;
  Text: AnsiString;
  Values: TValues;
begin
  SetLength(Values, 4);
  Values[0] := 3;
  Values[1] := 5;
  Values[2] := 7;
  Values[3] := 11;
  Text := 'abcdef';
  Pair.Text := Text;
  ThreadText := Text;

  Digest := 0;
  for I := 1 to 64 do
  begin
    Inc(Digest, ArrayProduct(Values, 0, 3));
    Inc(Digest, ArrayProduct(Values, 1, 2));
    Inc(Digest, TextProduct(Text, 2, 5));
    Inc(Digest, TextProduct(Text, 1, 6));
    Inc(Digest, RecordTextProduct(Pair, 2, 5));
    Inc(Digest, ThreadTextProduct(2, 5));
  end;

  if (Digest <> 2537984) or
     (Length(Values) <> 4) or (Values[3] <> 11) or
     (Text <> 'abcdef') or (Pair.Text <> 'abcdef') then
    Halt(1);
  WriteLn('CSE-MANAGED-LOAD:PASS:', Digest);
end.
