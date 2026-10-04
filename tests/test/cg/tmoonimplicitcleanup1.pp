{ %OPT=-O3 -OoAUTOINLINE }
program tmoonimplicitcleanup1;
{$mode delphiunicode}
uses SysUtils;
var
  Finalized, AfterCalls, Destroyed, Caught: Integer;
  FinalizeBoom, ConstructorBoom: Boolean;
type
  TTracked = record
    Active: Boolean;
    class operator Initialize(out Dest: TTracked);
    class operator Finalize(var Dest: TTracked);
  end;
  TRefObject = class(TInterfacedObject)
    constructor Create;
    procedure AfterConstruction; override;
    destructor Destroy; override;
  end;
class operator TTracked.Initialize(out Dest: TTracked);
begin
  Dest.Active:=True;
end;
class operator TTracked.Finalize(var Dest: TTracked);
begin
  if not Dest.Active then Halt(1);
  Dest.Active:=False;
  Inc(Finalized);
  if FinalizeBoom then
  begin
    FinalizeBoom:=False;
    raise Exception.Create('finalizer');
  end;
end;
constructor TRefObject.Create;
var
  Hold: IInterface;
  Tracked: TTracked;
begin
  inherited Create;
  if not Tracked.Active then Halt(11);
  Hold:=Self;
  if RefCount<>2 then Halt(2);
  if ConstructorBoom then raise Exception.Create('constructor');
end;
procedure TRefObject.AfterConstruction;
begin
  if (Finalized<>1) or (RefCount<>1) or (Destroyed<>0) then Halt(3);
  Inc(AfterCalls);
  inherited AfterConstruction;
end;
destructor TRefObject.Destroy;
begin
  Inc(Destroyed);
  inherited Destroy;
end;
procedure Cleanup(BodyBoom: Boolean);
var
  Tracked: TTracked;
begin
  if not Tracked.Active then Halt(12);
  if BodyBoom then raise Exception.Create('body');
end;
procedure LargeCleanup; noinline;
var
  A,B,C,D,E,F,G,H,I,J,K,L,M,N,O,P: TTracked;
begin
  if not(A.Active and B.Active and C.Active and D.Active and E.Active and F.Active and G.Active and H.Active and
    I.Active and J.Active and K.Active and L.Active and M.Active and N.Active and O.Active and P.Active) then Halt(13);
end;
var
  Obj: TRefObject;
  I: Integer;
begin
  Obj:=TRefObject.Create;
  if (Obj.RefCount<>0) or (AfterCalls<>1) or (Finalized<>1) then Halt(4);
  Obj.Free;
  if Destroyed<>1 then Halt(5);
  ConstructorBoom:=True;
  try
    Obj:=TRefObject.Create;
    Halt(6);
  except
    on E: Exception do
      if E.Message='constructor' then Inc(Caught) else raise;
  end;
  if (Caught<>1) or (Destroyed<>2) or (AfterCalls<>1) or (Finalized<>2) then Halt(7);
  for I:=0 to 1 do
  begin
    FinalizeBoom:=True;
    try
      Cleanup(I<>0);
      Halt(8);
    except
      on E: Exception do
        if E.Message='finalizer' then Inc(Caught) else raise;
    end;
    if Finalized<>I+3 then Halt(9);
  end;
  if Caught<>3 then Halt(10);
  LargeCleanup;
  if Finalized<>20 then Halt(14);
  WriteLn('implicit cleanup ok');
end.
