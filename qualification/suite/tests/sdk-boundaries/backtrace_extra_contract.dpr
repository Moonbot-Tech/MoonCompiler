program backtrace_extra_contract;
uses cthreads, SysUtils, Dynlibs, dl;

type
  TCallback = procedure; cdecl;
  TBridge = function(Callback: TCallback): NativeInt; cdecl;

var
  Calls: Integer;
  ForeignExpected: Boolean;

procedure CaptureNow; noinline;
var
  Frames: array[0..63] of CodePointer;
  Routine, Source: ShortString;
  Line: LongInt;
  Info: dl_info;
  Repeated: Integer;
  ForeignFound: Boolean;
begin
  var Count := CaptureBacktrace(0, Length(Frames), @Frames[0]);
  Repeated := 0;
  ForeignFound := False;
  for var I := 0 to Count - 1 do begin
    If GetLineInfo(PtrUInt(Frames[I]), Routine, Source, Line) and
      (Pos('RECURSE', UpperCase(string(Routine))) > 0) then Inc(Repeated);
    If dladdr(Frames[I], @Info) <> 0 then
      If (Info.dli_sname <> nil) and (AnsiString(Info.dli_sname) = 'foreign_bridge') then
        ForeignFound := True;
  end;
  If Repeated <> 9 then raise Exception.CreateFmt('recursive frames: %d', [Repeated]);
  If ForeignExpected and not ForeignFound then raise Exception.Create('missing C frame');
end;

procedure Recurse(Depth: Integer); noinline;
begin
  If Depth = 0 then CaptureNow else Recurse(Depth - 1);
  Inc(Calls);
end;

procedure Callback; cdecl;
begin
  Recurse(8);
  Inc(Calls);
end;

begin
  Recurse(8);
  If Calls <> 9 then Halt(2);
  var Lib := LoadLibrary('./libforeign_bridge.so');
  If Lib = 0 then raise Exception.Create('C bridge load');
  try
    var Proc := GetProcedureAddress(Lib, 'foreign_bridge');
    If Proc = nil then raise Exception.Create('C bridge export');
    ForeignExpected := True;
    If TBridge(Proc)(@Callback) <= 0 then Halt(3);
    If Calls <> 19 then Halt(4);
  finally
    UnloadLibrary(Lib);
  end;
  Writeln('BACKTRACE_RECURSION_FOREIGN_PASS');
end.
