program tdelphianonymousnew1;

{$ifdef FPC}
  {$mode delphiunicode}
  {$modeswitch anonymousfunctions}
  {$modeswitch functionreferences}
  {$modeswitch inlinevars}
{$endif}

type
  TTracked = class(TInterfacedObject)
  public
    class var Alive: Integer;
    constructor Create;
    destructor Destroy; override;
  end;

  TManagedRecord = record
    Text: UnicodeString;
    Values: TArray<Integer>;
    Token: IInterface;
  end;
  PManagedRecord = ^TManagedRecord;
  TProc = reference to procedure;
  TFactory = reference to function: PManagedRecord;

constructor TTracked.Create;
begin
  inherited Create;
  Inc(Alive);
end;

destructor TTracked.Destroy;
begin
  Dec(Alive);
  inherited Destroy;
end;

procedure Check(Condition: Boolean; ErrorCode: Byte);
begin
  if not Condition then
    Halt(ErrorCode);
end;

procedure FillAndCheck(Value: PManagedRecord; Base: Integer);
begin
  Check(Value^.Text = '', Base);
  Check(Value^.Values = nil, Base + 1);
  Check(Value^.Token = nil, Base + 2);
  Value^.Text := 'managed';
  Value^.Values := [Base, Base + 1];
  Value^.Token := TTracked.Create;
  Check((Value^.Text = 'managed') and (Length(Value^.Values) = 2), Base + 3);
end;

procedure Invoke(const Callback: TProc);
begin
  Callback();
end;

procedure CheckRegularStatementForm;
var
  Value: PManagedRecord;
begin
  New(Value);
  FillAndCheck(Value, 10);
  Dispose(Value);
  Check(TTracked.Alive = 0, 14);
end;

procedure CheckAssignedAnonymousInlineLocal;
var
  Callback: TProc;
begin
  Callback := procedure
    begin
      var Value: PManagedRecord;
      New(Value);
      FillAndCheck(Value, 20);
      Dispose(Value);
      Check(TTracked.Alive = 0, 24);
    end;
  Callback();
end;

procedure CheckAssignedAnonymousClassicLocal;
var
  Callback: TProc;
begin
  Callback := procedure
    var
      Value: PManagedRecord;
    begin
      New(Value);
      FillAndCheck(Value, 30);
      Dispose(Value);
      Check(TTracked.Alive = 0, 34);
    end;
  Callback();
end;

procedure CheckArgumentAnonymous;
begin
  Invoke(
    procedure
    begin
      var Value: PInteger;
      New(Value);
      Value^ := 42;
      Check(Value^ = 42, 40);
      Dispose(Value);
    end);
end;

procedure CheckNestedAnonymousCapture;
var
  Outer: TProc;
begin
  Outer := procedure
    begin
      var Value: PManagedRecord;
      var Reader: TProc;
      New(Value);
      FillAndCheck(Value, 50);
      Reader := procedure
        begin
          Check((Value^.Text = 'managed') and (Value^.Values[1] = 51), 54);
        end;
      Reader();
      Reader := nil;
      Dispose(Value);
      Check(TTracked.Alive = 0, 55);
    end;
  Outer();
end;

procedure CheckAnonymousFunctionResult;
var
  Factory: TFactory;
  Value: PManagedRecord;
begin
  Factory := function: PManagedRecord
    begin
      var Local: PManagedRecord;
      New(Local);
      FillAndCheck(Local, 60);
      Result := Local;
    end;
  Value := Factory();
  Check((Value^.Text = 'managed') and (Value^.Values[0] = 60), 64);
  Dispose(Value);
  Check(TTracked.Alive = 0, 65);
end;

{$ifdef FPC}
procedure CheckExpressionFormStillWorks;
var
  Callback: TProc;
begin
  Callback := procedure
    begin
      var Value: PManagedRecord;
      Value := New(PManagedRecord);
      FillAndCheck(Value, 70);
      Dispose(Value);
      Check(TTracked.Alive = 0, 74);
    end;
  Callback();
end;
{$endif}

begin
  TTracked.Alive := 0;
  CheckRegularStatementForm;
  CheckAssignedAnonymousInlineLocal;
  CheckAssignedAnonymousClassicLocal;
  CheckArgumentAnonymous;
  CheckNestedAnonymousCapture;
  CheckAnonymousFunctionResult;
{$ifdef FPC}
  CheckExpressionFormStillWorks;
{$endif}
  Check(TTracked.Alive = 0, 80);
end.
