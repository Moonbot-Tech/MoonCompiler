program rtti_gettypes;

{$mode delphi}
uses
{$ifdef UNIX}
  cthreads,
{$endif}
  Classes,
  SysUtils,
  TypInfo,
  Rtti,
  rtti_catalog_bridge,
  rtti_catalog_base,
  rtti_catalog_generic,
  rtti_catalog_plain,
  rtti_catalog_runtime_tables,
  rtti_extended_dependencies,
  rtti_delphi_defaults;

type
  {$RTTI EXPLICIT FIELDS([vcPrivate,vcPublic])}

  [CommandId(4)]
  TProgramCommand = class(TCommandBase)
  private
    FProgramSecret: Integer;
  end;

  TProgramEnum = (peZero,peOne);
  TProgramRecord = record
    Value: Integer;
  end;
  TProgramArray = array[0..2] of Integer;
  TProgramProc = procedure(Value: Integer);

  TUnusedVirtualEnumerator<T> = class
    procedure MoveNext; virtual;
  end;

  TUnusedVirtualEnumerable = class
    class function List<T>: TUnusedVirtualEnumerator<T>;
  end;

  TUnusedVirtualConsumer<T> = class
    procedure Run;
  end;

  TGetTypesThread = class(TThread)
  private
    FError: string;
  protected
    procedure Execute; override;
  public
    property Error: string read FError;
  end;

procedure TUnusedVirtualEnumerator<T>.MoveNext;
begin
end;

class function TUnusedVirtualEnumerable.List<T>: TUnusedVirtualEnumerator<T>;
begin
  Result:=nil;
end;

procedure TUnusedVirtualConsumer<T>.Run;
begin
  TUnusedVirtualEnumerable.List<T>();
end;

procedure Fail(const MessageText: string);
begin
  Writeln('FAIL: ',MessageText);
  Halt(1);
end;

function FindType(const Types: TArray<TRttiType>; const Name: string): TRttiType;
var
  RttiType: TRttiType;
begin
  Result:=nil;
  for RttiType in Types do
    if RttiType.Name=Name then
      begin
        if Assigned(Result) then
          Fail('duplicate type name '+Name);
        Result:=RttiType;
      end;
end;

function HasTypeHandle(const Types: TArray<TRttiType>; TypeInfo: PTypeInfo): Boolean;
var
  RttiType: TRttiType;
begin
  Result:=False;
  for RttiType in Types do
    if RttiType.Handle=TypeInfo then
      Exit(True);
end;

function CommandIdValue(RttiType: TRttiType): Integer;
var
  Attribute: TCustomAttribute;
begin
  Result:=-1;
  for Attribute in RttiType.GetAttributes do
    if Attribute is CommandId then
      begin
        if Result<>-1 then
          Fail('duplicate CommandId on '+RttiType.Name);
        Result:=CommandId(Attribute).Value;
      end;
end;

function CommandGroupValue(RttiType: TRttiType): Integer;
var
  Attribute: TCustomAttribute;
begin
  Result:=-1;
  while Assigned(RttiType) do
    begin
      for Attribute in RttiType.GetAttributes do
        if Attribute is CommandGroup then
          Exit(CommandGroup(Attribute).Value);
      RttiType:=RttiType.BaseType;
    end;
end;

procedure CheckCatalog;
var
  Context: TRttiContext;
  Types,
  TypesAgain: TArray<TRttiType>;
  RttiType,
  DirectType: TRttiType;
  Field: TRttiField;
  CommandCount,
  I,
  J: Integer;
  Found: Boolean;
