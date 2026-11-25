{$ifdef BREADTH_HAS_PRODUCT_IO}
{ Runtime import metadata selects a route, handler and input field. }

type
  TBreadthImportStepAttribute = class(TCustomAttribute)
  public
    Tag: string;
    Code: Int64;
    constructor Create(const ATag: string; ACode: Int64);
  end;

  {$RTTI EXPLICIT METHODS([vcPublic]) PROPERTIES([vcPublished])}
  [TBreadthImportStepAttribute('record', 9007199254740993)]
  TBreadthAnnotatedImport = class(TPersistent)
  private
    FSource: string;
  public
    [TBreadthImportStepAttribute('normalize' + #0 + #$03BB, -810000000037)]
    procedure Normalize(const Value: string);
  published
    [TBreadthImportStepAttribute('source', 9007199254740995)]
    property Source: string read FSource write FSource;
  end;
  {$RTTI INHERIT}

constructor TBreadthImportStepAttribute.Create(const ATag: string; ACode: Int64);
begin
  Tag := ATag;
  Code := ACode;
end;

procedure TBreadthAnnotatedImport.Normalize(const Value: string);
begin
  FSource := Trim(Value);
end;

function BreadthStepMatches(const Attrs: TArray<TCustomAttribute>; const Tag: string; Code: Int64): Boolean;
begin
  Result := (Length(Attrs) = 1) and (Attrs[0] is TBreadthImportStepAttribute)
    and (TBreadthImportStepAttribute(Attrs[0]).Tag = Tag) and (TBreadthImportStepAttribute(Attrs[0]).Code = Code);
end;

procedure RunBreadthImportAnnotations;
var
  Context: TRttiContext;
  Info: TRttiType;
  Handler: TRttiMethod;
  Member: TRttiProperty;
  Args: TArray<TRttiParameter>;
begin
  Context := TRttiContext.Create;
  try
    Info := Context.GetType(TBreadthAnnotatedImport);
    Check((Info <> nil) and BreadthStepMatches(Info.GetAttributes, 'record', 9007199254740993),
      'breadth-import-annotations-constructor-retains-exact-64-bit-class-code');
    If Info = nil then
      Exit;
    Member := Info.GetProperty('Source');
    Check((Member <> nil) and BreadthStepMatches(Member.GetAttributes, 'source', 9007199254740995),
      'breadth-import-annotations-property-metadata-selects-source-field');
    Handler := Info.GetMethod('Normalize');
    Check((Handler <> nil) and BreadthStepMatches(Handler.GetAttributes, 'normalize' + #0 + #$03BB, -810000000037),
      'breadth-import-annotations-handler-keeps-counted-unicode-tag-and-negative-code');
    If Handler = nil then
      Exit;
    Args := Handler.GetParameters;
    Check((Length(Args) = 1) and (Args[0].Name = 'Value') and (Args[0].ParamType.Handle = TypeInfo(string)) and (pfConst in Args[0].Flags),
      'breadth-import-annotations-handler-exposes-the-exact-parameter-declaration');
    Mix(UInt64(Length(Args)));
  finally
    Context.Free;
  end;
end;
{$endif}
