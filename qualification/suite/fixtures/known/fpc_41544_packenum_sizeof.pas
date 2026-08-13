program Fpc41544PackenumSizeof;

{$mode objfpc}

type
  {$push}
  {$warn 3031 off}
  {$packenum 4}
  TVerdict = (
    Wrong = 0,
    Good = 1,
    None = Low(
      {$if SizeOf(TVerdict) = SizeOf(ShortInt)} ShortInt
      {$elseif SizeOf(TVerdict) = SizeOf(SmallInt)} SmallInt
      {$elseif SizeOf(TVerdict) = SizeOf(LongInt)} LongInt
      {$else} Integer {$endif}
    )
  );
  {$pop}

begin
  if SizeOf(TVerdict) <> 4 then
    Halt(1);
  if Ord(TVerdict.None) <> Low(LongInt) then
    Halt(2);
end.
