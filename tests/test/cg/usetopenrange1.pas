unit usetopenrange1;

{$mode delphi}

interface

type
  TByteSet = set of Byte;
  TBasedIndex = 100..200;
  TBasedSet = set of TBasedIndex;

procedure ReplaceByteRange(var S: TByteSet; A, B: Byte); noinline;
procedure ReplaceByteRangeChecked(var S: TByteSet; A, B: Byte); noinline;
procedure ExtendByteRange(var S: TByteSet; A, B: Byte); noinline;
procedure ReplaceBasedRange(var S: TBasedSet; A, B: TBasedIndex); noinline;

implementation

{$R-}
procedure ReplaceByteRange(var S: TByteSet; A, B: Byte);
begin
  S := [A..B];
end;

{$R+}
procedure ReplaceByteRangeChecked(var S: TByteSet; A, B: Byte);
begin
  S := [A..B];
end;

{$R-}
procedure ExtendByteRange(var S: TByteSet; A, B: Byte);
begin
  S := S + [A..B];
end;

procedure ReplaceBasedRange(var S: TBasedSet; A, B: TBasedIndex);
begin
  S := [A..B];
end;

end.