begin
  Context:=TRttiContext.Create(False);
  try
    Types:=Context.GetTypes;
    if Length(Types)=0 then
      Fail('empty catalog');

    for I:=0 to High(Types) do
      begin
        if not Assigned(Types[I]) then
          Fail('nil RTTI entry');
        for J:=0 to I-1 do
          if Types[I].Handle=Types[J].Handle then
            Fail('duplicate RTTI handle for '+Types[I].Name);
      end;

    DirectType:=FindType(Types,'TDirectCommand');
    if not(DirectType is TRttiInstanceType) then
      Fail('TDirectCommand is missing or has wrong RTTI kind');
    if not TRttiInstanceType(DirectType).MetaclassType.InheritsFrom(TCommandBase) then
      Fail('TDirectCommand lost its class identity');
    if CommandIdValue(DirectType)<>1 then
      Fail('TDirectCommand attribute mismatch');
    Field:=DirectType.GetField('FSecret');
    if not Assigned(Field) then
      Fail('explicit private field RTTI is missing');
    if not Assigned(DirectType.GetField('FVisible')) then
      Fail('explicit public field RTTI is missing');

    RttiType:=FindType(Types,'TTransitiveCommand');
    if not(RttiType is TRttiInstanceType) or (CommandIdValue(RttiType)<>3) then
      Fail('transitive command discovery mismatch');
    if not Assigned(RttiType.GetField('FTransitiveSecret')) then
      Fail('transitive private field RTTI is missing');

    RttiType:=FindType(Types,'TProgramCommand');
    if not(RttiType is TRttiInstanceType) or (CommandIdValue(RttiType)<>4) then
      Fail('program command discovery mismatch');
    if not Assigned(RttiType.GetField('FProgramSecret')) then
      Fail('program private field RTTI is missing');

    if not Assigned(FindType(Types,'TCatalogEnum')) then
      Fail('enum is missing');
    if not Assigned(FindType(Types,'TCatalogRecord')) then
      Fail('record is missing');
    if not Assigned(FindType(Types,'TUniqueInteger')) then
      Fail('distinct alias is missing');
    if not HasTypeHandle(Types,TypeInfo(TUniqueCommand)) then
      Fail('unique class alias lost its parent RTTI');
    if not HasTypeHandle(Types,TypeInfo(ICatalogInterface)) then
      Fail('interface RTTI is missing');
    if not HasTypeHandle(Types,ConcreteRecordTypeInfo) then
      Fail('concrete generic record RTTI is missing');
    if not Assigned(FindType(Types,'TProgramEnum')) or
       not Assigned(FindType(Types,'TProgramRecord')) or
       not Assigned(FindType(Types,'TProgramArray')) or
       not Assigned(FindType(Types,'TProgramProc')) then
      Fail('program-scope non-class RTTI is missing');
    RttiType:=FindType(Types,'TPlainCatalogClass');
    if not Assigned(RttiType) or (CommandIdValue(RttiType)<>77) then
      Fail('class attribute without an explicit RTTI directive is missing');
    if Assigned(FindType(Types,'TUnlinkedCommand')) then
      Fail('unlinked unit leaked into catalog');
    if HasTypeHandle(Types,TypeInfo(TDirectCommand.TNestedCatalogClass)) then
      Fail('nested type leaked into the public catalog');
    if HasTypeHandle(Types,ImplementationCatalogTypeInfo) then
      Fail('implementation type leaked into the public catalog');

    CommandCount:=0;
    for RttiType in Types do
      if (RttiType is TRttiInstanceType) and
         TRttiInstanceType(RttiType).MetaclassType.InheritsFrom(TCommandBase) then
        Inc(CommandCount);
    if CommandCount<>ExpectedCommandCount then
      Fail(Format('command count mismatch: %d',[CommandCount]));

    if not Assigned(Context.GetType(ImplementationCatalogTypeInfo)) then
      Fail('implementation type could not be loaded directly');
    TypesAgain:=Context.GetTypes;
    if Length(TypesAgain)<>Length(Types) then
      Fail('repeated GetTypes changed catalog size');
    if HasTypeHandle(TypesAgain,ImplementationCatalogTypeInfo) then
      Fail('direct GetType polluted the compiler catalog');
    for I:=0 to High(Types) do
      begin
        Found:=False;
        for J:=0 to High(TypesAgain) do
          if TypesAgain[J].Handle=Types[I].Handle then
            begin
              Found:=True;
              Break;
            end;
        if not Found then
          Fail('repeated GetTypes lost a handle');
      end;
  finally
    Context.Free;
  end;
end;

procedure CheckDefaultRegistry;
var
  Context: TRttiContext;
  Types: TArray<TRttiType>;
  RttiType: TRttiType;
  Keys: array[0..255] of Boolean;
  Key,
  CommandCount: Integer;
begin
  FillChar(Keys,SizeOf(Keys),0);
  Context:=TRttiContext.Create;
  try
    Types:=Context.GetTypes;
    CommandCount:=0;
    for RttiType in Types do
      if (RttiType is TRttiInstanceType) and
         TRttiInstanceType(RttiType).MetaclassType.InheritsFrom(TCommandBase) then
        begin
          if CommandIdValue(RttiType)<0 then
            Fail('registry command has no direct ID: '+RttiType.Name);
          if CommandGroupValue(RttiType)<>7 then
            Fail('registry command lost inherited group: '+RttiType.Name);
          Key:=CommandIdValue(RttiType);
          if Keys[Key] then
            Fail('duplicate registry key');
          Keys[Key]:=True;
          Inc(CommandCount);
        end;
    if CommandCount<>ExpectedCommandCount then
      Fail(Format('default registry count mismatch: %d',[CommandCount]));
  finally
    Context.Free;
  end;
