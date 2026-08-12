program tcapturedinlineinterface1;

{$mode delphiunicode}
{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}
{$modeswitch inlinevars}

type
  ITracked = interface
    ['{4861D96F-B312-4C95-AED0-13E2A8C77B67}']
  end;

  TTracked = class(TInterfacedObject, ITracked)
  public
    class var Alive: LongInt;
    constructor Create;
    destructor Destroy; override;
  end;

  TAction = reference to procedure;

constructor TTracked.Create;
begin
  inherited;
  Inc(Alive);
end;

destructor TTracked.Destroy;
begin
  Dec(Alive);
  inherited;
end;

function MakeAction: TAction;
begin
  var Token: ITracked := TTracked.Create;
  Result := procedure
    begin
      If Token = nil then
        Halt(1);
    end;
end;

var
  First,
  Second: TAction;
begin
  First:=MakeAction;
  Second:=First;
  If TTracked.Alive<>1 then
    Halt(2);
  First:=nil;
  If TTracked.Alive<>1 then
    Halt(3);
  Second:=nil;
  If TTracked.Alive<>0 then
    Halt(4);
end.
