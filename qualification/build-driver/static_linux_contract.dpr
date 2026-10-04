program static_linux_contract;
uses SysUtils;
var Calls: Integer;
function Worker(P: Pointer): PtrInt;
begin
  try
    raise Exception.Create('worker');
  except
    on E: Exception do If E.Message = 'worker' then Inc(Calls);
  end;
  Result := 57;
end;
var Thread: TThreadID; Handle: TThreadID;
begin
  Calls := 0;
  Handle := BeginThread(nil, 0, @Worker, nil, 0, Thread);
  If (Handle = 0) or (WaitForThreadTerminate(Handle, 5000) <> 57) then Halt(1);
  CloseThread(Handle);
  try
    raise Exception.Create('main');
  except
    on E: Exception do If E.Message = 'main' then Inc(Calls);
  end;
  If Calls <> 2 then Halt(2);
  WriteLn('STATIC_DYNAMIC_CONTROL_PASS');
end.
