program rtl_api_comparer_factory_contracts;

{$mode delphiunicode}

uses
  SysUtils,
  Generics.Defaults,
  TypInfo;

type
  TProbeFactory = class(TGenericsHashFactory)
  public
    class var ServiceCalls: Integer;
    class var HashCalls: Integer;
    class function GetHashService: THashServiceClass; override;
    class function GetHashCode(AKey: Pointer; ASize: SizeInt; AInitVal: UInt32 = 0): UInt32; override;
  end;

  TExtendedProbeFactory = class(TDelphiDoubleHashFactory)
  public
    class var ServiceCalls: Integer;
    class function GetHashService: THashServiceClass; override;
  end;

  TProbeService = class(THashService<TProbeFactory>)
    class var EqualityCalls: Integer;
    class function LookupEqualityComparer(ATypeInfo: PTypeInfo; ASize: SizeInt): Pointer; override;
  end;

  TExtendedProbeService = class(TExtendedHashService<TExtendedProbeFactory>)
    class var EqualityCalls: Integer;
    class var ExtendedCalls: Integer;
    class function LookupEqualityComparer(ATypeInfo: PTypeInfo; ASize: SizeInt): Pointer; override;
    class function LookupExtendedEqualityComparer(ATypeInfo: PTypeInfo; ASize: SizeInt): Pointer; override;
  end;

  TBinaryValue = record
    First: Integer;
    Second: Integer;
  end;

  TProbe<T> = class
    class procedure Run(const Left, Same, Different: T); static;
  end;

procedure Check(Condition: Boolean; const Name: string);
begin
  If not Condition then begin
    Writeln('FAIL ', Name);
    Halt(1);
  end;
end;

class function TProbeFactory.GetHashService: THashServiceClass;
begin
  Inc(ServiceCalls);
  Result := TProbeService;
end;

class function TProbeFactory.GetHashCode(AKey: Pointer; ASize: SizeInt; AInitVal: UInt32): UInt32;
begin
  Inc(HashCalls);
  Result := inherited GetHashCode(AKey, ASize, AInitVal);
end;

class function TExtendedProbeFactory.GetHashService: THashServiceClass;
begin
  Inc(ServiceCalls);
  Result := TExtendedProbeService;
end;

class function TProbeService.LookupEqualityComparer(ATypeInfo: PTypeInfo; ASize: SizeInt): Pointer;
begin
  Inc(EqualityCalls);
  Result := inherited LookupEqualityComparer(ATypeInfo,ASize);
end;

class function TExtendedProbeService.LookupEqualityComparer(ATypeInfo: PTypeInfo; ASize: SizeInt): Pointer;
begin
  Inc(EqualityCalls);
  Result := nil;
end;

class function TExtendedProbeService.LookupExtendedEqualityComparer(ATypeInfo: PTypeInfo; ASize: SizeInt): Pointer;
begin
  Inc(ExtendedCalls);
  Result := inherited LookupExtendedEqualityComparer(ATypeInfo,ASize);
end;

class procedure TProbe<T>.Run(const Left, Same, Different: T);
var
  Comparer: IEqualityComparer<T>;
begin
  Comparer := TEqualityComparer<T>.Default(TDefaultHashFactory);
  Check(Comparer.Equals(Left, Same), 'default equality');
  Check(not Comparer.Equals(Left, Different), 'default inequality');
  Check(Comparer.GetHashCode(Left) = Comparer.GetHashCode(Same), 'equal values have equal hashes');
end;

var
  Comparer: IEqualityComparer<Integer>;
  Left, Same, Different: TBinaryValue;
begin
  TProbe<Integer>.Run(-27, -27, 13);
  TProbe<Cardinal>.Run($80000000, $80000000, $ffffffff);
  TProbe<Int64>.Run(-$100000001, -$100000001, $100000001);
  TProbe<UInt64>.Run($8000000000000000, $8000000000000000, $ffffffffffffffff);
  TProbe<UnicodeString>.Run('alpha', 'alpha', 'beta');
  TProbe<UnicodeString>.Run('', '', 'x');
  Left.First := 17;
  Left.Second := -13;
  Same := Left;
  Different := Left;
  Inc(Different.Second);
  TProbe<TBinaryValue>.Run(Left, Same, Different);

  Comparer := TEqualityComparer<Integer>.Default(TProbeFactory);
  Check(TProbeFactory.ServiceCalls > 0, 'derived factory service override');
  Check(TProbeService.EqualityCalls > 0, 'derived service equality override');
  Check(Comparer.Equals(7, 7) and not Comparer.Equals(7, 8), 'derived factory equality');
  Comparer.GetHashCode(7);
  Check(TProbeFactory.HashCalls > 0, 'derived factory hash override');

  Comparer := TEqualityComparer<Integer>.Default(TExtendedProbeFactory);
  Check(TExtendedProbeFactory.ServiceCalls > 0, 'extended factory service override');
  Check((TExtendedProbeService.ExtendedCalls > 0) and (TExtendedProbeService.EqualityCalls = 0), 'extended service route');
  Check(Comparer.Equals(9, 9) and not Comparer.Equals(9, 10), 'extended factory equality');
  Comparer := TEqualityComparer<Integer>.Default(nil);
  Check(Comparer = nil, 'nil factory preserves nil result');
  Writeln('RTL_API_COMPARER_FACTORY_CONTRACTS_OK');
end.
