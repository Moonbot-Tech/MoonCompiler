program rtl_api_delayed_contracts;
{$mode delphi}{$H+}
uses Windows, SysUtils, Classes, SysInit;
type
  TFour = record A, B, C, D: Int64; end;
function Weighted(A, B, C, D, E, F: Int64): Int64; stdcall; external 'moon_delay_fixture.dll' name 'Weighted' delayed;
function Mixed(A: Double; B: Int64; C: Double; D: Int64; E: Double): Double; stdcall;
  external 'moon_delay_fixture.dll' name 'Mixed' delayed;
function Four(A, B, C, D: Int64): TFour; stdcall; external 'moon_delay_fixture.dll' name 'Four' delayed;
function Ordinal(A, B, C, D, E, F: Int64): Int64; stdcall; external 'moon_delay_fixture.dll' index 7 delayed;
function Race(A, B, C, D, E, F: Int64): Int64; stdcall; external 'moon_delay_fixture.dll' name 'Race' delayed;
function MissingLibrary(A, B, C, D, E, F: Int64): Int64; stdcall;
  external 'moon_delay_absent.dll' name 'Weighted' delayed;
function MissingExport(A, B, C, D, E, F: Int64): Int64; stdcall;
  external 'moon_delay_fixture.dll' name 'NoSuchExport' delayed;

procedure Check(Value: Boolean; const Message: string);
begin
  If not Value then
    raise Exception.Create(Message);
end;

var
  Starts, Ends, RaceStarts: Longint;
  Recover: Boolean;
  StartGate: THandle;

function Notify(Kind: dliNotification; Info: PDelayLoadInfo): Pointer; stdcall;
begin
  Result := nil;
  Check((Info^.cb = SizeOf(TDelayLoadInfo)) and (Info^.pidd <> nil) and
    (Info^.ppfn <> nil) and (Info^.szDll <> nil), 'hook descriptor');
  If Kind = dliStartProcessing then begin
    InterlockedIncrement(Starts);
    If Info^.dlp.fImportByName and (AnsiString(Info^.dlp.szProcName) = 'Race') then
      InterlockedIncrement(RaceStarts);
  end;
  If Kind = dliNoteEndProcessing then begin
    Check(Info^.pfnCur <> nil, 'resolved address in completion hook');
    InterlockedIncrement(Ends);
  end;
end;

function RecoverFailure(Kind: dliNotification; Info: PDelayLoadInfo): Pointer; stdcall;
begin
  Result := nil;
  Check(Info^.dwLastError <> 0, 'native error preserved');
  If not Recover then
    Exit;
  If Kind = dliFailLoadLibrary then
    Result := Pointer(LoadLibraryA('moon_delay_fixture.dll'))
  else If Kind = dliFailGetProcAddress then
    Result := GetProcAddress(Info^.hmodCur, 'Weighted');
end;

type
  TCaller = class(TThread)
    Value: Int64;
    procedure Execute; override;
  end;
procedure TCaller.Execute;
begin
  WaitForSingleObject(StartGate, 3000);
  Value := Race(1, 2, 3, 4, 5, 6);
end;

var
  SavedNotify, SavedFailure: TDelayedLoadHook;
  R: TFour;
  Before, I: Integer;
  Workers: array[0..7] of TCaller;
  Failed: Boolean;
  P: function(A, B, C, D, E, F: Int64): Int64; stdcall;
begin
  Check(GetModuleHandleA('moon_delay_fixture.dll') = 0, 'DLL loaded before the first call');
  SavedNotify := SetDliNotifyHook2(Notify);
  SavedFailure := SetDliFailureHook2(RecoverFailure);
  try
    Check(Weighted(1, 2, 3, 4, 5, 6) = 91, 'integer register/stack arguments');
    Before := Starts;
    P := Weighted;
    Check(P(6, 5, 4, 3, 2, 1) = 56, 'procedure address calls cached import');
    Check(Starts = Before, 'repeated call should not resolve again');
    Check(Mixed(1.5, 2, 3.5, 4, 5.5) = 59.5, 'mixed floating/integer/stack arguments');
    R := Four(101, 202, 303, 404);
    Check((R.A = 101) and (R.B = 202) and (R.C = 303) and (R.D = 404), 'hidden structure result');
    Check(Ordinal(1, 2, 3, 4, 5, 6) = 91, 'ordinal import');
    StartGate := CreateEvent(nil, True, False, nil);
    for I := 0 to High(Workers) do
      Workers[I] := TCaller.Create(False);
    SetEvent(StartGate);
    for I := 0 to High(Workers) do begin
      Workers[I].WaitFor;
      Check((Workers[I].FatalException = nil) and (Workers[I].Value = 91), 'concurrent first call');
      Workers[I].Free;
    end;
    CloseHandle(StartGate);
    Check(RaceStarts = 1, 'one resolver for simultaneous first calls');
    for I := 0 to 1 do begin
      Failed := False;
      try
        If I = 0 then
          MissingLibrary(1, 2, 3, 4, 5, 6)
        else
          MissingExport(1, 2, 3, 4, 5, 6);
      except
        on E: EExternalException do
          Failed := True;
      end;
      Check(Failed, 'missing import must raise through the delay thunk');
    end;
    Recover := True;
    Check(MissingLibrary(1, 2, 3, 4, 5, 6) = 91, 'load failure recovery');
    Check(MissingExport(1, 2, 3, 4, 5, 6) = 91, 'export failure recovery');
    UnloadDelayLoadedDLL2(nil);
    Check(GetModuleHandleA('moon_delay_fixture.dll') = 0, 'all delay-load references released');
    Before := Starts;
    LoadAllImportsForDll('moon_delay_fixture.dll');
    Check((GetModuleHandleA('moon_delay_fixture.dll') <> 0) and (Starts > Before), 'explicit preloading');
    Before := Starts;
    Check(Weighted(1, 2, 3, 4, 5, 6) = 91, 'preloaded target');
    Check(Starts = Before, 'preloading populates the target');
    UnloadDelayLoadedDLL2('moon_delay_fixture.dll');
    Check(GetModuleHandleA('moon_delay_fixture.dll') = 0, 'named unload');
    Check(Weighted(1, 2, 3, 4, 5, 6) = 91, 'reload after explicit unload');
    Check(Ends > 0, 'completion notifications');
  finally
    UnloadDelayLoadedDLL2(nil);
    SetDliNotifyHook2(SavedNotify);
    SetDliFailureHook2(SavedFailure);
  end;
  Writeln('RTL_API_DELAYED_CONTRACTS_OK');
end.
