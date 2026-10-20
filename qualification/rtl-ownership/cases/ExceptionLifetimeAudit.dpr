program ExceptionLifetimeAudit;
{$mode delphiunicode}
uses mormot.core.fpcx64mm, System.SysUtils;
type
  TTrackedError = class(Exception)
    constructor Create;
    destructor Destroy; override;
  end;
var Created, Destroyed, Checks: Integer;
procedure Check(Value: Boolean; const Name: string);
begin
  Inc(Checks);
  If not Value then begin Writeln('FAIL ', Name); Halt(1); end;
end;
constructor TTrackedError.Create;
begin inherited Create('audit'); Inc(Created); end;
destructor TTrackedError.Destroy;
begin Inc(Destroyed); inherited Destroy; end;
function Trace(Addr: CodePointer; Frame: Pointer; var Count: LongInt; var Frames: PCodePointer): Boolean;
begin
  Count := 2; GetMem(Frames, 2 * SizeOf(CodePointer));
  Frames[0] := Addr; Frames[1] := nil; Result := True;
end;
procedure ExitHandler(out Saved: TObject);
begin
  try raise TTrackedError.Create;
  except Saved := TObject(AcquireExceptionObject); Exit; end;
end;
procedure Run(const Mode: string);
var Saved, Again: TObject; Outer: PExceptObject; N: Integer;
begin
  Saved := nil;
  If Mode = 'exit' then begin
    ExitHandler(Saved);
    Check((Saved is TTrackedError) and (RaiseList = nil), 'exit unlinks handler'); Saved.Free;
  end else If (Mode = 'break') or (Mode = 'continue') then begin
    for N := 1 to 2 do begin
      try raise TTrackedError.Create;
      except
        Saved := TObject(AcquireExceptionObject);
        If Mode = 'break' then Break;
        Saved.Free;
        Continue;
      end;
    end;
    If Mode = 'break' then Saved.Free;
  end else If Mode = 'recapture' then begin
    try raise TTrackedError.Create;
    except Saved := TObject(AcquireExceptionObject); end;
    Check(RaiseList = nil, 'first transfer detached');
    try raise Saved;
    except Again := TObject(AcquireExceptionObject); Check(Saved = Again, 'recaptured identity'); end;
    Check(RaiseList = nil, 'second transfer detached'); Again.Free;
  end else If Mode = 'active-saved-raise' then begin
    try
      try raise TTrackedError.Create;
      except Saved := TObject(AcquireExceptionObject); raise Saved; end;
    except on E: TTrackedError do Check(E = Saved, 'raise acquired active object'); end;
  end else If Mode = 'nested-balanced' then begin
    try raise TTrackedError.Create;
    except
      Outer := RaiseList; Saved := TObject(AcquireExceptionObject);
      try raise TTrackedError.Create;
      except AcquireExceptionObject; AcquireExceptionObject; ReleaseExceptionObject; ReleaseExceptionObject; end;
      Check((RaiseList = Outer) and (ExceptObject = Saved), 'inner restored active owner');
      ReleaseExceptionObject;
    end;
  end else If Mode = 'caught-finally' then begin
    try
      try raise TTrackedError.Create;
      finally
        Outer := RaiseList;
        try raise TTrackedError.Create;
        except Saved := TObject(AcquireExceptionObject); end;
        Check(RaiseList = Outer, 'finally nested restores pending exception'); Saved.Free;
      end;
    except on E: TTrackedError do Check(E.Message = 'audit', 'original survives caught finally failure'); end;
  end else begin Writeln('unknown mode'); Halt(2); end;
  Check(RaiseList = nil, 'stack restored');
  Check(Created = Destroyed, 'all errors destroyed exactly once');
end;
var I: Integer;
begin
  If ParamStr(2) = 'trace' then ExceptionBacktraceProc := Trace;
  for I := 1 to 32 do Run(ParamStr(1));
  ExceptionBacktraceProc := nil;
  Writeln('AUDIT_PASS checks=', Checks, ' created=', Created, ' destroyed=', Destroyed, ' mode=', ParamStr(1));
end.
