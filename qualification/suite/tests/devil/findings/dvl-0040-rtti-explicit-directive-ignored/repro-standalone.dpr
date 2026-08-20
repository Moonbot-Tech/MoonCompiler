program rtti_explicit_public;
{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch anonymousfunctions}
  {$modeswitch functionreferences}
  {$modeswitch INLINEVARS}
{$endif}
{$APPTYPE CONSOLE}
uses
{$ifdef FPC}
  mormot.core.fpcx64mm,
{$endif}
  SysUtils, TypInfo, Rtti;

type
  MarkAttribute = class(TCustomAttribute)
  public
    Tag: Integer;
    constructor Create(ATag: Integer);
  end;

constructor MarkAttribute.Create(ATag: Integer);
begin
  inherited Create;
  Tag := ATag;
end;

function Sum(const Items: TArray<TCustomAttribute>): Integer;
var
  A: TCustomAttribute;
begin
  Result := 0;
  for A in Items do
    if A is MarkAttribute then
      Result := Result + MarkAttribute(A).Tag;
end;

{$RTTI EXPLICIT METHODS([vcPublic]) PROPERTIES([vcPublic]) FIELDS([vcPublic])}
{$M+}
type
  TBox = class
  private
    FSlot: Integer;
  published
    [Mark(11)]
    property Slot: Integer read FSlot write FSlot;
  end;
{$M-}

var
  Ctx: TRttiContext;
  Total, Count: Integer;
begin
  Ctx := TRttiContext.Create;
  Total := 0;
  Count := 0;
  for var P in Ctx.GetType(TBox).GetProperties do
  begin
    Inc(Count);
    Total := Total + Sum(P.GetAttributes);
  end;
  WriteLn('props = ', Count, ' tags = ', Total);
end.