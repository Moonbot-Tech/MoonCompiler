program attr_rtti;
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

type
  [Mark(7)]
  TBox = class
  public
    [Mark(8)]
    FSlot: Integer;
    [Mark(9)]
    procedure Touch;
  end;

procedure TBox.Touch;
begin
end;

var
  Ctx: TRttiContext;
  T: TRttiType;
  A: TCustomAttribute;
  Seen: Integer;
begin
  Seen := 0;
  Ctx := TRttiContext.Create;
  T := Ctx.GetType(TBox);
  for A in T.GetAttributes do
    if A is MarkAttribute then
      Seen := Seen + MarkAttribute(A).Tag;
  for var F in T.GetFields do
    for A in F.GetAttributes do
      if A is MarkAttribute then
        Seen := Seen + MarkAttribute(A).Tag;
  for var M in T.GetMethods do
    for A in M.GetAttributes do
      if A is MarkAttribute then
        Seen := Seen + MarkAttribute(A).Tag;
  WriteLn('attribute tags seen = ', Seen);
end.