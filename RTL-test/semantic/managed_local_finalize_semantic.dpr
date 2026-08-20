program managed_local_finalize_semantic;

{$ifdef FPC}
{$mode delphi}{$H+}
{$endif FPC}

uses
  {$ifdef FPC}
  mormot.core.fpcx64mm,
  {$endif FPC}
  {$ifdef UNIX}
  cthreads,
  cwstring,
  {$endif UNIX}
  SysUtils;

type
  ITracked = interface
    ['{6A520FB5-663A-4B6C-B89B-E63C8CD71B10}']
    function Value: Integer;
  end;

  TTracked = class(TInterfacedObject, ITracked)
  private
    FValue: Integer;
  public
    constructor Create(AValue: Integer);
    destructor Destroy; override;
    function Value: Integer;
  end;

  TTrackedArray = array of ITracked;
  TNestedTrackedArray = array of TTrackedArray;

var
  CreatedCount: Integer;
  DestroyedCount: Integer;

procedure Check(Condition: Boolean; const MessageText: string);
begin
  If not Condition then
    raise Exception.Create(MessageText);
end;

constructor TTracked.Create(AValue: Integer);
begin
  inherited Create;
  Inc(CreatedCount);
  FValue := AValue;
end;

destructor TTracked.Destroy;
begin
  Inc(DestroyedCount);
  inherited Destroy;
end;

function TTracked.Value: Integer;
begin
  Result := FValue;
end;

procedure NormalExit;
var
  Values: TTrackedArray;
  AliasValues: TTrackedArray;
begin
  SetLength(Values, 2);
  Values[0] := TTracked.Create(10);
  Values[1] := TTracked.Create(20);
  AliasValues := Values;
  Check((AliasValues[0].Value = 10) and (AliasValues[1].Value = 20),
    'dynamic array alias contents');
end;

procedure EarlyExit;
var
  Values: TTrackedArray;
begin
  SetLength(Values, 1);
  Values[0] := TTracked.Create(30);
  Exit;
end;

procedure ExplicitFinalize;
var
  Values: TTrackedArray;
begin
  SetLength(Values, 1);
  Values[0] := TTracked.Create(40);
  Finalize(Values);
  Check(Length(Values) = 0, 'Finalize clears dynamic array');
end;

procedure NestedArrays;
var
  Values: TNestedTrackedArray;
begin
  SetLength(Values, 2);
  SetLength(Values[0], 1);
  SetLength(Values[1], 1);
  Values[0][0] := TTracked.Create(50);
  Values[1][0] := TTracked.Create(60);
end;

procedure ExceptionalExit;
var
  Values: TTrackedArray;
begin
  SetLength(Values, 2);
  Values[0] := TTracked.Create(70);
  Values[1] := TTracked.Create(80);
  raise EAbort.Create('expected');
end;

procedure Run;
var
  Raised: Boolean;
begin
  NormalExit;
  Check((CreatedCount = 2) and (DestroyedCount = 2),
    'normal exit releases aliased dynamic array exactly once');

  EarlyExit;
  Check((CreatedCount = 3) and (DestroyedCount = 3),
    'Exit releases dynamic array');

  ExplicitFinalize;
  Check((CreatedCount = 4) and (DestroyedCount = 4),
    'explicit and implicit finalization do not double release');

  NestedArrays;
  Check((CreatedCount = 6) and (DestroyedCount = 6),
    'nested dynamic arrays release every managed element');

  Raised := False;
  try
    ExceptionalExit;
  except
    on E: EAbort do
      Raised := E.Message = 'expected';
  end;
  Check(Raised, 'exception propagated');
  Check((CreatedCount = 8) and (DestroyedCount = 8),
    'exception unwinding releases dynamic array');
end;

begin
  try
    Run;
    WriteLn('MANAGED_LOCAL_FINALIZE_OK');
  except
    on E: Exception do
    begin
      WriteLn('MANAGED_LOCAL_FINALIZE_FAIL ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
