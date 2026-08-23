program attribute_positions_semantic;

{ dvl-0032: Delphi accepts attributes before a parameter, before the name
  of an inline variable and before a class var section; the bare [ref]
  modifier keeps its meaning next to attribute brackets.  All three
  positions were parse rejects for us.  Locals and class vars carry no
  RTTI, so the pin checks that every position compiles and runs;
  parameter attributes additionally bind to the parameter symbols for the
  extended-RTTI writer to pick up.

  No mode directive on purpose: a mode directive resets the driver
  modeswitches, and the pin needs the product profile's inline vars. }

{$APPTYPE CONSOLE}

uses
  {$ifdef FPC}
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  {$endif UNIX}
  {$endif FPC}
  SysUtils;

type
  MarkAttribute = class(TCustomAttribute)
  public
    constructor Create; overload;
    constructor Create(N: Integer); overload;
  end;

  THolder = class
  public
    [Mark] class var CV: Integer;
  end;

constructor MarkAttribute.Create;
begin
  inherited Create;
end;

constructor MarkAttribute.Create(N: Integer);
begin
  inherited Create;
end;

procedure Check(Condition: Boolean; const MessageText: string);
begin
  If not Condition then
    raise Exception.Create(MessageText);
end;

procedure TakeAttr([Mark] X: Integer; [Mark(2)] const Y: string);
begin
  Check((X = 7) and (Y = 'ok'), 'attributed parameters');
end;

procedure TakeRef(const [ref] R: Integer);
begin
  Check(R = 5, 'const [ref] parameter');
end;

procedure TakeRef2([ref] const R: Integer);
begin
  Check(R = 6, '[ref] const parameter');
end;

procedure TakeMulti([Mark] A, B: Integer);
begin
  Check((A = 8) and (B = 9), 'attribute over a name list');
end;

procedure RunInlineVars;
begin
  var [Mark] Slot: Integer;
  Slot := 1;
  Check(Slot = 1, 'attributed inline var');
  var [Mark(3)] S2 := 42;
  Check(S2 = 42, 'attributed inferred inline var');
end;

begin
  try
    RunInlineVars;
    TakeAttr(7, 'ok');
    TakeRef(5);
    TakeRef2(6);
    TakeMulti(8, 9);
    THolder.CV := 11;
    Check(THolder.CV = 11, 'attributed class var');
    WriteLn('ATTRIBUTE_POSITIONS_OK');
  except
    on E: Exception do begin
      WriteLn('ATTRIBUTE_POSITIONS_FAIL ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
