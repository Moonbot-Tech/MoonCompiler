{ %OPT=-O3 }
program tifminmaxtarget1;
{$IFDEF FPC}{$mode delphi}{$ENDIF}
{$inline on}
uses {$IFDEF FPC}SysUtils, Math{$ELSE}System.SysUtils, System.Math{$ENDIF};
{ The condition precedes address evaluation. A target may change the values
  selected by that condition, or raise a different exception. CONTROL keeps
  the condition in a separate call so it cannot become a min/max intrinsic. }
type
  TItem = record A, B, Value: Integer; end;
  PItem = ^TItem;
  TItems = array[0..1] of TItem;
  TReals = array[0..1] of Double;
var
  A, B, Sink, Calls, Failures: Integer;
  X, Y, RealSink: Double;
  U, V: UInt64;
  Values: array[0..1] of UInt64;
  CheckedValues: array[0..1] of Integer;
  Item: TItem;
  Items: TItems;
  Reals: TReals;

function Less(L, R: Integer): Boolean; {$IFDEF FPC}noinline;{$ENDIF}
begin
  Result := L < R;
end;
function GreaterReal(L, R: Double): Boolean; {$IFDEF FPC}noinline;{$ENDIF}
begin
  Result := L > R;
end;
function GreaterUnsigned(L, R: UInt64): Boolean; {$IFDEF FPC}noinline;{$ENDIF}
begin
  Result := L >= R;
end;
function Target: PInteger; {$IFDEF FPC}noinline;{$ENDIF}
begin
  Inc(Calls);
  A := 50;
  B := 1;
  Result := @Sink;
end;
function RealTarget: PDouble; {$IFDEF FPC}noinline;{$ENDIF}
begin
  Inc(Calls);
  X := 50;
  Y := 1;
  Result := @RealSink;
end;
function Index: Integer; {$IFDEF FPC}noinline;{$ENDIF}
begin
  Inc(Calls);
  U := 50;
  V := 1;
  Result := 0;
end;
function InlineTarget: PInteger; inline;
begin
  Inc(Calls);
  A := 50;
  B := 1;
  Result := @Sink;
end;

procedure PointerMin; {$IFDEF FPC}noinline;{$ENDIF}
begin
  If {$IFDEF CONTROL}Less(A, B){$ELSE}A < B{$ENDIF} then Target^ := A else Target^ := B;
end;
procedure PointerMax; {$IFDEF FPC}noinline;{$ENDIF}
begin
  If {$IFDEF CONTROL}Less(A, B){$ELSE}A < B{$ENDIF} then Target^ := B else Target^ := A;
end;
procedure RealMax; {$IFDEF FPC}noinline;{$ENDIF}
begin
  If {$IFDEF CONTROL}GreaterReal(X, Y){$ELSE}X > Y{$ENDIF} then RealTarget^ := X else RealTarget^ := Y;
end;
procedure ElementMax; {$IFDEF FPC}noinline;{$ENDIF}
begin
  If {$IFDEF CONTROL}GreaterUnsigned(U, V){$ELSE}U >= V{$ENDIF} then Values[Index] := U else Values[Index] := V;
end;
procedure InlinedMin; {$IFDEF FPC}noinline;{$ENDIF}
begin
  If {$IFDEF CONTROL}Less(A, B){$ELSE}A < B{$ENDIF} then InlineTarget^ := A else InlineTarget^ := B;
end;

{ These ordinary forms must retain their min/max code. }
procedure HotField(var R: TItem); {$IFDEF FPC}noinline;{$ENDIF}
begin
  If R.A < R.B then R.Value := R.A else R.Value := R.B;
end;
procedure HotElement(var R: TItems; I: Integer); {$IFDEF FPC}noinline;{$ENDIF}
begin
  If R[I].A < R[I].B then R[I].Value := R[I].A else R[I].Value := R[I].B;
