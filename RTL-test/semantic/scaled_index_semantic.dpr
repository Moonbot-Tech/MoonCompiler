program scaled_index_semantic;

{ The element of an array of records whose size is 3, 5 or 9 times 2, 4 or 8:
  the index is multiplied by LEA and a shift, and the shift goes into the
  scale of the address of the load which follows (x86 peephole,
  OptPass1SHLSAL, "ShlOp2Op").  The rule asked whether the register of the
  index is used behind the load and took the register for used where the
  load itself writes it: "lea (%rax,%rax,4),%rax; shl $3,%rax;
  mov 40(%rcx,%rax),%eax" kept its shift.  A load which writes the whole
  register of the index leaves no reader of the shifted value.

  The forms: fields of 1, 2, 4 and 8 bytes read into the register of the
  index, the address of the element, sizes of the element from 6 to 72 bytes,
  the index read again behind the load, a load of one byte which leaves the
  rest of the register alone.

  The values are those of Delphi 12.2 and of -O1. }

{$mode delphi}{$H+}
{$Q-}{$R-}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  cwstring,
  {$endif UNIX}
  SysUtils;

type
  { 40 bytes: 5 * 8 }
  TMark = record
    I: Cardinal;
    Cp: PAnsiChar;
    Pp: Pointer;
    Level: Byte;
    Cl: Cardinal;
    Removed: Cardinal;
  end;

  { 6 bytes: 3 * 2 }
  TSix = packed record
    A: Word;
    B: Cardinal;
  end;

  { 12 bytes: 3 * 4 }
  TTwelve = record
    A, B, C: Cardinal;
  end;

  { 20 bytes: 5 * 4 }
  TTwenty = record
    A, B, C, D, E: Cardinal;
  end;

  { 24 bytes: 3 * 8 }
  TTwentyFour = record
    A, B, C: Int64;
  end;

  { 72 bytes: 9 * 8 }
  TSeventyTwo = record
    A: array[0..7] of Int64;
    B: Int64;
  end;

var
  Fails: Integer = 0;
  Sixes: array[0..9] of TSix;
  Twelves: array[0..9] of TTwelve;
  Twenties: array[0..9] of TTwenty;
  TwentyFours: array[0..9] of TTwentyFour;
  SeventyTwos: array[0..9] of TSeventyTwo;

procedure Check(Got, Want: Int64; const Name: string);
begin
  if Got <> Want then
  begin
    WriteLn('FAIL ', Name, ': ', Got, ' <> ', Want);
    Inc(Fails);
  end;
end;

function Walk(Base: PAnsiChar; Seed: Cardinal): Int64; noinline;
var
  History: array[0..24] of TMark;
  Top: Integer;
  I, Cl, Removed: Cardinal;
  Cp, Ps: PAnsiChar;
  Pp: Pointer;
  Level: Byte;

  procedure GoBack;
  begin
    I := History[Top].I;
    Cp := History[Top].Cp;
    Cl := History[Top].Cl;
    Pp := History[Top].Pp;
    Level := History[Top].Level;
    Removed := History[Top].Removed;
    Ps := Base + (I - 1);
    Dec(Top);
  end;

  procedure Push;
  begin
    Inc(Top);
    History[Top].I := I;
    History[Top].Cp := Cp;
    History[Top].Cl := Cl;
    History[Top].Pp := Pp;
    History[Top].Level := Level;
    History[Top].Removed := Removed;
  end;

var
  K: Integer;
begin
  Top := -1;
  I := Seed;
  Cl := 2;
  Cp := Base;
  Pp := @History;
  Level := 1;
  Removed := 0;
  for K := 1 to 5 do
    begin
      Push;
      Inc(I, 3);
      Inc(Cl);
      Inc(Cp);
      Inc(Level);
      Inc(Removed, 2);
    end;
  GoBack;
  GoBack;
  Result := Int64(I) * 1000000 + Cl * 10000 + Level * 100 + Removed + (Ps - Base) + (Cp - Base) + Top;
  if Pp <> @History then
    Result := -1;
end;

function SixWord(Index: Integer): Int64; noinline;
begin
  Result := Sixes[Index].A;
end;

function SixLong(Index: Integer): Int64; noinline;
begin
  Result := Sixes[Index].B;
end;

function TwelveLong(Index: Integer): Cardinal; noinline;
begin
  Result := Twelves[Index].C;
end;

function TwentyLong(Index: Cardinal): Cardinal; noinline;
begin
  Result := Twenties[Index].E;
end;

function TwentyFourWide(Index: Int64): Int64; noinline;
begin
  Result := TwentyFours[Index].C;
end;

function SeventyTwoWide(Index: Integer): Int64; noinline;
begin
  Result := SeventyTwos[Index].B;
end;

function SeventyTwoAddress(Index: Integer): Pointer; noinline;
begin
  Result := @SeventyTwos[Index].B;
end;

function IndexAgain(Index: Integer): Int64; noinline;
var
  K: Int64;
begin
  { the index is read behind the load of the element }
  K := Index;
  Result := TwentyFours[K].B;
  Result := Result * 100 + K;
end;

function ByteKeepsRest(const Marks: array of TMark; Index: Int64): Int64; noinline;
var
  R: Int64;
begin
  { one byte of the element goes into the low byte of a value which keeps
    its other bytes }
  R := Index * 256;
  PByte(@R)^ := Marks[Index].Level;
  Result := R;
end;

var
  Text: array[0..31] of AnsiChar = 'abcdefghijklmnopqrstuvwxyz01234';
  Marks: array[0..3] of TMark;
  K: Integer;
begin
  Check(Walk(@Text[0], 4), 13050423, 'fields of an element of 40 bytes in a nested routine');

  for K := 0 to 9 do
    begin
      Sixes[K].A := 100 + K;
      Sixes[K].B := 100000 + K;
      Twelves[K].C := 3000000000 + Cardinal(K);
      Twenties[K].E := 4000000000 + Cardinal(K);
      TwentyFours[K].B := 20 + K;
      TwentyFours[K].C := -5000000000 - K;
      SeventyTwos[K].B := 7000000000 + K;
    end;
  Check(SixWord(7), 107, 'a word of an element of 6 bytes');
  Check(SixLong(7), 100007, 'four bytes of an element of 6 bytes');
  Check(TwelveLong(8), 3000000008, 'an element of 12 bytes');
  Check(TwentyLong(9), 4000000009, 'an element of 20 bytes');
  Check(TwentyFourWide(6), -5000000006, 'an element of 24 bytes');
  Check(SeventyTwoWide(5), 7000000005, 'an element of 72 bytes');
  Check(PInt64(SeventyTwoAddress(4))^, 7000000004, 'the address of an element of 72 bytes');
  Check(IndexAgain(3), 2303, 'the index is read behind the load');
  for K := 0 to 3 do
    Marks[K].Level := 200 + K;
  Check(ByteKeepsRest(Marks, 2), 2 * 256 + 202, 'a byte of the element, the rest of the value is kept');

  if Fails = 0 then
    WriteLn('SCALED_INDEX_PASS')
  else
  begin
    WriteLn('SCALED_INDEX_FAIL ', Fails);
    Halt(1);
  end;
end.
