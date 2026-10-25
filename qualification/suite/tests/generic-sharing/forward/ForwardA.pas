unit ForwardA;
{$mode delphi}
interface
uses ForwardCore;
function BridgeClassA:TClass;
function ForwardInfoA:Pointer;
implementation
function BridgeClassA:TClass;
begin
  Result:=TBridge<Integer>;
end;
function ForwardInfoA:Pointer;
begin
  Result:=TypeInfo(IForward<Integer>);
end;
end.