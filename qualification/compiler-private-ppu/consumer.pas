unit consumer;
{$mode delphi}{$INLINE ON}
interface
function ConsumerValue: LongInt; inline;
implementation
uses provider;

function ConsumerValue: LongInt;
begin
  Result:=ReadValue;
end;
end.
