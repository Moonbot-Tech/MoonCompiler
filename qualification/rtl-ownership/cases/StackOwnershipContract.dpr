program StackOwnershipContract;
uses mormot.core.fpcx64mm, System.SysUtils;

function Trace(Addr: CodePointer; Frame: Pointer; var Count: LongInt;
  var Frames: PCodePointer): Boolean;
begin
  Count := 2;
  GetMem(Frames, Count * SizeOf(CodePointer));
  Frames[0] := Addr;
  Frames[1] := nil;
  Result := True;
end;

var Error: TObject; Entry: PExceptObject; N, Depth: Integer;
begin
  If ParamStr(2) = '--trace' then ExceptionBacktraceProc := Trace;
  for N := 1 to 32 do begin
    Error := nil;
    try
      raise Exception.Create('owned');
    except
      If ParamStr(1) = '--acquire' then Error := TObject(AcquireExceptionObject);
    end;
    Error.Free;
  end;
  ExceptionBacktraceProc := nil;
  Depth := 0;
  Entry := RaiseList;
  while Entry <> nil do begin
    Inc(Depth);
    Entry := Entry^.Next;
  end;
  Writeln('STALE_RAISE_LIST_ENTRIES=', Depth);
end.
