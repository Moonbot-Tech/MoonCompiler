program alias_consumer;
{$mode delphi}{$H+}{$INLINE ON}
uses alias_cases;
var
  Obj: TObjChain;
  Derived: TDerivedCopy;
  R: TRecChain;
  E: TEnumChain;
  S: TSub;
  P: TPacked;
  A: TArray;
  I: Integer;
begin
  Obj:=TObjChain.Create;
  Derived:=TDerivedCopy.Create;
  Obj.Value:=42;
  Derived.Value:=35;
  R.Value:=Obj.ReadValue;
  R.Text:='abc';
  E:=TEnumChain(three);
  S:=two;
  P.Prefix:=17;
  P.Suffix:=23;
  P.Item.Value:=53;
  for I:=0 to High(A) do
    A[I].Value:=I*13+5;
  if (R.Value<>42) or (Ord(E)<>2) or (Ord(S)<>1) or (Derived.ReadValue<>42) then
    Halt(1);
  if InlineValue(R)<>45 then
    Halt(2);
  if (P.Item.ReadValue<>53) or (P.Prefix<>17) or (P.Suffix<>23) then
    Halt(3);
  for I:=0 to High(A) do
    if A[I].ReadValue<>I*13+5 then
      Halt(4);
  Obj.Free;
  Derived.Free;
  WriteLn('L2_ALIAS_PASS');
end.
