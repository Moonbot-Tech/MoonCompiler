program Forward;
{$mode delphi}
uses SysUtils, ForwardCore, ForwardA, ForwardB;

var
  Bridge: TBridge<Integer>;
begin
  try
    If (BridgeClassA<>BridgeClassB) or (ForwardInfoA<>ForwardInfoB) then raise Exception.Create('FORWARD identity');
    Bridge:=TBridge<Integer>.Create;
    Bridge.Number:=TForward<Integer>.Create;
    Bridge.Number.Value:=137;
    Bridge.NumberRef:=Bridge.Number;
    Bridge.Text:=TForward<UnicodeString>.Create;
    Bridge.Text.Value:='forward string';
    Bridge.TextRef:=Bridge.Text;
    Bridge.Typed:=Bridge.Number;
    Bridge.TypedRef:=Bridge.Number;
    If Bridge.Typed.Value<>137 then raise Exception.Create('FORWARD formal class');
    If Bridge.TypedRef.GetValue<>137 then raise Exception.Create('FORWARD formal interface');
    If Bridge.NumberRef.GetValue<>137 then raise Exception.Create('FORWARD integer');
    If Bridge.TextRef.GetValue<>'forward string' then raise Exception.Create('FORWARD managed');
    Bridge.Free;
    If Finalized<>2 then raise Exception.Create('FORWARD lifecycle');
    Writeln('FORWARD_PASS');
  except
    on E: Exception do begin
      Writeln('CONTRACT_REJECTED: ',E.Message);
      Halt(91);
    end;
  end;
end.
