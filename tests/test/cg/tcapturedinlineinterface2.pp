program tcapturedinlineinterface2;

{$ifdef FPC}
  {$mode delphiunicode}
  {$modeswitch anonymousfunctions}
  {$modeswitch functionreferences}
  {$modeswitch inlinevars}
{$endif}

type
  ITracked = interface
    ['{1B4D628F-DC89-46FB-8F4B-E5364633F35B}']
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

procedure RunSynchronous;
begin
  for var I:=1 to 3 do begin
    var Token: ITracked:=TTracked.Create;
    var Action: TAction:=procedure
      begin
        If Token=nil then
          Halt(1);
      end;
    Action();
    If TTracked.Alive<>1 then
      Halt(2);
  end;
end;

procedure RunTwoCaptured;
begin
  for var I:=1 to 3 do begin
    var Left: ITracked:=TTracked.Create;
    var Right: ITracked:=TTracked.Create;
    var Action: TAction:=procedure
      begin
        If (Left=nil) or (Right=nil) then
          Halt(7);
      end;
    Action();
    If TTracked.Alive<>2 then
      Halt(8);
  end;
end;

procedure RunUninitialized;
begin
  var Token: ITracked;
  Token:=TTracked.Create;
  var Action: TAction:=procedure
    begin
      If Token=nil then
        Halt(9);
    end;
  Action();
end;

function MakeLast: TAction;
begin
  for var I:=1 to 3 do begin
    var Token: ITracked:=TTracked.Create;
    Result:=procedure
      begin
        If Token=nil then
          Halt(3);
      end;
  end;
end;

var
  Action: TAction;
begin
  RunSynchronous;
  If TTracked.Alive<>0 then
    Halt(4);
  RunTwoCaptured;
  If TTracked.Alive<>0 then
    Halt(10);
  RunUninitialized;
  If TTracked.Alive<>0 then
    Halt(11);
  Action:=MakeLast();
  If TTracked.Alive<>1 then
    Halt(5);
  Action:=nil;
  If TTracked.Alive<>0 then
    Halt(6);
end.
