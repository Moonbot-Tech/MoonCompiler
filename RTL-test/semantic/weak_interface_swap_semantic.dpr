program weak_interface_swap_semantic;
{$mode unleashed}
{$modeswitch prefixedattributes}

uses SysUtils;

type
  TRow = record
    Name: string;
    [Weak] Link: IInterface;
  end;

procedure Check(Value: Boolean; const Where: string);
begin
  if not Value then raise Exception.Create(Where);
end;

procedure TestSwap;
var
  A, B, Strong: IInterface;
  Left, Right: TRow;
begin
  A := TInterfacedObject.Create;
  B := TInterfacedObject.Create;
  Left.Name := 'left';
  Right.Name := 'right';
  Left.Link := A;
  Right.Link := B;
  SwapValues(Left, Right);
  Check((Left.Name = 'right') and (Right.Name = 'left'), 'swap records');
  SwapValues(Left, Left);
  A := nil;
  Check((Pointer(Right.Link) = nil) and (Left.Link = B), 'relocated weak target');
  A := TInterfacedObject.Create;
  Right.Link := A;
  SwapValues(Left.Link, Right.Link);
  Check((Left.Link = A) and (Right.Link = B), 'swap weak fields');
  Strong := B;
  SwapValues(Left.Link, Strong);
  A := nil;
  Check((Strong <> nil) and (Left.Link = B), 'swap strong and weak');
  B := nil;
  Check((Pointer(Left.Link) = nil) and (Pointer(Right.Link) = nil), 'swapped weak slots cleared');
end;

begin
  TestSwap;
  WriteLn('WEAK_INTERFACE_SWAP_PASS');
end.
