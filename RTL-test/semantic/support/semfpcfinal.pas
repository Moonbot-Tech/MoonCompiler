unit semfpcfinal;
{$mode fpc}{$modeswitch inlinevars}
interface
implementation
uses semraise, semtrack;
finalization
  begin
    var Token: IToken := TToken.Create;
    WriteLn('FINAL_TOKEN ', Token.Value);
    RaiseCallback;
  end;
end.
