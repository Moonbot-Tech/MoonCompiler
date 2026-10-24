program Probe;
{$APPTYPE CONSOLE}
uses {$IFDEF UNIX} cthreads, ffi.manager, {$ENDIF} System.SysUtils, System.Classes, Core,A,B;
var Source, Restored: TComponent; Buffer: TMemoryStream;
begin
  Writeln('CLASS=', A.StoredClass = B.StoredClass);
  RegisterClass(B.StoredClass);
  RegisterClass(A.StoredClass);
  try
    Source := A.MakeStored;
    try
      Buffer := TMemoryStream.Create;
      try
        Buffer.WriteComponent(Source);
        Buffer.Position := 0;
        Restored := Buffer.ReadComponent(nil);
        try
          Writeln('STREAMED=', B.CheckStored(Restored));
          Writeln('REGISTERED=', GetClass(Source.ClassName) = B.StoredClass);
        finally
          Restored.Free;
        end;
      finally
        Buffer.Free;
      end;
    finally
      Source.Free;
    end;
  finally
    UnRegisterClass(B.StoredClass);
  end;
end.
