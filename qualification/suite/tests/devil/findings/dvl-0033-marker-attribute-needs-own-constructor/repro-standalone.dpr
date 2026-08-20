program attr_rtti_field;
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

type
  TBox = class
  public
    [Mark(8)]
    FSlot: Integer;
  end;

var
  Ctx: TRttiContext;
  Total: Integer;
begin
  Ctx := TRttiContext.Create;
  Total := 0;
  for var F in Ctx.GetType(TBox).GetFields do
    Total := Total + Sum(F.GetAttributes);
  WriteLn('field = ', Total);
end.