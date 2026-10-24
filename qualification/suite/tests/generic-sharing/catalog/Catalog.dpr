program Catalog;
{$APPTYPE CONSOLE}
uses {$IFDEF UNIX} cthreads, ffi.manager, {$ENDIF} System.SysUtils, System.Rtti, ConsumerA, ConsumerB;
var C: TRttiContext; A, B: TClass; Types: TArray<TRttiType>; T: TRttiType; N: Integer;
begin
  A := ConsumerA.BoxClass;
  B := ConsumerB.BoxClass;
  C := TRttiContext.Create;
  try
    Types := C.GetTypes;
    N := 0;
    for T in Types do
      if (T.Handle = A.ClassInfo) or (T.Handle = B.ClassInfo) then Inc(N);
    Writeln('CLASS=', A = B);
    Writeln('CATALOG_MATCHES=', N);
  finally C.Free; end;
end.
