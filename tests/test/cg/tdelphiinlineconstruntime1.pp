program tdelphiinlineconstruntime1;

{$ifdef FPC}
  {$mode delphiunicode}
  {$modeswitch anonymousfunctions}
  {$modeswitch functionreferences}
  {$modeswitch inlinevars}
{$endif}

uses
  {$ifdef FPC}SysUtils{$else}System.SysUtils{$endif};

type
  ITracked = interface
    ['{CCB32507-02E3-4734-BEE7-81042F8510A8}']
    function GetValue: Integer;
  end;

  TTracked = class(TInterfacedObject, ITracked)
  private
    FValue: Integer;
  public
    class var Alive: Integer;
    constructor Create(AValue: Integer);
    destructor Destroy; override;
    function GetValue: Integer;
  end;

  TBox = class
  private
    FIconSize: Integer;
    FIconGap: Integer;
  public
    constructor Create(AIconSize, AIconGap: Integer);
    function Minimum: Integer;
  end;

  TValueRec = record
    Value: Integer;
  end;

  TEvaluator = class
    class function Evaluate<T>(Base: Integer): Integer; static;
  end;

  TAction = reference to procedure;

var
  Calls: Integer;

function RuntimeValue(AValue: Integer): Integer;
begin
  Inc(Calls);
  Result:=AValue;
end;

function MakeValueRec(AValue: Integer): TValueRec;
begin
  Result.Value:=AValue;
end;

class function TEvaluator.Evaluate<T>(Base: Integer): Integer;
begin
  const StaticTyped: Integer=3;
  const RuntimeValue=Base+SizeOf(T);
  const RuntimeTyped: Integer=RuntimeValue*2;
  case StaticTyped of
    3: Result:=Base+RuntimeValue+RuntimeTyped;
  else
    Result:=-1;
  end;
end;

constructor TTracked.Create(AValue: Integer);
begin
  inherited Create;
  FValue:=AValue;
  Inc(Alive);
end;

destructor TTracked.Destroy;
begin
  Dec(Alive);
  inherited Destroy;
end;

function TTracked.GetValue: Integer;
begin
  Result:=FValue;
end;

constructor TBox.Create(AIconSize, AIconGap: Integer);
begin
  inherited Create;
  FIconSize:=AIconSize;
  FIconGap:=AIconGap;
end;

function TBox.Minimum: Integer;
begin
  Result:=1;
  const MinInner=2*FIconSize+FIconGap;
  Result:=Result+MinInner;
end;

procedure CheckScalars;
var
  Base: Integer;
begin
  Base:=7;
  const StaticValue=2+3;
  const RuntimeUntyped=RuntimeValue(Base+StaticValue);
  const RuntimeTyped: Integer=RuntimeValue(RuntimeUntyped+1);
  If (RuntimeUntyped<>12) or (RuntimeTyped<>13) or (Calls<>2) then
    Halt(1);
end;

procedure CheckArray;
var
  Base: Integer;
begin
  Base:=3;
  const Values=[Base,RuntimeValue(Base+1)];
  If (Length(Values)<>2) or (Values[0]<>3) or (Values[1]<>4) then
    Halt(2);
  Values[0]:=9;
  If Values[0]<>9 then
    Halt(8);
end;

function StaticArrayStep: Integer;
begin
  const Values=[1,2];
  Result:=Values[0];
  Values[0]:=7;
  If Values[0]<>7 then
    Halt(9);
end;

procedure CheckManagedLoop;
begin
  for var I:=1 to 3 do begin
    const Text=IntToStr(I);
    const Tracked=ITracked(TTracked.Create(I));
    If (Text<>IntToStr(I)) or (Tracked.GetValue<>I) or (TTracked.Alive<>1) then
      Halt(3);
  end;
end;

procedure CheckCapturedSynchronous;
begin
  for var I:=1 to 3 do begin
    const Tracked=ITracked(TTracked.Create(I));
    const Action=TAction(procedure
      begin
        If Tracked.GetValue<>I then
          Halt(11);
      end);
    Action();
    If TTracked.Alive<>1 then
      Halt(12);
  end;
end;

function MakeCapturedLast: TAction;
begin
  for var I:=1 to 3 do begin
    const Tracked=ITracked(TTracked.Create(I));
    Result:=procedure
      begin
        If Tracked.GetValue<>3 then
          Halt(13);
      end;
  end;
end;

procedure CheckTypedRecord;
var
  Base: Integer;
begin
  Base:=9;
  const Value: TValueRec=MakeValueRec(Base+4);
  If Value.Value<>13 then
    Halt(5);
end;

var
  Box: TBox;
  Action: TAction;
begin
  CheckScalars;
  CheckArray;
  If (StaticArrayStep<>1) or (StaticArrayStep<>1) then
    Halt(10);
  CheckManagedLoop;
  If TTracked.Alive<>0 then
    Halt(4);
  CheckCapturedSynchronous;
  If TTracked.Alive<>0 then
    Halt(14);
  Action:=MakeCapturedLast();
  If TTracked.Alive<>1 then
    Halt(15);
  Action();
  Action:=nil;
  If TTracked.Alive<>0 then
    Halt(16);
  CheckTypedRecord;
  If (TEvaluator.Evaluate<Byte>(4)<>19) or
     (TEvaluator.Evaluate<Int64>(4)<>40) then
    Halt(6);
  Box:=TBox.Create(16,3);
  try
    If Box.Minimum<>36 then
      Halt(7);
  finally
    Box.Free;
  end;
end.
