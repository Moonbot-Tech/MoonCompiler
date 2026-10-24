program Keys;
{$APPTYPE CONSOLE}
uses {$IFDEF UNIX} cthreads, ffi.manager, {$ENDIF} System.SysUtils, System.TypInfo, ConsumerA, ConsumerB;
var I: Integer; A, B, N: TClass;
begin
    A := ConsumerA.BoxClass;
    B := ConsumerB.BoxClass;
    N := ConsumerA.NestedClass(5);
    for I := 0 to 6 do
      Writeln('NESTED_', I, '=', ConsumerA.NestedClass(I) = ConsumerB.NestedClass(I));
    Writeln('DISTINCT_ARGS=', ConsumerA.NestedClass(0) <> ConsumerA.NestedClass(1));
    Writeln('UNIT_A=', GetTypeData(A.ClassInfo)^.UnitName);
    Writeln('UNIT_B=', GetTypeData(B.ClassInfo)^.UnitName);
    Writeln('NESTED_UNIT=', GetTypeData(N.ClassInfo)^.UnitName);
end.
