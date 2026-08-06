{ %OPT=-O3 }
program tdelphilocalfinalizeforms1;

{$mode delphi}
{$modeswitch inlinevars}
{$modeswitch tuples}
{$modeswitch autofree}

type
  TTrace = class(TInterfacedObject)
  public
    constructor Create;
    destructor Destroy; override;
  end;

  TBox = record
    Item: IInterface;
  end;

var
  Alive: Integer;
  RawCount: Integer;
  Raw: array[0..15] of TTrace;

constructor TTrace.Create;
begin
  inherited Create;
  Inc(Alive);
end;

destructor TTrace.Destroy;
begin
  Dec(Alive);
  inherited Destroy;
end;

function NewItem: IInterface;
var
  Item: TTrace;
begin
  Item := TTrace.Create;
  Raw[RawCount] := Item;
  Inc(RawCount);
  Result := Item;
end;

function NewBox: TBox;
begin
  Result.Item := NewItem;
end;

function NewPair: (IInterface, IInterface);
begin
  Result := (NewItem, NewItem);
end;

procedure CheckWithVar;
begin
  with var Box: TBox := NewBox do begin
    If Item = nil then
      Halt(1);
    If Alive <> 1 then
      Halt(2);
  end;
  If Alive <> 0 then
    Halt(3);
end;

procedure CheckTupleDeclaration;
var
  RefA, RefB: Integer;
begin
  RawCount := 0;
  begin
    var (A, B) := NewPair;
    If (A = nil) or (B = nil) then
      Halt(4);
    If Alive <> 2 then
      Halt(5);
    RefA := Raw[0].RefCount;
    RefB := Raw[1].RefCount;
  end;
  If (Raw[0].RefCount <> RefA - 1) or
     (Raw[1].RefCount <> RefB - 1) then
    Halt(6);
end;

procedure CheckForInTuple;
var
  Items: array of (IInterface, IInterface);
  Count: Integer;
  I: Integer;
  RefBefore: array[0..3] of Integer;
begin
  RawCount := 0;
  Items := [NewPair, NewPair];
  If Alive <> 4 then
    Halt(7);
  for I := 0 to 3 do
    RefBefore[I] := Raw[I].RefCount;
  Count := 0;
  for var (A, B) in Items do begin
    If (A = nil) or (B = nil) then
      Halt(8);
    Inc(Count);
  end;
  If Count <> 2 then
    Halt(9);
  for I := 0 to 3 do
    If Raw[I].RefCount <> RefBefore[I] then
      Halt(10);
  Items := nil;
end;

begin
  Alive := 0;
  CheckWithVar;
  CheckTupleDeclaration;
  If Alive <> 0 then
    Halt(11);
  CheckForInTuple;
  If Alive <> 0 then
    Halt(12);
end.
