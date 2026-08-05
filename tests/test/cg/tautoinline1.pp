{ %OPT=-O3 -OoAUTOINLINE }
program tautoinline1;

{$mode delphi}

type
  TGuard = class(TInterfacedObject)
  public
    class var Alive: Integer;
    constructor Create;
    destructor Destroy; override;
  end;

  TManagedRec = record
    Intf: IInterface;
    Tag: Integer;
  end;

constructor TGuard.Create;
begin
  inherited Create;
  Inc(Alive);
end;

destructor TGuard.Destroy;
begin
  Dec(Alive);
  inherited Destroy;
end;

procedure ModifyByValue(R: TManagedRec);
begin
  R.Tag := 0;
end;

var
  R: TManagedRec;
begin
  R.Intf := TGuard.Create;
  R.Tag := 42;
  ModifyByValue(R);
  if TGuard.Alive <> 1 then
    Halt(1);
  R.Intf := nil;
  if TGuard.Alive <> 0 then
    Halt(2);
end.
