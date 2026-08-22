{ %OPT=-O3 }
program tstrengthresultcounter1;

{$mode delphi}

type
  TGranularity = (granUndefined, granHour, granDay, granMonth, granYear);
  TSignedIndex = -2 .. 0;

const
  GRANULARITY_MARKERS: array[granDay .. granYear] of Integer = (29, 30, 31);
  INTEGER_MARKERS: array[2 .. 4] of Integer = (42, 43, 44);
  SIGNED_MARKERS: array[TSignedIndex] of Integer = (52, 53, 54);

function FindGranularity(Marker: Integer): TGranularity;
begin
  for Result := granDay to granYear do
    if GRANULARITY_MARKERS[Result] = Marker then
      Exit;
  Result := granUndefined;
end;

function FindInteger(Marker: Integer): Integer;
begin
  for Result := 2 to 4 do
    if INTEGER_MARKERS[Result] = Marker then
      Exit;
  Result := -1;
end;

function FindIntegerBackward(Marker: Integer): Integer;
begin
  for Result := 4 downto 2 do
    if INTEGER_MARKERS[Result] = Marker then
      Exit;
  Result := -1;
end;

function FindSigned(Marker: Integer): TSignedIndex;
begin
  for Result := High(TSignedIndex) downto Low(TSignedIndex) do
    if SIGNED_MARKERS[Result] = Marker then
      Exit;
  Result := Low(TSignedIndex);
end;

begin
  if FindGranularity(29) <> granDay then
    Halt(1);
  if FindGranularity(30) <> granMonth then
    Halt(2);
  if FindGranularity(31) <> granYear then
    Halt(3);
  if FindGranularity(99) <> granUndefined then
    Halt(4);

  if FindInteger(42) <> 2 then
    Halt(5);
  if FindInteger(44) <> 4 then
    Halt(6);
  if FindInteger(99) <> -1 then
    Halt(7);

  if FindIntegerBackward(44) <> 4 then
    Halt(8);
  if FindIntegerBackward(42) <> 2 then
    Halt(9);
  if FindIntegerBackward(99) <> -1 then
    Halt(10);

  if FindSigned(54) <> 0 then
    Halt(11);
  if FindSigned(53) <> -1 then
    Halt(12);
  if FindSigned(52) <> -2 then
    Halt(13);
end.
