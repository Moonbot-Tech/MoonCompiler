program dictionary_factory_cache_semantic;

{ A user hash factory can return a stable or changing custom comparer.
  Neither its lifetime nor matching its own Default makes its equality
  the built-in equality required by the flat path. Both objects remain
  alive, so this does not depend on heap reuse or a dangling pointer. }

{$mode delphi}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  cwstring,
  {$endif UNIX}
  SysUtils, TypInfo, Generics.Defaults, Generics.Collections;

type
  TModuloComparer = class(TInterfacedObject, IEqualityComparer<Integer>)
  public
    destructor Destroy; override;
    function Equals(const ALeft, ARight: Integer): Boolean; reintroduce;
    function GetHashCode(const AValue: Integer): Integer; reintroduce;
  end;

  TChangingService = class(THashService)
  public
    class function LookupEqualityComparer(AInfo: PTypeInfo; ASize: SizeInt): Pointer; override;
  end;

  { It must be the exact built-in factory, not a descendant, that is cached. }
  TChangingFactory = class(TGenericsHashFactory)
  public
    class function GetHashService: THashServiceClass; override;
  end;

  TFactoryDictionary = TOpenAddressingLP<Integer, Integer, TChangingFactory>;
  TInheritedHashFactory = class(TDefaultHashFactory);
  TIntPair = TPair<Integer, Integer>;

var
  Comparers: array[0..1] of IEqualityComparer<Integer>;
  LookupCalls, DestroyedComparers, Failures, Checks: Integer;
  StableFactory: Boolean;

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  Inc(Checks);
  if not ACondition then
  begin
    Inc(Failures);
    WriteLn('FAIL ', AMessage);
  end;
end;

destructor TModuloComparer.Destroy;
begin
  Inc(DestroyedComparers);
  inherited Destroy;
end;

function TModuloComparer.Equals(const ALeft, ARight: Integer): Boolean;
begin
  Result := ALeft mod 10 = ARight mod 10;
end;

function TModuloComparer.GetHashCode(const AValue: Integer): Integer;
begin
  Result := AValue mod 10;
end;

class function TChangingService.LookupEqualityComparer(AInfo: PTypeInfo; ASize: SizeInt): Pointer;
begin
  if StableFactory then
    Result := Pointer(Comparers[0])
  else
    Result := Pointer(Comparers[LookupCalls mod 2]);
  Inc(LookupCalls);
end;

class function TChangingFactory.GetHashService: THashServiceClass;
begin
  Result := TChangingService;
end;

procedure Exercise(ADictionary: TFactoryDictionary; const AName: string);
var
  Value: Integer;
begin
  try
    Check(not ADictionary.Flat, AName + ': custom comparer stays active');
    ADictionary.AddOrSetValue(1, 1);
    ADictionary.AddOrSetValue(11, 11);
    Check(ADictionary.Count = 1, AName + ': equal keys share one entry');
    Check(ADictionary.TryGetValue(21, Value) and (Value = 11), AName + ': custom lookup');
    ADictionary.Remove(31);
    Check(ADictionary.Count = 0, AName + ': custom removal');
  finally
    ADictionary.Free;
  end;
end;

procedure RunFactoryCases(AStable: Boolean);
var
  I: Integer;
  Items: array[0..1] of TIntPair;
  Collection: TList<TIntPair>;
