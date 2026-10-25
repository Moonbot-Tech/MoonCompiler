program Mapping;
{$mode delphi}
uses SysUtils, MappingCore, MappingA, MappingB;

procedure Check(Value: Boolean; const Why: UnicodeString);
begin
  If not Value then raise Exception.Create('MAPPING: '+Why);
end;

var
  A: IValue<Integer>;
  S: IValue<UnicodeString>;
  D: IValue<Integer>;
  X: IAlt<Integer>;
  B: TBox<Integer>;
  F: IValue<Integer>;
begin
  try
    Check(IntegerClass=AliasClass,'class identity');
    Check(IntegerInfo=AliasInfo,'interface identity');
    Check(IntegerClass<>StringClass,'different args');
    A:=MakeInteger;
    S:=MakeString;
    Check((A.Value=137) and (A.Tag=11),'main dispatch');
    Check((S.Value='shared string') and (S.Tag=11),'managed dispatch');
    B:=TDerived<Integer>.Create(239);
    D:=B;
    X:=B;
    Check((D.Value=239) and (D.Tag=11),'inherited dispatch');
    Check((X.Value=0) and (X.Tag=29),'alternate dispatch');
    F:=TFixed<UnicodeString>.Create;
    Check((F.Value=71) and (F.Tag=83),'fixed specialization in partial template');
    A:=nil;
    S:=nil;
    D:=nil;
    Check(Destroyed=2,'shared interface retains object');
    X:=nil;
    F:=nil;
    Check(Destroyed=3,'lifecycle');
    Writeln('MAPPING_FORWARD_PASS');
  except
    on E: Exception do begin
      Writeln('CONTRACT_REJECTED: ',E.Message);
      Halt(91);
    end;
  end;
end.