end;
procedure HotPointer(P: PItem); {$IFDEF FPC}noinline;{$ENDIF}
begin
  If P^.A < P^.B then P^.Value := P^.A else P^.Value := P^.B;
end;
function GetItem: PItem; inline;
begin
  Result := @Item;
end;
procedure HotGetter; {$IFDEF FPC}noinline;{$ENDIF}
begin
  If Item.A < Item.B then GetItem^.Value := Item.A else GetItem^.Value := Item.B;
end;

{$R+}
procedure HotCheckedReal(var R: TReals; I: Integer; L, H: Double); {$IFDEF FPC}noinline;{$ENDIF}
begin
  If L < H then R[I] := L else R[I] := H;
end;
procedure HotCheckedElement(var R: TItems; I: Integer); {$IFDEF FPC}noinline;{$ENDIF}
begin
  If R[I].A < R[I].B then R[I].Value := R[I].A else R[I].Value := R[I].B;
end;
procedure ExceptionOrder(Divisor, Bound, I: Integer); {$IFDEF FPC}noinline;{$ENDIF}
begin
  If {$IFDEF CONTROL}Less(10 div Divisor, Bound){$ELSE}10 div Divisor < Bound{$ENDIF} then
    CheckedValues[Min(I, I+1)] := 10 div Divisor
  else
    CheckedValues[Min(I, I+1)] := Bound;
end;
{$R-}

procedure Check(Got, Expected: Double; const Name: string);
begin
  If (Got <> Expected) or (Calls <> 1) then begin
    Writeln('FAIL ', Name, ' got=', Got:0:0, ' expected=', Expected:0:0, ' calls=', Calls);
    Inc(Failures);
  end;
end;
procedure Reset(First, Second: Integer);
begin
  A := First;
  B := Second;
  X := First;
  Y := Second;
  U := First;
  V := Second;
  Calls := 0;
end;
var Caught: Boolean;
begin
  Reset(5, 10);
  PointerMin;
  Check(Sink, 50, 'pointer min then');
  Reset(10, 5);
  PointerMin;
  Check(Sink, 1, 'pointer min else');
  Reset(5, 10);
  PointerMax;
  Check(Sink, 1, 'pointer max then');
  Reset(10, 5);
  PointerMax;
  Check(Sink, 50, 'pointer max else');
  Reset(5, 10);
  RealMax;
  Check(RealSink, 1, 'real max else');
  Reset(10, 5);
  RealMax;
  Check(RealSink, 50, 'real max then');
  Reset(5, 10);
  ElementMax;
  Check(Values[0], 1, 'element max else');
  Reset(10, 5);
  ElementMax;
  Check(Values[0], 50, 'element max then');
  Reset(5, 10);
  InlinedMin;
  Check(Sink, 50, 'inline target then');
  Reset(10, 5);
  InlinedMin;
  Check(Sink, 1, 'inline target else');
  Item.A := 5;
  Item.B := 10;
  Calls := 1;
  HotField(Item);
  Check(Item.Value, 5, 'ordinary field');
  Items[0] := Item;
  HotElement(Items, 0);
  Check(Items[0].Value, 5, 'ordinary element');
  HotPointer(@Item);
  Check(Item.Value, 5, 'ordinary pointer');
  HotGetter;
  Check(Item.Value, 5, 'ordinary getter');
  HotCheckedReal(Reals, 0, 5, 10);
  Check(Reals[0], 5, 'ordinary checked real');
  HotCheckedElement(Items, 0);
  Check(Items[0].Value, 5, 'ordinary checked element');
  Caught := False;
  try
    ExceptionOrder(0, 5, 5);
  except
    on E: EDivByZero do Caught := True;
    on E: Exception do Writeln('FAIL exception order: ', E.ClassName);
  end;
  If not Caught then Inc(Failures);
  ExceptionOrder(2, 10, 0);
  Check(CheckedValues[0], 5, 'checked min success');
  If Failures <> 0 then Halt(1);
  Writeln('IF_MINMAX_TARGET_OK');
end.
