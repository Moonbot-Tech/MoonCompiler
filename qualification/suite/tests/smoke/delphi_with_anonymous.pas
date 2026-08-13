program delphi_with_anonymous;

{$mode delphi}
{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}

type
  TPoint = record
    X: Integer;
    Y: Integer;
  end;

  TPlainManaged = record
    Number: Integer;
    Text: string;
  end;

  TTracked = record
  private
    FText: string;
  public
    class operator Initialize(var Dest: TTracked);
    class operator Finalize(var Dest: TTracked);
    property Text: string read FText;
  end;

  TProc = reference to procedure;
  TPointArray = array of TPoint;

  TPointSource = class
  private
    function GetPoint: TPoint;
  public
    property Point: TPoint read GetPoint;
  end;

var
  Callback: TProc;
  EvalCount: Integer;
  IndexCount: Integer;
  InitCount: Integer;
  FinalizeCount: Integer;
  SeenX: Integer;
  SeenY: Integer;
  SeenText: string;

class operator TTracked.Initialize(var Dest: TTracked);
begin
  Inc(InitCount);
  Dest.FText:='';
end;

class operator TTracked.Finalize(var Dest: TTracked);
begin
  Inc(FinalizeCount);
  Dest.FText:='';
end;

function MakePoint: TPoint;
begin
  Inc(EvalCount);
  Result.X:=17;
  Result.Y:=25;
end;

function NextIndex: Integer;
begin
  Inc(IndexCount);
  Result:=1;
end;

function MakePlainManaged: TPlainManaged;
begin
  Inc(EvalCount);
  Result.Number:=31;
  Result.Text:='plain-managed';
end;

function MakePlainManagedIndex(AIndex: Integer): TPlainManaged;
begin
  Result.Number:=AIndex;
  Result.Text:=Chr(Ord('0')+AIndex);
end;

function MakeTracked: TTracked;
begin
  Inc(EvalCount);
  Result.FText:='alive';
end;

function TPointSource.GetPoint: TPoint;
begin
  Result:=MakePoint;
end;

procedure CaptureTemporary;
begin
  with MakePoint do
    Callback:=
      procedure
      begin
        SeenX:=X;
        SeenY:=Y;
      end;
end;

procedure CaptureLocal;
var
  Point: TPoint;
begin
  Point.X:=1;
  Point.Y:=2;
  with Point do
    Callback:=
      procedure
      begin
        SeenX:=X;
        SeenY:=Y;
      end;
  Point.X:=40;
end;

procedure CaptureArrayElement;
var
  Points: array[0..1] of TPoint;
begin
  Points[0].X:=9;
  Points[0].Y:=9;
  Points[1].X:=3;
  Points[1].Y:=4;
  with Points[NextIndex] do
    Callback:=
      procedure
      begin
        SeenX:=X;
        SeenY:=Y;
      end;
  Points[1].X:=50;
end;

procedure CaptureArrayElementByLocalIndex;
var
  Points: array[0..1] of TPoint;
  Index: Integer;
begin
  Index:=1;
  Points[0].X:=9;
  Points[0].Y:=9;
  Points[1].X:=5;
  Points[1].Y:=6;
  with Points[Index] do
    Callback:=
      procedure
      begin
        SeenX:=X;
        SeenY:=Y;
      end;
  Points[1].X:=60;
end;

procedure CaptureDynamicArray;
var
  Points: TPointArray;
begin
  SetLength(Points, 2);
  Points[1].X:=70;
  Points[1].Y:=8;
  with Points[NextIndex] do
    Callback:=
      procedure
      begin
        SeenX:=X;
        SeenY:=Y;
      end;
  Points[1].X:=71;
end;

procedure CaptureDynamicArrayParameter(const Points: TPointArray);
begin
  with Points[NextIndex] do
    Callback:=
      procedure
      begin
        SeenX:=X;
        SeenY:=Y;
      end;
end;

procedure CaptureDynamicArrayThroughParameter;
var
  Points: TPointArray;
begin
  SetLength(Points, 2);
  Points[1].X:=80;
  Points[1].Y:=9;
  CaptureDynamicArrayParameter(Points);
  Points[1].X:=81;
end;

procedure CaptureProperty;
var
  Source: TPointSource;
begin
  Source:=TPointSource.Create;
  try
    with Source.Point do
      Callback:=
        procedure
        begin
          SeenX:=X;
          SeenY:=Y;
        end;
  finally
    Source.Free;
  end;
end;

procedure CaptureManaged;
begin
  with MakeTracked do
    Callback:=
      procedure
      begin
        SeenText:=Text;
      end;
end;

procedure CapturePlainManaged;
begin
  with MakePlainManaged do
    Callback:=
      procedure
      begin
        SeenX:=Number;
        SeenText:=Text;
      end;
end;

procedure CapturePlainManagedLoop;
var
  Callbacks: array[0..2] of TProc;
  I: Integer;
begin
  for I:=0 to 2 do
    with MakePlainManagedIndex(I) do
      Callbacks[I]:=
        procedure
        begin
          SeenX:=Number;
          SeenText:=Text;
        end;
  for I:=0 to 2 do begin
    Callbacks[I]();
    if (SeenX<>2) or (SeenText<>'2') then
      Halt(13);
  end;
end;

var
  FinalizedAtScopeExit: Integer;
begin
  CaptureTemporary;
  if EvalCount<>1 then
    Halt(1);
  Callback();
  if (SeenX<>17) or (SeenY<>25) then
    Halt(2);

  CaptureLocal;
  Callback();
  if (SeenX<>40) or (SeenY<>2) then
    Halt(3);

  CaptureArrayElement;
  if IndexCount<>1 then
    Halt(10);
  Callback();
  if (IndexCount<>1) or (SeenX<>50) or (SeenY<>4) then
    Halt(14);

  CaptureArrayElementByLocalIndex;
  Callback();
  if (SeenX<>60) or (SeenY<>6) then
    Halt(15);

  CaptureDynamicArray;
  Callback();
  if (IndexCount<>2) or (SeenX<>71) or (SeenY<>8) then
    Halt(16);
  Callback:=nil;

  CaptureDynamicArrayThroughParameter;
  Callback();
  if (IndexCount<>3) or (SeenX<>81) or (SeenY<>9) then
    Halt(17);
  Callback:=nil;

  CaptureProperty;
  if EvalCount<>2 then
    Halt(11);
  Callback();
  if (SeenX<>17) or (SeenY<>25) then
    Halt(12);

  CaptureManaged;
  if EvalCount<>3 then
    Halt(4);
  FinalizedAtScopeExit:=FinalizeCount;
  if FinalizedAtScopeExit=0 then
    Halt(5);
  Callback();
  if SeenText<>'' then
    Halt(6);
  Callback:=nil;
  if FinalizeCount<>FinalizedAtScopeExit then
    Halt(7);

  CapturePlainManaged;
  if EvalCount<>4 then
    Halt(8);
  Callback();
  if (SeenX<>31) or (SeenText<>'plain-managed') then
    Halt(9);
  Callback:=nil;
  CapturePlainManagedLoop;
  Writeln('DELPHI_WITH_ANONYMOUS_OK');
end.
