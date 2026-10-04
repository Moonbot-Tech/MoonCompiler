unit semfpcinit;
{$mode fpc}
{$modeswitch inlinevars}
{$interfaces com}
interface
uses semtrack;
implementation
initialization
  begin
    var Token: IToken := TToken.Create;
    If Token.Value <> 42 then Halt(93);
  end;
end.