end;

procedure CheckDelphiDefaults;
var
  Context: TRttiContext;
  RttiType: TRttiType;
  Field: TRttiField;
  Attribute: TCustomAttribute;
  Value: TValue;
  ArrayValue: TValue;
  BooleanPair: TBooleanPair;
  FoundAttribute: Boolean;
begin
  Context:=TRttiContext.Create;
  try
    RttiType:=Context.GetType(TypeInfo(TDefaultRttiClass));
    if not Assigned(RttiType) then
      Fail('default RTTI class is missing');
    Field:=RttiType.GetField('Enabled');
    if not Assigned(Field) then
      Fail('Delphi default public-field RTTI is missing');
    if Field.FieldType.Handle<>TypeInfo(Boolean) then
      Fail('Boolean field lost its type identity');
    if Field.FieldType.TypeKind<>tkEnumeration then
      Fail('Boolean RTTI is not exposed as a Delphi enumeration');
    if not(Field.FieldType is TRttiEnumerationType) then
      Fail('Boolean RTTI has the wrong facade class');
    if TRttiEnumerationType(Field.FieldType).UnderlyingType<>Field.FieldType then
      Fail('Boolean RTTI has the wrong underlying type');
    if Length(TRttiEnumerationType(Field.FieldType).GetNames)<>2 then
      Fail('Boolean RTTI has the wrong name table');
    Value:=TValue.From<Boolean>(True);
    if Value.Kind<>tkEnumeration then
      Fail('Boolean TValue is not exposed as a Delphi enumeration');
    if not Value.AsBoolean then
      Fail('Boolean TValue lost its value');
    if Value.ToString<>'True' then
      Fail('Boolean TValue lost its textual representation');
    if not Boolean(Value.AsVariant) then
      Fail('Boolean TValue lost its Variant conversion');
    BooleanPair[0]:=False;
    BooleanPair[1]:=False;
    ArrayValue:=TValue.From<TBooleanPair>(BooleanPair);
    ArrayValue.SetArrayElement(1,Value);
    if not ArrayValue.GetArrayElement(1).AsBoolean then
      Fail('Boolean TValue array assignment lost its raw storage kind');
    FoundAttribute:=False;
    for Attribute in Field.GetAttributes do
      if Attribute is TDefaultFieldAttribute then
        FoundAttribute:=True;
    if not FoundAttribute then
      Fail('default public-field attribute is missing');
  finally
    Context.Free;
  end;
end;

procedure TGetTypesThread.Execute;
var
  I: Integer;
  Context: TRttiContext;
  Types: TArray<TRttiType>;
begin
  try
    for I:=1 to 100 do
      begin
        Context:=TRttiContext.Create(False);
        try
          Types:=Context.GetTypes;
          if not Assigned(FindType(Types,'TTransitiveCommand')) then
            raise Exception.Create('thread lost transitive type');
        finally
          Context.Free;
        end;
      end;
  except
    on E: Exception do
      FError:=E.ClassName+': '+E.Message;
  end;
end;

procedure CheckThreads;
var
  Threads: array[0..7] of TGetTypesThread;
  I: Integer;
begin
  TRttiContext.DropContext;
  for I:=Low(Threads) to High(Threads) do
    Threads[I]:=TGetTypesThread.Create(False);
  for I:=Low(Threads) to High(Threads) do
    begin
      Threads[I].WaitFor;
      if Threads[I].Error<>'' then
        Fail(Threads[I].Error);
      Threads[I].Free;
    end;
end;

procedure CheckDropContext;
var
  Context: TRttiContext;
  RttiType: TRttiType;
begin
  TRttiContext.DropContext;
  Context:=TRttiContext.Create;
  try
    RttiType:=FindType(Context.GetTypes,'TDirectCommand');
    if not Assigned(RttiType) or (CommandIdValue(RttiType)<>1) then
      Fail('DropContext lost catalog RTTI');
  finally
    Context.Free;
  end;
end;

begin
  if not CheckExtendedDependencies then
    Fail('extended RTTI dependency linkage failed');
  if not TouchNonPublicCatalogTypes then
    Fail('non-public type linkage check failed');
  if CatalogResource<>'resource-ok' then
    Fail('resourcestring table regression');
  CatalogThreadValue:=17;
  if CatalogThreadValue<>17 then
    Fail('threadvar table regression');
  CheckCatalog;
  CheckDefaultRegistry;
  CheckDelphiDefaults;
  CheckThreads;
  CheckDropContext;
  Writeln('RTTI_GETTYPES_PASS');
end.
