program SEHLocalUnwindAudit;
uses mormot.core.fpcx64mm, System.SysUtils;
type
  TTrackedError = class(Exception)
    ID: Integer;
    constructor Create(AID: Integer);
    destructor Destroy; override;
  end;
var Dead: array[1..2] of Integer;
constructor TTrackedError.Create(AID: Integer);
begin
  inherited Create('local unwind');
  ID := AID;
end;
destructor TTrackedError.Destroy;
begin
  Inc(Dead[ID]);
  inherited Destroy;
end;
procedure LeaveThroughFinally(const Mode: string);
begin
  If Mode = 'exit' then begin
    try
      Exit;
    finally
      raise TTrackedError.Create(2);
    end;
  end else If Mode = 'break' then begin
    for var I := 1 to 1 do
      try
        Break;
      finally
        raise TTrackedError.Create(2);
      end;
  end else If Mode = 'continue' then begin
    for var I := 1 to 1 do
      try
        Continue;
      finally
        raise TTrackedError.Create(2);
      end;
  end else Halt(100);
end;
procedure Run(const Mode: string);
var Outer, Base: PExceptObject; Saved: TObject;
begin
  FillChar(Dead, SizeOf(Dead), 0);
  Base := RaiseList;
  try
    raise TTrackedError.Create(1);
  except
    Outer := RaiseList;
    Saved := ExceptObject;
    try
      LeaveThroughFinally(Mode);
    except
      If not (ExceptObject is TTrackedError) or (TTrackedError(ExceptObject).ID <> 2) then Halt(2);
    end;
    If (Dead[1] <> 0) or (Dead[2] <> 1) or (RaiseList <> Outer) or (ExceptObject <> Saved) then Halt(3);
  end;
  If (Dead[1] <> 1) or (RaiseList <> Base) then Halt(4);
end;
begin
  for var I := 1 to 8 do Run(ParamStr(1));
  Writeln('PASS ', ParamStr(1));
end.
