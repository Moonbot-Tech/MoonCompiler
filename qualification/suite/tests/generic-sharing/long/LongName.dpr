program LongName;
 {$APPTYPE CONSOLE}
 uses {$IFDEF UNIX} cthreads, ffi.manager, {$ENDIF} System.SysUtils,A,B;
 var O:TObject;
 begin
 Writeln('IDENTITY=',A.ClassA=B.ClassA);
 Writeln('DISTINCT=',A.ClassA<>B.ClassB);
 O:=A.ClassA.Create;
 try Writeln('CAST=',B.Check(O));finally O.Free;end;
 end.