begin
  StableFactory := AStable;
  DestroyedComparers := 0;
  Comparers[0] := TModuloComparer.Create;
  Comparers[1] := TModuloComparer.Create;
  Items[0] := TIntPair.Create(1, 1);
  Items[1] := TIntPair.Create(11, 11);
  Collection := TList<TIntPair>.Create;
  Collection.Add(Items[0]);
  Collection.Add(Items[1]);
  try
    for I := 1 to 4 do
      Exercise(TFactoryDictionary.Create, 'default ' + IntToStr(I));
    Exercise(TFactoryDictionary.Create(32), 'capacity');
    Exercise(TFactoryDictionary.Create(IEqualityComparer<Integer>(nil)), 'nil comparer');
    Exercise(TFactoryDictionary.Create(32, nil), 'capacity and nil comparer');
    Exercise(TFactoryDictionary.Create(Items), 'array');
    Exercise(TFactoryDictionary.Create(Items, nil), 'array and nil comparer');
    Exercise(TFactoryDictionary.Create(TEnumerable<TIntPair>(Collection)), 'collection');
    Exercise(TFactoryDictionary.Create(TEnumerable<TIntPair>(Collection), nil), 'collection and nil comparer');
    {$IFDEF ENABLE_METHODS_WITH_TEnumerableWithPointers}
    Exercise(TFactoryDictionary.Create(TEnumerableWithPointers<TIntPair>(Collection)), 'pointer collection');
    Exercise(TFactoryDictionary.Create(TEnumerableWithPointers<TIntPair>(Collection), nil),
      'pointer collection and nil comparer');
    {$ENDIF}

    { At this call the factory default is object zero, so explicit object
      one has custom semantics even if an earlier cache remembers it. }
    LookupCalls := 0;
    Exercise(TFactoryDictionary.Create(Comparers[1]), 'explicit comparer');
    LookupCalls := 0;
    Exercise(TFactoryDictionary.Create(32, Comparers[1]), 'explicit comparer with capacity');
    LookupCalls := 0;
    Exercise(TFactoryDictionary.Create(Items, Comparers[1]), 'explicit comparer with array');
    LookupCalls := 0;
    Exercise(TFactoryDictionary.Create(TEnumerable<TIntPair>(Collection), Comparers[1]),
      'explicit comparer with collection');
    {$IFDEF ENABLE_METHODS_WITH_TEnumerableWithPointers}
    LookupCalls := 0;
    Exercise(TFactoryDictionary.Create(TEnumerableWithPointers<TIntPair>(Collection), Comparers[1]),
      'explicit comparer with pointer collection');
    {$ENDIF}
  finally
    Collection.Free;
    Comparers[0] := nil;
    Comparers[1] := nil;
  end;
  Check(DestroyedComparers = 2, 'no retained comparer references');
end;

procedure CheckBuiltInFactories;
var
  Integers: TOpenAddressingLP<Integer, Integer, TDelphiHashFactory>;
  Strings: TOpenAddressingLP<UnicodeString, Integer, TxxHash32HashFactory>;
  InheritedFactory: TOpenAddressingLP<Integer, Integer, TInheritedHashFactory>;
begin
  Integers := TOpenAddressingLP<Integer, Integer, TDelphiHashFactory>.Create;
  Strings := TOpenAddressingLP<UnicodeString, Integer, TxxHash32HashFactory>.Create;
  InheritedFactory := TOpenAddressingLP<Integer, Integer, TInheritedHashFactory>.Create;
  try
    Check(Integers.Flat, 'built-in integer factory stays flat');
    Check(Strings.Flat, 'built-in string factory stays flat');
    Check(InheritedFactory.Flat, 'inherited built-in factory stays flat');
    Integers.Add(1, 7);
    Strings.Add('key', 8);
    InheritedFactory.Add(2, 9);
    Check(Integers[1] = 7, 'built-in integer lookup');
    Check(Strings['key'] = 8, 'built-in string lookup');
    Check(InheritedFactory[2] = 9, 'inherited built-in lookup');
  finally
    InheritedFactory.Free;
    Strings.Free;
    Integers.Free;
  end;
end;

begin
  RunFactoryCases(False);
  RunFactoryCases(True);
  CheckBuiltInFactories;
  WriteLn('Checks=', Checks, ' Failures=', Failures);
  if Failures <> 0 then
    Halt(1);
  WriteLn('DICTIONARY_FACTORY_CACHE_PASS');
end.
