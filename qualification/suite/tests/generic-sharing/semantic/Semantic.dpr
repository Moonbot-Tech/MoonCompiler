program Semantic;
{$APPTYPE CONSOLE}
uses {$IFDEF UNIX} cthreads, ffi.manager, {$ENDIF} System.SysUtils, System.TypInfo, System.Rtti, GenericCore, ConsumerA, ConsumerB;
var O: TObject; I: IProbe; C: TRttiContext; M: TRttiMethod;
begin
  Writeln('CLASS=', ConsumerA.BoxClass = ConsumerB.BoxClass);
  Writeln('TYPEINFO=', ConsumerA.BoxInfo = ConsumerB.BoxInfo);
  Writeln('RECORD=', ConsumerA.PairInfo = ConsumerB.PairInfo);
  Writeln('ALIAS=', ConsumerA.BoxClass = ConsumerB.AliasClass);
  Writeln('DISTINCT=', ConsumerA.BoxClass <> ConsumerB.DistinctClass);
  Writeln('PRIVATE=', ConsumerA.PrivateClass <> ConsumerB.PrivateClass);
  Writeln('ORDERED=', ConsumerA.PairInfo <> ConsumerB.ReverseInfo);
  Writeln('DERIVED=', ConsumerA.DerivedClass = ConsumerB.DerivedClass);
  ConsumerA.SetCounter(19);
  Writeln('SHARED_COUNTER=', ConsumerB.GetCounter = 19);
  Writeln('MANAGED=', ConsumerA.StringRoundTrip = 'hello '#$0416#$D83D#$DE00);
  Writeln('RECORD_VALUE=', ConsumerB.PairRoundTrip = 'pair');
  O := ConsumerA.NewBox;
  try
    Writeln('CROSS_CAST=', ConsumerB.CheckBox(O));
    C := TRttiContext.Create;
    try
      M := C.GetType(O.ClassType).GetMethod('Plus');
      Writeln('INVOKE=', Assigned(M) and (M.Invoke(O, [5]).AsInteger = 12));
    finally C.Free; end;
  finally O.Free; end;
  I := ConsumerA.NewInterface;
  Writeln('INTERFACE=', ConsumerB.ReadInterface(I) = 35);
  I := nil;
  Writeln('INIT_COUNT=', Initializations);
end.
