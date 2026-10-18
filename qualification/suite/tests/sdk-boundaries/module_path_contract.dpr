program module_path_contract;
uses System.SysUtils, Dynlibs, ExeInfo, dl;

type TMarker = function: Pointer; cdecl;

var MarkerCalls: Integer;

function ExecutableMarker: Pointer; noinline;
begin
  Result := get_pc_addr;
  Inc(MarkerCalls);
end;

procedure CheckAddress(Addr: Pointer; const Expected: string);
var
  Base: Pointer;
  Name: AnsiString;
  Info: dl_info;
  Routine, Source: ShortString;
  Line: LongInt;
begin
  GetModuleByAddr(Addr, Base, Name);
  If (Name = '') or (Name[1] <> '/') then
    raise Exception.Create('module path not absolute: ' + string(Name));
  If dladdr(Addr, @Info) = 0 then raise Exception.Create('native dladdr failed');
  If Base <> Info.dli_fbase then raise Exception.Create('module base changed');
  If not GetLineInfo(PtrUInt(Addr), Routine, Source, Line) then
    raise Exception.Create('missing symbol: ' + string(Name));
  If Pos(UpperCase(Expected), UpperCase(string(Routine))) = 0 then
    raise Exception.Create('wrong symbol: ' + string(Routine));
  If Line <= 0 then raise Exception.Create('missing source line');
end;

begin
  If ParamCount <> 1 then Halt(2);
  var Lib := LoadLibrary(ParamStr(1));
  If Lib = 0 then raise Exception.Create('load relative library');
  try
    var MarkerProc := GetProcedureAddress(Lib, 'LibraryMarker');
    If MarkerProc = nil then raise Exception.Create('library export');
    var Marker := TMarker(MarkerProc)();
    If not SetCurrentDir('/tmp') then Halt(3);
    CheckAddress(ExecutableMarker, 'ExecutableMarker');
    CheckAddress(Marker, 'LibraryMarker');
    If not SetCurrentDir('/') then Halt(4);
    CheckAddress(Marker, 'LibraryMarker');
    CheckAddress(ExecutableMarker, 'ExecutableMarker');
    var Base: Pointer;
    var Name: AnsiString;
    GetModuleByAddr(Pointer(1), Base, Name);
    If (Name <> '') or (Base <> nil) then raise Exception.Create('unmapped address');
  finally
    UnloadLibrary(Lib);
  end;
  Writeln('MODULE_PATH_CONTRACT_PASS');
end.
