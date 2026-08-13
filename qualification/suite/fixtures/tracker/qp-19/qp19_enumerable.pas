unit qp19_enumerable;
{$ifdef FPC}{$mode delphiunicode}{$H+}{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}{$modeswitch functionreferences}{$modeswitch nestedprocvars}{$modeswitch inlinevars}{$endif}
interface
type
  TCountedEnumerator = class
  private
    FCurrent: Integer;
  public
    class var Alive: Integer;
    constructor Create;
    destructor Destroy; override;
    function MoveNext: Boolean;
    property Current: Integer read FCurrent;
  end;
  TCountedEnumerable = class
    function GetEnumerator: TCountedEnumerator;
  end;
implementation
constructor TCountedEnumerator.Create;
begin inherited Create; Inc(Alive); FCurrent := 0; end;
destructor TCountedEnumerator.Destroy;
begin Dec(Alive); inherited; end;
function TCountedEnumerator.MoveNext: Boolean;
begin Inc(FCurrent); Result := FCurrent <= 3; end;
function TCountedEnumerable.GetEnumerator: TCountedEnumerator;
begin Result := TCountedEnumerator.Create; end;
end.
