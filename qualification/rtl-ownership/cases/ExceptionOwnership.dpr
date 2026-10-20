program ExceptionOwnership;
uses mormot.core.fpcx64mm, System.SysUtils, System.Classes;

type
  TTrackedError = class(Exception)
    constructor Create;
    destructor Destroy; override;
  end;
  TWorker = class(TThread)
  public
    Saved: TObject;
    Transfer: Boolean;
    StackClean: Boolean;
    procedure Execute; override;
  end;
var Created, Destroyed: Integer;

procedure Check(Value: Boolean; const What: string);
begin
  If not Value then begin
    Writeln('FAIL ',What);
    Halt(1);
  end;
end;

constructor TTrackedError.Create;
begin
  inherited Create('ownership');
  InterlockedIncrement(Created);
end;

destructor TTrackedError.Destroy;
begin
  InterlockedIncrement(Destroyed);
  inherited Destroy;
end;

procedure TWorker.Execute;
begin
  If Transfer then begin
    try
      raise TTrackedError.Create;
    except
      Saved := TObject(AcquireExceptionObject);
    end;
    StackClean := RaiseList = nil;
  end else
    raise TTrackedError.Create;
end;

function Trace(Addr: CodePointer; Frame: Pointer; var Count: LongInt;
  var Frames: PCodePointer): Boolean;
begin
  Count := 2;
  GetMem(Frames, Count * SizeOf(CodePointer));
  Frames[0] := Addr;
  Frames[1] := nil;
  Result := True;
end;

procedure Run(const Mode: string);
var Saved, Saved2: TObject; Outer: PExceptObject; Worker: TWorker;
begin
  Saved := nil;
  If Mode = 'balanced' then begin
    try
      raise TTrackedError.Create;
    except
      AcquireExceptionObject;
      ReleaseExceptionObject;
    end;
  end else If Mode = 'multi' then begin
    try
      raise TTrackedError.Create;
    except
      Saved := TObject(AcquireExceptionObject);
      Saved2 := TObject(AcquireExceptionObject);
      Check(Saved = Saved2,'multiple acquisition identity');
      ReleaseExceptionObject;
    end;
    Check(RaiseList = nil,'multi detached');
    Saved.Free;
  end else If Mode = 'nested' then begin
    try
      raise TTrackedError.Create;
    except
      Outer := RaiseList;
      try
        raise TTrackedError.Create;
      except
        Saved := TObject(AcquireExceptionObject);
      end;
      Check(RaiseList = Outer,'restore enclosing handler');
      Saved.Free;
      Saved := TObject(AcquireExceptionObject);
    end;
    Saved.Free;
  end else If Mode = 'reraise' then begin
    try
      try
        raise TTrackedError.Create;
      except
        AcquireExceptionObject;
        raise;
      end;
    except
      on E: TTrackedError do Check(E.Message = 'ownership','bare reraise');
    end;
  end else If Mode = 'saved-raise' then begin
    try
      raise TTrackedError.Create;
    except
      Saved := TObject(AcquireExceptionObject);
    end;
    Check(RaiseList = nil,'saved detached before rethrow');
    try
      raise Saved;
    except
      on E: TTrackedError do Check(E = Saved,'saved rethrow identity');
    end;
  end else If Mode = 'replacement' then begin
    try
      try
        raise TTrackedError.Create;
      except
        Saved := TObject(AcquireExceptionObject);
        raise TTrackedError.Create;
      end;
    except
      on E: TTrackedError do Check(E <> Saved,'replacement identity');
    end;
    Check(RaiseList = nil,'replacement detached');
    Saved.Free;
  end else If Mode = 'finally-replace' then begin
    try
      try
        raise TTrackedError.Create;
      finally
        raise TTrackedError.Create;
      end;
    except
      on E: TTrackedError do Check(E.Message = 'ownership','finally replacement');
    end;
  end else If (Mode = 'thread') or (Mode = 'fatal') then begin
    Worker := TWorker.Create(True);
    try
      Worker.Transfer := Mode = 'thread';
      Worker.Start;
      Worker.WaitFor;
      If Worker.Transfer then begin
        Check(Worker.StackClean,'worker exception stack detached');
        Check(Worker.FatalException = nil,'transfer did not fail');
        Check(Worker.Saved is TTrackedError,'worker owns error');
        Worker.Saved.Free;
        Worker.Saved := nil;
      end else
        Check(Worker.FatalException is TTrackedError,'FatalException ownership');
    finally
      Worker.Free;
    end;
  end else begin
    Writeln('Unknown mode');
    Halt(2);
  end;
  Check(RaiseList = nil,'handler stack restored');
  Check(Created = Destroyed,'exactly one destruction per object');
end;

var I: Integer;
begin
  If ParamStr(2) = 'trace' then ExceptionBacktraceProc := Trace;
  for I := 1 to 32 do Run(ParamStr(1));
  ExceptionBacktraceProc := nil;
  Writeln('EXCEPTION_OWNERSHIP_PASS ',ParamStr(1),' created=',Created,' destroyed=',Destroyed);
end.
