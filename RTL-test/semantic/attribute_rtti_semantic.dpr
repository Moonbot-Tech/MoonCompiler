program attribute_rtti_semantic;

{ dvl-0037 + dvl-0040: with the Delphi extended RTTI profile the
  TRttiContext serves methods and public properties with their
  attributes, exactly like DCC64: attributes bound to a type, a field, a
  method and a public property all read back, and GetMethods enumerates
  the declared public methods.  The RTTI EXPLICIT directive governs the
  attribute payload: a published property whose visibility is excluded
  from the PROPERTIES set stays enumerable (the classic M+ contract) but
  reads back no attributes, and widening the set back restores them.
  All expectations below are DCC64-measured. }

{$APPTYPE CONSOLE}

uses
  {$ifdef FPC}
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  {$endif UNIX}
  {$endif FPC}
  SysUtils, Rtti;

type
  MarkAttribute = class(TCustomAttribute)
  public
    FTag: Integer;
    constructor Create(N: Integer);
  end;

  [Mark(1)]
  TBox = class
  public
    [Mark(2)] FField: Integer;
    [Mark(4)] procedure Poke;
    [Mark(16)] class function Zap: Integer;
  private
    FSlot: Integer;
  public
    [Mark(8)] property Slot: Integer read FSlot write FSlot;
  end;

{$RTTI EXPLICIT METHODS([vcPublic]) PROPERTIES([vcPublic]) FIELDS([vcPublic])}
{$M+}
type
  TNarrow = class
  private
    FSlot: Integer;
  published
    [Mark(11)]
    property Slot: Integer read FSlot write FSlot;
  end;
{$M-}

{$RTTI EXPLICIT METHODS([vcPublic,vcPublished]) PROPERTIES([vcPublic,vcPublished]) FIELDS([vcPrivate,vcProtected,vcPublic,vcPublished])}
{$M+}
type
  TWide = class
  private
    FSlot: Integer;
  published
    [Mark(11)]
    property Slot: Integer read FSlot write FSlot;
  end;
{$M-}

constructor MarkAttribute.Create(N: Integer);
begin
  inherited Create;
  FTag := N;
end;

procedure TBox.Poke;
begin
end;

class function TBox.Zap: Integer;
begin
  Result := 0;
end;

procedure Check(Condition: Boolean; const MessageText: string);
begin
  If not Condition then
    raise Exception.Create(MessageText);
end;

function SumAttrs(const A: TArray<TCustomAttribute>): Integer;
var
  X: TCustomAttribute;
begin
  Result := 0;
  for X in A do
    If X is MarkAttribute then
      Inc(Result, MarkAttribute(X).FTag);
end;

procedure CheckTargets;
var
  Ctx: TRttiContext;
  T: TRttiType;
  M: TRttiMethod;
  P: TRttiProperty;
  F: TRttiField;
  Total, MCount: Integer;
begin
  Ctx := TRttiContext.Create;
  try
    T := Ctx.GetType(TypeInfo(TBox));
    Check(SumAttrs(T.GetAttributes) = 1, 'type attribute');
    Total := 0;
    for F in T.GetFields do
      Inc(Total, SumAttrs(F.GetAttributes));
    Check(Total = 2, 'field attribute');
    Total := 0; MCount := 0;
    for M in T.GetMethods do begin
      If M.Parent = T then Inc(MCount);
      Inc(Total, SumAttrs(M.GetAttributes));
    end;
    Check(MCount = 2, 'declared method count');
    Check(Total = 20, 'method attributes');
    Total := 0;
    for P in T.GetProperties do
      Inc(Total, SumAttrs(P.GetAttributes));
    Check(Total = 8, 'public property attribute');
  finally
    Ctx.Free;
  end;
end;

procedure CheckDirective(TI: Pointer; ExpectedTags: Integer; const Name: string);
var
  Ctx: TRttiContext;
  T: TRttiType;
  P: TRttiProperty;
  Props, Tags: Integer;
begin
  Ctx := TRttiContext.Create;
  try
    T := Ctx.GetType(TI);
    Props := 0;
    Tags := 0;
    for P in T.GetProperties do begin
      Inc(Props);
      Inc(Tags, SumAttrs(P.GetAttributes));
    end;
    Check(Props = 1, Name + ': published property stays enumerable');
    Check(Tags = ExpectedTags, Name + ': attribute payload');
  finally
    Ctx.Free;
  end;
end;

begin
  try
    CheckTargets;
    CheckDirective(TypeInfo(TNarrow), 0, 'explicit public');
    CheckDirective(TypeInfo(TWide), 11, 'back to published');
    WriteLn('ATTRIBUTE_RTTI_OK');
  except
    on E: Exception do begin
      WriteLn('ATTRIBUTE_RTTI_FAIL ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
