program twidecharsetmembership1;

{$mode delphiunicode}
{$R-}{$Q-}

var
  Calls: Integer;
  I: Integer;
  W: WideChar;
  FourHits: Integer;
  FiveHits: Integer;
  MixedHits: Integer;
  ByteHits: Integer;
  VariableHits: Integer;
  ByteSet: set of AnsiChar;

function CountedWide(Value: Word): WideChar;
begin
  Inc(Calls);
  Result:=WideChar(Value);
end;

begin
  FourHits:=0;
  FiveHits:=0;
  MixedHits:=0;
  ByteHits:=0;
  for I:=0 to 1000 do
    begin
      W:=WideChar(I);
      if W in ['a','e','i','o'] then
        Inc(FourHits);
      if W in ['a','e','i','o','u'] then
        Inc(FiveHits);
      if W in ['0'..'9','A'..'F','a'..'f','_','$',#$80..#$ff] then
        Inc(MixedHits);
      if W in [#$80..#$ff] then
        Inc(ByteHits);
    end;
  if (FourHits<>4) or (FiveHits<>5) or (MixedHits<>152) or
     (ByteHits<>128) then
    Halt(1);

  Calls:=0;
  if CountedWide($410) in ['a','e','i','o','u'] then
    Halt(2);
  if Calls<>1 then
    Halt(3);

  ByteSet:=[AnsiChar(#$80)..AnsiChar(#$ff)];
  VariableHits:=0;
  for I:=0 to 1000 do
    if WideChar(I) in ByteSet then
      Inc(VariableHits);
  if VariableHits<>128 then
    Halt(4);
end.
