{ Literal component resource loading through the published-method table. }

type
  TBreadthResourceComponent = class(TComponent)
  private
    FLevel: Integer;
    FOnPulse: TNotifyEvent;
    FTrace: Integer;
    procedure SetLevel(Value: Integer);
  protected
    procedure Loaded; override;
  public
    property Trace: Integer read FTrace;
  published
    procedure ApplyPulse(Sender: TObject);
    property Level: Integer read FLevel write SetLevel;
    property OnPulse: TNotifyEvent read FOnPulse write FOnPulse;
  end;

procedure TBreadthResourceComponent.SetLevel(Value: Integer);
begin
  FLevel := Value;
  If (csLoading in ComponentState) and (csReading in ComponentState) then
    FTrace := FTrace * 10 + 1;
end;

procedure TBreadthResourceComponent.Loaded;
begin
  inherited;
  If not (csLoading in ComponentState) and not (csReading in ComponentState) and Assigned(FOnPulse) then
    FTrace := FTrace * 10 + 2;
end;

procedure TBreadthResourceComponent.ApplyPulse(Sender: TObject);
begin
  If Sender = Self then
    FTrace := FTrace * 10 + 3;
  FLevel := FLevel + 842;
end;

function BreadthReadTextComponent(const Resource: AnsiString; Target: TComponent; Binary: TStream): TComponent;
var
  Text: TMemoryStream;
begin
  Text := TMemoryStream.Create;
  try
    Text.WriteBuffer(Resource[1], Length(Resource));
    Text.Position := 0;
    ObjectTextToBinary(Text, Binary);
    Binary.Position := 0;
    Result := Binary.ReadComponent(Target);
  finally
    Text.Free;
  end;
end;

procedure RunBreadthResourceDispatch;
const
  Resource: AnsiString =
    'object BreadthResource: TBreadthResourceComponent'#10 +
    '  Level = -304'#10 +
    '  OnPulse = ApplyPulse'#10 +
    'end'#10;
var
  Binary: TMemoryStream;
  Target, CopyTarget: TBreadthResourceComponent;
  LoadedTarget: TComponent;
  Pulse: TNotifyEvent;
begin
  Binary := TMemoryStream.Create;
  try
    Target := TBreadthResourceComponent.Create(nil);
    try
      LoadedTarget := BreadthReadTextComponent(Resource, Target, Binary);
      Check((LoadedTarget = Target) and (Target.Name = 'BreadthResource'), 'breadth-resource-restores-existing-root');
      Check((Target.Level = -304) and (Target.Trace = 12), 'breadth-resource-property-and-loaded-ordered');
      Pulse := Target.OnPulse;
      Check(Assigned(Pulse) and (TMethod(Pulse).Data = Target), 'breadth-resource-method-binds-loaded-instance');
      If Assigned(Pulse) then
        Pulse(Target);
      Check((Target.Level = 538) and (Target.Trace = 123), 'breadth-resource-loaded-method-invokes-real-handler');
      Mix(UInt64(Target.Trace));
      Binary.Size := 0;
      Binary.WriteComponent(Target);
      Binary.Position := 0;
      CopyTarget := TBreadthResourceComponent.Create(nil);
      try
        LoadedTarget := Binary.ReadComponent(CopyTarget);
        Check((LoadedTarget = CopyTarget) and (CopyTarget.Level = 538) and (CopyTarget.Trace = 12),
          'breadth-resource-writer-preserves-published-state');
        Pulse := CopyTarget.OnPulse;
        Check(Assigned(Pulse) and (TMethod(Pulse).Data = CopyTarget), 'breadth-resource-writer-resolves-new-receiver');
        If Assigned(Pulse) then
          Pulse(CopyTarget);
        Check((Target.Level = 538) and (CopyTarget.Level = 1380) and (CopyTarget.Trace = 123),
          'breadth-resource-roundtrip-keeps-receiver-state-separate');
        Mix(UInt64(CopyTarget.Level));
      finally
        CopyTarget.Free;
      end;
    finally
      Target.Free;
    end;
  finally
    Binary.Free;
  end;
end;
