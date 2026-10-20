program StaticPropertyAudit;
{$mode delphiunicode}
uses mormot.core.fpcx64mm, System.SysUtils, System.Rtti, System.TypInfo, StaticPropertyTypes;
type
  TTracked = class(TInterfacedObject)
    constructor Create;
    destructor Destroy; override;
  end;
var Created, Destroyed, Checks: Integer;
procedure Check(OK: Boolean; const Name: string);
begin Inc(Checks); If not OK then begin Writeln('FAIL ', Name); Halt(1); end; end;
constructor TTracked.Create;
begin inherited Create; Inc(Created); end;
destructor TTracked.Destroy;
begin Inc(Destroyed); inherited Destroy; end;
procedure CheckRef(TypeInfo: PTypeInfo; Destination: Pointer);
var C: TRttiContext; P: TRttiProperty; OldRef, NewRef: IInterface; V: TValue; Failed: Boolean;
begin
  C := TRttiContext.Create;
  try
    P := C.GetType(TypeInfo).GetProperty('Value');
    Check(P <> nil, 'static property RTTI');
    Check((PPropInfo(P.Handle)^.SetProc = Destination) and (PPropInfo(P.Handle)^.GetProc = Destination), 'both addresses');
    OldRef := TTracked.Create; NewRef := TTracked.Create;
    P.SetValue(nil, TValue.From<IInterface>(OldRef));
    P.SetValue(nil, TValue.From<IInterface>(NewRef));
    OldRef := nil;
    V := P.GetValue(nil); Check(V.AsInterface = NewRef, 'getter value');
    P.SetValue(nil, V);
    Failed := False;
    try P.SetValue(nil, TValue.From<Integer>(123)); except on EInvalidCast do Failed := True; end;
    Check(Failed and (V.AsInterface = NewRef), 'failed cast');
    P.SetValue(nil, TValue.Empty); Check(P.GetValue(nil).AsInterface = nil, 'empty write');
    V := TValue.Empty; NewRef := nil;
  finally C.Free; end;
end;
procedure Run;
var C: TRttiContext; P: TRttiProperty;
begin
  CheckRef(System.TypeInfo(TRefHolder), @TRefHolder.Data);
  CheckRef(System.TypeInfo(TOuter.TNested), @TOuter.TNested.Data);
  CheckRef(System.TypeInfo(TDerived), @TBase.Data);
  CheckRef(System.TypeInfo(TRecordHolder), @TRecordHolder.Data);
  CheckRef(System.TypeInfo(TSubfieldHolder), @TSubfieldHolder.Data.Ref);
  CheckRef(System.TypeInfo(TArrayHolder), @TArrayHolder.Data[1]);
  C := TRttiContext.Create;
  try
    TStringHolder.Data := StringOfChar('A',100);
    P := C.GetType(TStringHolder).GetProperty('Value'); Check(P <> nil,'string property RTTI');
    P.SetValue(nil, TValue.From<UnicodeString>(StringOfChar('B',200)));
    Check(TStringHolder.Data = StringOfChar('B',200),'string write');
    Check(P.GetValue(nil).AsString = TStringHolder.Data,'string getter');
    P.SetValue(nil,TValue.Empty); Check(TStringHolder.Data = '','empty string');
    P := C.GetType(TIntHolder).GetProperty('Value'); Check(P <> nil,'integer property RTTI');
    P.SetValue(nil,TValue.From<Int64>(123456789));
    Check((TIntHolder.Data = 123456789) and (P.GetValue(nil).AsInt64 = 123456789),'integer value');
    P := C.GetType(TStaticOnly).GetProperty('Value'); Check(P <> nil,'RTTI-only static field');
    P.SetValue(nil,TValue.From<IInterface>(TTracked.Create));
    Check(P.GetValue(nil).AsInterface <> nil,'RTTI-only static read');
    P.SetValue(nil,TValue.Empty);
  finally C.Free; end;
end;
begin
  Run;
  Check(Created = Destroyed, 'all owners destroyed');
  Writeln('AUDIT_PASS checks=',Checks,' created=',Created,' destroyed=',Destroyed);
end.
