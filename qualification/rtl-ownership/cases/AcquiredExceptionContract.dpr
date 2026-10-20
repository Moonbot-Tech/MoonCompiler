program AcquiredExceptionContract;

uses
  mormot.core.fpcx64mm, System.SysUtils;

procedure Run;
begin
  for var I := 1 to 32 do begin
    var Error: TObject := nil;
    try
      raise Exception.Create('Owned by the caller after AcquireExceptionObject');
    except
      If ParamStr(1) = '--acquire' then Error := TObject(AcquireExceptionObject);
    end;
    Error.Free;
  end;
end;

begin
  Run;
  Writeln('ACQUIRED_EXCEPTION_LIFETIME_PASS iterations=32 mode=', ParamStr(1));
end.
