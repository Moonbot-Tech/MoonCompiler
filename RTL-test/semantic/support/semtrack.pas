unit semtrack;
{$IFDEF FPC}{$mode delphi}{$ENDIF}
interface
type
  IToken = interface
    ['{B27392E4-BCBF-4C4E-9921-9FB5D4B2A1C5}']
    function Value: Integer;
  end;
  TToken = class(TInterfacedObject, IToken)
    constructor Create;
    destructor Destroy; override;
    function Value: Integer;
  end;
var Created, Destroyed: Integer;
implementation
constructor TToken.Create;
begin
  inherited Create;
  Inc(Created);
end;
destructor TToken.Destroy;
begin
  Inc(Destroyed);
  inherited Destroy;
end;
function TToken.Value: Integer;
begin
  Result := 42;
end;
initialization
finalization
  Writeln('BALANCE ', Created, ' ', Destroyed);
  If Created <> Destroyed then Halt(92);
end.
