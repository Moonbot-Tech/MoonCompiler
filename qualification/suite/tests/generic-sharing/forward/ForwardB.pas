unit ForwardB;
{$mode delphi}
interface
uses ForwardCore;
type TIntAlias=Integer;
function BridgeClassB:TClass;
function ForwardInfoB:Pointer;
implementation
function BridgeClassB:TClass;
begin
  Result:=TBridge<TIntAlias>;
end;
function ForwardInfoB:Pointer;
begin
  Result:=TypeInfo(IForward<TIntAlias>);
end;
end.