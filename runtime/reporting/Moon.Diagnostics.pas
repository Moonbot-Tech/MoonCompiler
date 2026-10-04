unit Moon.Diagnostics;

{$mode delphiunicode}{$H+}
{$if not defined(CPUX86_64)}{$fatal Moon.Diagnostics requires x86-64}{$endif}
{$if not (defined(LINUX) or defined(WIN64))}{$fatal Unsupported report target}{$endif}

interface

uses
  SysUtils, Classes;

type
  TDiagnosticReport = class
  private
    FHandle: THandle;
    FBuffer: array[0..16383] of Byte;
    FUsed: Integer;
    FWriteFailed, FSymbolsFailed: Boolean;
    procedure Flush;
    procedure Line(const Text: string);
  public
    procedure Add(const Name, Value: string);
    procedure AttachFile(const FileName: string);
  end;

  TDiagnosticDataProc = procedure(Report: TDiagnosticReport);
  TDiagnosticNameProc = function(const Kind, Title: string): string;

  TDiagnosticOptions = record
    Directory: string;
    FileName: TDiagnosticNameProc;
    PostURL, PostFieldName, PostSuccessText: string;
    PostTimeoutMS: LongInt;
    MaxReportsPerRun: LongInt; { 0 = default 10; otherwise positive }
  end;

{ Call once before starting application threads. POST is opt-in, after local saving.
  DataProc runs during report formatting, never during early capture. }
procedure InitializeReports(const Directory: string = ''; DataProc: TDiagnosticDataProc = nil;
  const ApplicationVersion: string = ''); overload;
procedure InitializeReports(const Options: TDiagnosticOptions; DataProc: TDiagnosticDataProc = nil;
  const ApplicationVersion: string = ''); overload;
function WriteExceptionReport(const Title: string = ''): string; overload;
function WriteExceptionReport(E: Exception; const Title: string = ''): string; overload;
function WriteManualReport(const Title: string): string;

{ Both switches default to enabled. Setters return their own previous state,
  suitable for try/finally restoration. The thread switch affects only its caller.
  Disabled capture leaves ordinary RTL exception handling intact; report writers
  return ''. A report already in progress is not cancelled. }
function SetReportsEnabled(Enabled: Boolean): Boolean;
function SetThreadReportsEnabled(Enabled: Boolean): Boolean;
function ReportsEnabled: Boolean; inline;

{$ifdef MOON_DIAGNOSTICS_TEST}
{ Test-only fault injection. These pointers and branches do not exist in product builds. }
var
  DiagnosticTestBeforeResolve: procedure;
  DiagnosticTestWrite: function(Handle: THandle; const Buffer; Count: LongInt): LongInt;
  {$ifdef LINUX}DiagnosticTestMapsFile: PAnsiChar;{$endif}
{$endif}

implementation

uses
  lnfodwrf, Moon.Diagnostics.Http, Moon.Diagnostics.Zip,
  {$ifdef LINUX}BaseUnix, UnixType, Dynlibs{$else}Windows{$endif};

const
  MaxFrames = 128;
  StackBytes = 4096;
  CodeBeforeBytes = 128;
  CodeAfterBytes = 128;
  OperandBytes = 64;
  RegisterNames: array[0..17] of string = (
    'R8', 'R9', 'R10', 'R11', 'R12', 'R13', 'R14', 'R15',
    'RDI', 'RSI', 'RBP', 'RBX', 'RDX', 'RAX', 'RCX', 'RSP', 'RIP', 'EFLAGS');

type
  TDecodedMemory = record
    Address, Base: QWord;
    Flags, Bits: LongWord;
  end;
  TMemoryWindow = record
    Count: LongInt;
    Data: array[0..OperandBytes - 1] of Byte;
  end;
  TMemoryRegionState = (rsUnused, rsUnknown, rsUnmapped, rsReserved, rsMapped);
  TMemoryRegion = record
    Address, Base, Size: QWord;
    State: TMemoryRegionState;
    Access: Byte; { read=1, write=2, execute=4, guard=8 }
    {$ifdef WIN64}Protection: LongWord;{$endif}
  end;

  TRawSnapshot = record
    ThreadId, MonotonicNS: QWord;
    MemoryStart: PtrUInt;
    Registers: array[0..17] of QWord;
    Count, UnwindStatus, MemoryCount: LongInt;
    Hardware: Boolean;
    Frames: array[0..MaxFrames - 1] of PtrUInt;
    Memory: array[0..StackBytes - 1] of Byte;
    { Hardware-fault evidence only. No extra work for manual thread samples. }
    FloatValid: Boolean;
    FloatState: array[0..511] of Byte; { OS FXSAVE layout; no live FXSAVE instruction }
    {$ifdef LINUX}TrapNumber, TrapError, FaultAddress: QWord;{$endif}
    FunctionStart, FunctionEnd, CodeBeforeStart: PtrUInt;
    BeforeCount, AfterCount: LongInt;
    CodeBefore: array[0..CodeBeforeBytes - 1] of Byte;
    CodeAfter: array[0..CodeAfterBytes - 1] of Byte;
    Operands: array[0..1] of TDecodedMemory;
    OperandMemory, BaseMemory: array[0..1] of TMemoryWindow;
    Regions: array[0..3] of TMemoryRegion; { RIP, operand0, operand1, Linux page-fault address }
  end;

  TExceptionSnapshot = class
    Address: PtrUInt;
    Raw: TRawSnapshot;
  end;

var
  ReportOptions: TDiagnosticOptions;
  ApplicationName, ApplicationBuild, OSDescription: string;
  StartedTick: QWord;
  OnData: TDiagnosticDataProc;
  ReportLock: TRTLCriticalSection;
  ReportSequence: LongInt;
  Initialized: Boolean;
  GloballyDisabled: LongInt;
  PreviousCapture: TExceptionContextProc;
  {$ifdef LINUX}
  PreviousBacktrace: TExceptionBacktraceProc;
  {$endif}
  PreviousUnhandled, PreviousThreadUnhandled: TExceptProc;
  PreviousFrameLimit: LongInt;

threadvar
  ThreadDisabled: Boolean;
  Capturing, Reporting: Boolean;
  PendingHardware, PendingBacktrace: Boolean;
  HardwareSnapshot: TRawSnapshot;

{$ifdef LINUX}{$i moon_diagnostics_linux.inc}{$else}{$i moon_diagnostics_win64.inc}{$endif}

{$ifdef LINUX}{$linklib native/moon_decode_linux.a}{$else}{$linklib native/moon_decode_win64.a}{$endif}
function DecodeInstruction(Bytes: Pointer; Count: SizeUInt; IP: QWord; Registers, Memory: Pointer;
  Text: PAnsiChar; TextSize: SizeUInt): LongWord; cdecl; external name 'moon_diag_moon_decode';

procedure CaptureFaultDetails(Context: Pointer; var Raw: TRawSnapshot);
var
  IP, Before, After: PtrUInt;
  I: Integer;
begin
  NativeFaultState(Context, Raw);
  IP := Raw.Registers[16];
  Before := CodeBeforeBytes;
  If IP < Before then Before := IP;
  If (Raw.FunctionStart <> 0) and (Raw.FunctionStart <= IP) and (IP - Raw.FunctionStart < Before) then
    Before := IP - Raw.FunctionStart;
  Raw.CodeBeforeStart := IP - Before;
  Raw.BeforeCount := ReadOwnMemory(Pointer(Raw.CodeBeforeStart), @Raw.CodeBefore, Before);
  { Read RIP separately: an inaccessible previous page must not hide the fault. }
  After := SizeOf(Raw.CodeAfter);
  If (Raw.FunctionEnd > IP) and (Raw.FunctionEnd - IP < After) then After := Raw.FunctionEnd - IP;
  Raw.AfterCount := ReadOwnMemory(Pointer(IP), @Raw.CodeAfter, After);
  If DecodeInstruction(@Raw.CodeAfter, Raw.AfterCount, IP, @Raw.Registers, @Raw.Operands, nil, 0) <> 0 then
    for I := 0 to High(Raw.Operands) do
      If Raw.Operands[I].Flags and 1 <> 0 then begin
        Raw.OperandMemory[I].Count := ReadOwnMemory(Pointer(Raw.Operands[I].Address),
          @Raw.OperandMemory[I].Data, OperandBytes);
        If (Raw.Operands[I].Flags and 2 <> 0) and (Raw.Operands[I].Base <> Raw.Operands[I].Address) then
          Raw.BaseMemory[I].Count := ReadOwnMemory(Pointer(Raw.Operands[I].Base), @Raw.BaseMemory[I].Data, OperandBytes);
        Raw.Regions[I + 1].Address := Raw.Operands[I].Address;
        Raw.Regions[I + 1].State := rsUnknown;
      end;
  Raw.Regions[0].Address := IP;
  Raw.Regions[0].State := rsUnknown;
  {$ifdef LINUX}
  If Raw.TrapNumber = 14 then begin
    Raw.Regions[3].Address := Raw.FaultAddress;
    Raw.Regions[3].State := rsUnknown;
  end;
  {$endif}
  NativeMemoryRegions(Raw.Regions);
end;

function SetReportsEnabled(Enabled: Boolean): Boolean;
begin
  Result := InterlockedExchange(GloballyDisabled, Ord(not Enabled)) = 0;
end;

function SetThreadReportsEnabled(Enabled: Boolean): Boolean;
begin
  Result := not ThreadDisabled;
  ThreadDisabled := not Enabled;
end;

function ReportsEnabled: Boolean;
begin
  Result := (GloballyDisabled = 0) and not ThreadDisabled;
end;

{$ifdef LINUX}
function CaptureRTLBacktrace(Addr: CodePointer; Frame: Pointer;
  var FrameCount: LongInt; var Frames: PCodePointer): Boolean;
var
  I: Integer;
begin
  Result := False;
  If not ReportsEnabled then begin
    PendingHardware := False;
    PendingBacktrace := False;
    If Assigned(PreviousBacktrace) then Result := PreviousBacktrace(Addr, Frame, FrameCount, Frames);
    Exit;
  end;
  If Capturing or Reporting then Exit;
  Capturing := True;
  PendingBacktrace := False;
  try
    try
      If not (PendingHardware and (HardwareSnapshot.Registers[16] = PtrUInt(Addr))) then begin
        CaptureNative(nil, HardwareSnapshot, False, True, PtrUInt(Frame), PtrUInt(Addr));
        If HardwareSnapshot.Count = 0 then begin
          { raise ... at Address can intentionally substitute the origin.
            Do not present collector frames as that caller's original stack. }
          PendingHardware := False;
          Exit;
        end;
      end;
      FrameCount := HardwareSnapshot.Count - 1;
      If FrameCount < 0 then FrameCount := 0;
      If FrameCount > 0 then GetMem(Frames, FrameCount * SizeOf(CodePointer));
      for I := 0 to FrameCount - 1 do Frames[I] := CodePointer(HardwareSnapshot.Frames[I + 1]);
      PendingBacktrace := True;
      Result := True;
    except
      FrameCount := 0;
      Frames := nil;
    end;
  finally
    Capturing := False;
  end;
  If not Result and Assigned(PreviousBacktrace) then Result := PreviousBacktrace(Addr, Frame, FrameCount, Frames);
end;
{$endif}

procedure CaptureException(Obj: TObject; Addr: CodePointer; Frame: Pointer; FrameCount: LongInt;
  Frames: PCodePointer; Context: Pointer; Hardware: Boolean);
var
  Snapshot: TExceptionSnapshot;
  I: Integer;
begin
  If not ReportsEnabled then begin
    PendingHardware := False;
    PendingBacktrace := False;
    If Assigned(PreviousCapture) then PreviousCapture(Obj, Addr, Frame, FrameCount, Frames, Context, Hardware);
    Exit;
  end;
  If Obj = nil then begin
    { The RTL calls this before changing the OS fault context. No managed data. }
    If (Context <> nil) and not Capturing then begin
      Capturing := True;
      CaptureNative(Context, HardwareSnapshot, True);
      CaptureFaultDetails(Context, HardwareSnapshot);
      PendingHardware := True;
      Capturing := False;
    end;
    If Assigned(PreviousCapture) then PreviousCapture(Obj, Addr, Frame, FrameCount, Frames, Context, Hardware);
    Exit;
  end;
  If Capturing or Reporting then Exit;
  Capturing := True;
  try
    try
      If Obj is Exception then begin
        Snapshot := TExceptionSnapshot.Create;
        try
          Snapshot.Address := PtrUInt(Addr);
          If PendingBacktrace or (PendingHardware and (HardwareSnapshot.Registers[16] = PtrUInt(Addr))) then
            Snapshot.Raw := HardwareSnapshot
          else begin
            CaptureNative(Context, Snapshot.Raw, False, False, PtrUInt(Frame));
            Snapshot.Raw.Hardware := Hardware;
            If Hardware and (Context <> nil) then CaptureFaultDetails(Context, Snapshot.Raw);
            { Reuse the RTL trace; do not unwind a second time on each raise. }
            Snapshot.Raw.Frames[0] := PtrUInt(Addr);
            Snapshot.Raw.Count := FrameCount;
            If Snapshot.Raw.Count >= MaxFrames then Snapshot.Raw.Count := MaxFrames - 1;
            for I := 0 to Snapshot.Raw.Count - 1 do Snapshot.Raw.Frames[I + 1] := PtrUInt(Frames[I]);
            Inc(Snapshot.Raw.Count);
            If FrameCount >= RaiseMaxFrameCount then Snapshot.Raw.UnwindStatus := 1;
          end;
          PendingHardware := False;
          PendingBacktrace := False;
          Exception(Obj).DiagnosticContext := Snapshot;
          Snapshot := nil;
        finally
          Snapshot.Free;
        end;
      end;
    except
      { Capturing must never replace the application's exception. }
      PendingHardware := False;
      PendingBacktrace := False;
    end;
  finally
    Capturing := False;
  end;
  If Assigned(PreviousCapture) then PreviousCapture(Obj, Addr, Frame, FrameCount, Frames, Context, Hardware);
end;

procedure TDiagnosticReport.Flush;
var
  Written, Offset: LongInt;
begin
  Offset := 0;
  while Offset < FUsed do begin
    {$ifdef MOON_DIAGNOSTICS_TEST}
    If Assigned(DiagnosticTestWrite) then Written := DiagnosticTestWrite(FHandle, FBuffer[Offset], FUsed - Offset)
    else
    {$endif}
      Written := FileWrite(FHandle, FBuffer[Offset], FUsed - Offset);
    {$ifdef LINUX}
    If (Written < 0) and (FpGetErrno = ESysEINTR) then Continue;
    {$endif}
    If Written <= 0 then begin
      FWriteFailed := True;
      raise EWriteError.Create('Diagnostic report write failed');
    end;
    Inc(Offset, Written);
  end;
  FUsed := 0;
end;

procedure TDiagnosticReport.Line(const Text: string);
var
  Bytes: UTF8String;
  Offset, Count: Integer;
begin
  If FWriteFailed then raise EWriteError.Create('Diagnostic report write failed');
  Bytes := UTF8Encode(Text + #10);
  Offset := 1;
  while Offset <= Length(Bytes) do begin
    If FUsed = SizeOf(FBuffer) then Flush;
    Count := Length(Bytes) - Offset + 1;
    If Count > SizeOf(FBuffer) - FUsed then Count := SizeOf(FBuffer) - FUsed;
    Move(Bytes[Offset], FBuffer[FUsed], Count);
    Inc(FUsed, Count);
    Inc(Offset, Count);
  end;
end;

procedure TDiagnosticReport.Add(const Name, Value: string);
begin
  Line(Name + '=' + Value);
end;

procedure TDiagnosticReport.AttachFile(const FileName: string);
var
  Source: TFileStream;
  Buffer: array[0..4095] of Byte;
  Encoded: string;
  Count, I: Integer;
begin
  { Hex is deliberately streamable and also preserves arbitrary binary files. }
  Line('[attachment hex ' + ExtractFileName(FileName) + ']');
  Source := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  try
    repeat
      Count := Source.Read(Buffer, SizeOf(Buffer));
      SetLength(Encoded, Count * 2);
      for I := 0 to Count - 1 do begin
        Encoded[I * 2 + 1] := '0123456789ABCDEF'[(Buffer[I] shr 4) + 1];
        Encoded[I * 2 + 2] := '0123456789ABCDEF'[(Buffer[I] and 15) + 1];
      end;
      If Count > 0 then Line(Encoded);
    until Count = 0;
  finally
    Source.Free;
  end;
  Line('[/attachment]');
end;

procedure WriteAddress(Report: TDiagnosticReport; Address: PtrUInt; ReturnAddress: Boolean);
var
  Func, Source: ShortString;
  Number: LongInt;
  Lookup: PtrUInt;
  Found: Boolean;
begin
  Lookup := Address;
  If ReturnAddress and (Lookup > 0) then Dec(Lookup);
  Found := False;
  If not Report.FSymbolsFailed then begin
    try
      {$ifdef MOON_DIAGNOSTICS_TEST}
      If Assigned(DiagnosticTestBeforeResolve) then DiagnosticTestBeforeResolve;
      {$endif}
      Found := GetLineInfo(Lookup, Func, Source, Number);
    except
      Report.FSymbolsFailed := True;
      Report.Line('symbolization_error=address lookup failed; raw addresses retained');
    end;
  end;
  If Found and ((Func <> '') or (Source <> '')) then
    Report.Line('  $' + IntToHex(Address, 16) + ' ' + string(Func) + ' ' + string(Source) + ':' + IntToStr(Number))
  else
    Report.Line('  $' + IntToHex(Address, 16) + ' [symbol unavailable]');
end;

function HexBytes(Data: PByte; Count: Integer; Reverse: Boolean = False): string;
var
  I, Index: Integer;
begin
  Result := '';
  for I := 0 to Count - 1 do begin
    If Reverse then Index := Count - I - 1 else Index := I;
    Result := Result + IntToHex(Data[Index], 2);
    If not Reverse then Result := Result + ' ';
  end;
end;

procedure WriteMemory(Report: TDiagnosticReport; const Name: string; Address: QWord; const Window: TMemoryWindow);
begin
  Report.Add(Name + '_address', '$' + IntToHex(Address, 16));
  Report.Add(Name + '_bytes', IntToStr(Window.Count));
  If Window.Count <> 0 then Report.Add(Name + '_hex', HexBytes(@Window.Data, Window.Count))
  else Report.Add(Name + '_status', 'unreadable at capture');
end;

procedure WriteFaultEvidence(Report: TDiagnosticReport; const Raw: TRawSnapshot);
const
  RegionNames: array[0..3] of string = ('instruction', 'operand0', 'operand1', 'fault');
  RegionStates: array[TMemoryRegionState] of string = ('unused', 'unavailable', 'unmapped', 'reserved', 'mapped');
var
  I: Integer;
  Name, Access: string;
begin
  If not Raw.Hardware then Exit;
  Report.Add('memory_regions', 'capture-time OS mappings; not allocation-lifetime evidence');
  for I := 0 to High(Raw.Regions) do
    If Raw.Regions[I].State <> rsUnused then begin
      Name := RegionNames[I] + '_region';
      Report.Add(Name + '_address', '$' + IntToHex(Raw.Regions[I].Address, 16));
      Report.Add(Name + '_state', RegionStates[Raw.Regions[I].State]);
      If Raw.Regions[I].State in [rsReserved, rsMapped] then begin
        Report.Add(Name + '_base', '$' + IntToHex(Raw.Regions[I].Base, 16));
        Report.Add(Name + '_size', UIntToStr(Raw.Regions[I].Size));
        Access := '---';
        If Raw.Regions[I].Access and 1 <> 0 then Access[1] := 'r';
        If Raw.Regions[I].Access and 2 <> 0 then Access[2] := 'w';
        If Raw.Regions[I].Access and 4 <> 0 then Access[3] := 'x';
        Report.Add(Name + '_access', Access);
        {$ifdef WIN64}
        Report.Add(Name + '_protection', '$' + IntToHex(Raw.Regions[I].Protection, 8));
        Report.Add(Name + '_guard', BoolToStr(Raw.Regions[I].Access and 8 <> 0, True));
        {$endif}
      end;
    end;
  {$ifdef LINUX}
  Report.Add('linux_trap', UIntToStr(Raw.TrapNumber));
  Report.Add('linux_trap_error', '$' + IntToHex(Raw.TrapError, 16));
  If Raw.TrapNumber = 14 then Report.Add('fault_address', '$' + IntToHex(Raw.FaultAddress, 16));
  {$endif}
  If Raw.FloatValid then begin
    Report.Add('fp_context', 'original OS context; values are raw bit patterns, high byte first');
    Report.Add('x87_control', '$' + HexBytes(@Raw.FloatState[0], 2, True));
    Report.Add('x87_status', '$' + HexBytes(@Raw.FloatState[2], 2, True));
    Report.Add('x87_abridged_tag', '$' + HexBytes(@Raw.FloatState[4], 1, True));
    Report.Add('x87_opcode', '$' + HexBytes(@Raw.FloatState[6], 2, True));
    Report.Add('x87_instruction_pointer_raw', '$' + HexBytes(@Raw.FloatState[8], 8, True));
    Report.Add('x87_data_pointer_raw', '$' + HexBytes(@Raw.FloatState[16], 8, True));
    Report.Add('MXCSR', '$' + HexBytes(@Raw.FloatState[24], 4, True));
    for I := 0 to 7 do Report.Add('x87_ST' + IntToStr(I), '$' + HexBytes(@Raw.FloatState[32 + I * 16], 10, True));
    for I := 0 to 15 do Report.Add('XMM' + IntToStr(I), '$' + HexBytes(@Raw.FloatState[160 + I * 16], 16, True));
  end else Report.Add('fp_context', 'unavailable');
  Report.Add('code_before_start', '$' + IntToHex(Raw.CodeBeforeStart, 16));
  Report.Add('code_before_hex', HexBytes(@Raw.CodeBefore, Raw.BeforeCount));
  Report.Add('code_at_rip_hex', HexBytes(@Raw.CodeAfter, Raw.AfterCount));
  for I := 0 to High(Raw.Operands) do
    If Raw.Operands[I].Flags and 1 <> 0 then begin
      Name := 'operand' + IntToStr(I);
      Report.Add(Name + '_bits', UIntToStr(Raw.Operands[I].Bits));
      Report.Add(Name + '_read', BoolToStr(Raw.Operands[I].Flags and 4 <> 0, True));
      Report.Add(Name + '_write', BoolToStr(Raw.Operands[I].Flags and 8 <> 0, True));
      WriteMemory(Report, Name, Raw.Operands[I].Address, Raw.OperandMemory[I]);
      If (Raw.Operands[I].Flags and 2 <> 0) and (Raw.Operands[I].Base <> Raw.Operands[I].Address) then
        WriteMemory(Report, Name + '_base', Raw.Operands[I].Base, Raw.BaseMemory[I]);
    end;
end;

procedure WriteDisassembly(Report: TDiagnosticReport; const Raw: TRawSnapshot);
var
  I, N: LongWord;
  Text: array[0..255] of AnsiChar;
  ValidPrefix: Boolean;

  procedure Emit(Data: PByte; Count: LongWord; IP: QWord; Fault: Boolean);
  var
    Offset, Size: LongWord;
    Marker: string;
  begin
    Offset := 0;
    while Offset < Count do begin
      Size := DecodeInstruction(@Data[Offset], Count - Offset, IP + Offset, nil, nil, @Text, SizeOf(Text));
      If Size = 0 then begin
        Report.Line('  $' + IntToHex(IP + Offset, 16) + ' [invalid or truncated instruction]');
        Exit;
      end;
      If Fault and (Offset = 0) then Marker := '=> ' else Marker := '   ';
      Report.Line(Marker + '$' + IntToHex(IP + Offset, 16) + ' ' + HexBytes(@Data[Offset], Size) + string(PAnsiChar(@Text)));
      Inc(Offset, Size);
    end;
  end;

begin
  If not Raw.Hardware then Exit;
  Report.Line('[disassembly; saved code, not execution history]');
  ValidPrefix := (Raw.FunctionStart <> 0) and (Raw.CodeBeforeStart = Raw.FunctionStart) and
    (Raw.CodeBeforeStart + PtrUInt(Raw.BeforeCount) = Raw.Registers[16]);
  I := 0;
  while ValidPrefix and (I < LongWord(Raw.BeforeCount)) do begin
    N := DecodeInstruction(@Raw.CodeBefore[I], Raw.BeforeCount - I, Raw.CodeBeforeStart + I, nil, nil, nil, 0);
    If N = 0 then ValidPrefix := False else Inc(I, N);
  end;
  If ValidPrefix then Emit(@Raw.CodeBefore, Raw.BeforeCount, Raw.CodeBeforeStart, False)
  else Report.Line('before_rip=raw bytes only; instruction boundary not established');
  If Raw.AfterCount <> 0 then Emit(@Raw.CodeAfter, Raw.AfterCount, Raw.Registers[16], True)
  else Report.Line('at_rip=unreadable at capture');
end;

procedure WriteSnapshot(Report: TDiagnosticReport; const Raw: TRawSnapshot; Registers: Boolean);
var
  I, J: Integer;
  Text: string;
begin
  Report.Line('[thread ' + UIntToStr(Raw.ThreadId) + ']');
  Report.Add('captured_monotonic_ns', UIntToStr(Raw.MonotonicNS));
  Report.Add('unwind_status', IntToStr(Raw.UnwindStatus));
  { Write raw addresses first: they remain useful if symbolization itself fails. }
  for I := 0 to Raw.Count - 1 do Report.Line('pc[$' + IntToHex(Raw.Frames[I], 16) + ']');
  If Registers then begin
    for I := 0 to High(RegisterNames) do
      Report.Add(RegisterNames[I], '$' + IntToHex(Raw.Registers[I], 16));
    Report.Add('context', 'capture-time; hardware=' + BoolToStr(Raw.Hardware, True));
    Report.Add('stack_memory_start', '$' + IntToHex(Raw.MemoryStart, 16));
    Report.Add('stack_memory_bytes', IntToStr(Raw.MemoryCount));
    I := 0;
    while I < Raw.MemoryCount do begin
      Text := '';
      J := 0;
      while (J < 16) and (I < Raw.MemoryCount) do begin
        Text := Text + IntToHex(Raw.Memory[I], 2) + ' ';
        Inc(I);
        Inc(J);
      end;
      Report.Line(Text);
    end;
    WriteFaultEvidence(Report, Raw);
  end;
  Report.Flush; { Persist raw context before entering the DWARF reader. }
  If Registers then WriteDisassembly(Report, Raw);
  for I := 0 to Raw.Count - 1 do WriteAddress(Report, Raw.Frames[I], I <> 0);
end;

function ReserveReport: Boolean;
begin
  { Called under ReportLock, before callbacks, thread sampling or file creation.
    A failed attempt still consumes its slot; failures must not permit a flood. }
  Result := ReportSequence < ReportOptions.MaxReportsPerRun;
  If Result then Inc(ReportSequence);
end;

function BeginReport(const Kind, Title: string; out Report: TDiagnosticReport): string;
var
  Handle: THandle;
  Prefix: string;
  I: Integer;
  NameFailed: Boolean;
begin
  Prefix := 'report';
  NameFailed := False;
  If Assigned(ReportOptions.FileName) then begin
    try
      Prefix := ReportOptions.FileName(Kind, Title);
    except
      NameFailed := True;
    end;
  end;
  { One portable file-name component, never a path supplied by a callback.
    Leave room for the unique suffix within Linux's 255-byte component limit. }
  If Length(Prefix) > 48 then SetLength(Prefix, 48);
  If (Prefix <> '') and (Ord(Prefix[Length(Prefix)]) >= $D800) and (Ord(Prefix[Length(Prefix)]) <= $DBFF) then
    SetLength(Prefix, Length(Prefix) - 1);
  for I := 1 to Length(Prefix) do
    If (Ord(Prefix[I]) < 32) or (Pos(Prefix[I], '<>:"/\|?*') > 0) then Prefix[I] := '_';
  If Prefix = '' then Prefix := 'report';
  Result := IncludeTrailingPathDelimiter(ReportOptions.Directory) + Prefix + '-' +
    UIntToStr(NativeProcessId) + '-' + UIntToStr(NativeThreadId) + '-' +
    FormatDateTime('yyyymmdd-hhnnss-zzz', Now) + '-' +
    IntToStr(ReportSequence) + '.txt';
  Handle := CreateReportFile(Result);
  If Handle = THandle(-1) then RaiseLastOSError;
  Report := nil;
  try
    Report := TDiagnosticReport.Create;
    Report.FHandle := Handle;
    Report.Line('MOON_DIAGNOSTIC_REPORT 1');
    Report.Add('kind', Kind);
    Report.Add('title', Title);
    If NameFailed then Report.Add('filename_error', 'callback failed; default name used');
    Report.Add('application', ApplicationName);
    Report.Add('application_version', ApplicationBuild);
    Report.Add('os', OSDescription);
    Report.Add('compiler', 'FPC ' + {$I %FPCVERSION%});
    Report.Add('target', {$I %FPCTARGETCPU%} + '-' + {$I %FPCTARGETOS%});
    Report.Add('reporter_compiled', {$I %DATE%} + ' ' + {$I %TIME%});
    Report.Add('uptime_ms_since_init', UIntToStr(GetTickCount64 - StartedTick));
    Report.Add('time', FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz', Now));
  except
    Report.Free;
    Report := nil;
    NativeClose(Handle);
    raise;
  end;
end;

procedure CloseReport(Report: TDiagnosticReport);
begin
  try
    If not Report.FWriteFailed then Report.Flush;
  finally
    NativeClose(Report.FHandle);
    Report.Free;
  end;
end;

procedure FinishReport(Report: TDiagnosticReport; Complete: Boolean);
begin
  If Assigned(OnData) then begin
    try
      OnData(Report);
    except
      { A failed optional section must not discard the captured exception.
        Output failures remain fatal: Flush remembers them and raises again. }
      Complete := False;
      Report.Add('application_data_error', 'callback failed; preceding data retained');
    end;
  end;
  Report.Add('complete', BoolToStr(Complete and not Report.FSymbolsFailed, True));
  Report.Line('MOON_DIAGNOSTIC_END');
end;

procedure PackReport(const FileName, ZipName: string);
var
  Handle: THandle;
  Closed: Boolean;
begin
  Handle := CreateReportFile(ZipName); { exclusive create, same permissions as report }
  If Handle = THandle(-1) then RaiseLastOSError;
  try
    try
      WriteDiagnosticZip(FileName, Handle);
    finally
      {$ifdef LINUX}Closed := FpClose(Handle) = 0;{$else}Closed := CloseHandle(Handle);{$endif}
    end;
    If not Closed then RaiseLastOSError;
  except
    SysUtils.DeleteFile(ZipName); { only our newly created incomplete archive }
    raise;
  end;
end;

procedure DeliverReport(const FileName: string);
var
  Status: TDiagnosticReport;
  Handle: THandle;
  Code: LongInt;
  Error, ZipName: string;
begin
  If ReportOptions.PostURL = '' then Exit;
  Code := 0;
  try
    ZipName := ChangeFileExt(FileName, '.zip');
    PackReport(FileName, ZipName);
    Error := PostDiagnosticFile(ZipName, ReportOptions.PostURL, ReportOptions.PostFieldName,
      ReportOptions.PostSuccessText, ReportOptions.PostTimeoutMS, Code);
  except
    on E: Exception do Error := E.Message;
  end;
  { Delivery never changes or removes the closed report. A sibling status file
    records failure as well as success, without URL, credentials or response data. }
  try
    Handle := CreateReportFile(FileName + '.delivery');
    If Handle = THandle(-1) then Exit;
    Status := nil;
    try
      Status := TDiagnosticReport.Create;
      Status.FHandle := Handle;
      Status.Add('sent', BoolToStr(Error = '', True));
      Status.Add('http_status', IntToStr(Code));
      If Error <> '' then Status.Add('error', Error);
      Status.Flush;
    finally
      Status.Free;
      NativeClose(Handle);
    end;
  except
    { A delivery-status write must not turn a saved report into an apparent loss. }
  end;
end;

function WriteExceptionReport(const Title: string): string;
begin
  If not ReportsEnabled then Exit('');
  If not (ExceptObject is Exception) then raise Exception.Create('No active Pascal exception');
  Result := WriteExceptionReport(Exception(ExceptObject), Title);
end;

function WriteExceptionReport(E: Exception; const Title: string): string;
var
  Report: TDiagnosticReport;
  Snapshot: TExceptionSnapshot;
begin
  If not ReportsEnabled then Exit('');
  If not Initialized then raise Exception.Create('InitializeReports must be called first');
  If E = nil then raise Exception.Create('Exception object is nil');
  If Reporting then Exit('');
  Reporting := True;
  try
    EnterCriticalSection(ReportLock);
    try
      If not ReserveReport then Exit('');
      Result := BeginReport('exception', Title, Report);
      Snapshot := nil;
      try
        Report.Add('exception_class', string(E.ClassName));
        Report.Add('exception_message', E.Message);
        If E.DiagnosticContext is TExceptionSnapshot then Snapshot := TExceptionSnapshot(E.DiagnosticContext);
        If Snapshot <> nil then begin
          Report.Add('exception_address', '$' + IntToHex(Snapshot.Address, 16));
          WriteSnapshot(Report, Snapshot.Raw, True);
        end else
          Report.Line('original_context=unavailable (exception predates capture or capture failed)');
        FinishReport(Report, (Snapshot <> nil) and (Snapshot.Raw.UnwindStatus = 0));
      finally
        CloseReport(Report);
      end;
    finally
      LeaveCriticalSection(ReportLock);
    end;
    DeliverReport(Result);
  finally
    Reporting := False;
  end;
end;

function WriteManualReport(const Title: string): string;
var
  Report: TDiagnosticReport;
  Raw: TRawSnapshot;
  Threads: TList;
  I: Integer;
  Complete: Boolean;
begin
  If not ReportsEnabled then Exit('');
  If not Initialized then raise Exception.Create('InitializeReports must be called first');
  If Reporting then Exit('');
  Reporting := True;
  try
    EnterCriticalSection(ReportLock);
    Threads := nil;
    try
      If not ReserveReport then Exit('');
      Threads := TList.Create;
      EnumerateThreads(Threads);
      Result := BeginReport('manual', Title, Report);
      Complete := True;
      try
        Report.Add('threads_enumerated', IntToStr(Threads.Count));
        for I := 0 to Threads.Count - 1 do begin
          If SampleThread(PtrUInt(Threads[I]), Raw) then begin
            WriteSnapshot(Report, Raw, False);
            Complete := Complete and (Raw.UnwindStatus = 0);
          end
          else begin
            Complete := False;
            Report.Line('[thread ' + UIntToStr(PtrUInt(Threads[I])) + '] unavailable or exited');
          end;
        end;
        FinishReport(Report, Complete);
      finally
        CloseReport(Report);
      end;
    finally
      Threads.Free;
      LeaveCriticalSection(ReportLock);
    end;
    DeliverReport(Result);
  finally
    Reporting := False;
  end;
end;

procedure Unhandled(Obj: TObject; Addr: CodePointer; Count: LongInt; Frames: PCodePointer);
begin
  try
    If Obj is Exception then WriteExceptionReport(Exception(Obj), 'unhandled main exception');
  except
    { Original termination semantics win over a failed report. }
  end;
  If Assigned(PreviousUnhandled) then PreviousUnhandled(Obj, Addr, Count, Frames);
end;

procedure ThreadUnhandled(Obj: TObject; Addr: CodePointer; Count: LongInt; Frames: PCodePointer);
begin
  try
    If Obj is Exception then WriteExceptionReport(Exception(Obj), 'unhandled worker exception');
  except
  end;
  If Assigned(PreviousThreadUnhandled) then PreviousThreadUnhandled(Obj, Addr, Count, Frames);
end;

procedure InitializeReports(const Directory: string; DataProc: TDiagnosticDataProc; const ApplicationVersion: string);
var
  Options: TDiagnosticOptions;
begin
  Options := Default(TDiagnosticOptions);
  Options.Directory := Directory;
  InitializeReports(Options, DataProc, ApplicationVersion);
end;

procedure InitializeReports(const Options: TDiagnosticOptions; DataProc: TDiagnosticDataProc;
  const ApplicationVersion: string);
begin
  If Initialized then raise Exception.Create('Reports are already initialized');
  ReportOptions := Options;
  If ReportOptions.MaxReportsPerRun = 0 then ReportOptions.MaxReportsPerRun := 10;
  If ReportOptions.MaxReportsPerRun < 0 then raise Exception.Create('Report limit must be positive');
  If ReportOptions.Directory = '' then
    ReportOptions.Directory := IncludeTrailingPathDelimiter(ExtractFilePath(ExpandFileName(ParamStr(0)))) + 'BugReports';
  ReportOptions.Directory := ExpandFileName(ReportOptions.Directory);
  If ReportOptions.PostFieldName = '' then ReportOptions.PostFieldName := 'el_upload_file_0';
  If ReportOptions.PostTimeoutMS = 0 then ReportOptions.PostTimeoutMS := 10000;
  If ReportOptions.PostTimeoutMS < 0 then raise Exception.Create('POST timeout must be positive');
  If ReportOptions.PostURL <> '' then begin
    If (Pos('https://', ReportOptions.PostURL) <> 1) and (Pos('http://', ReportOptions.PostURL) <> 1) then
      raise Exception.Create('Diagnostic POST requires an http:// or https:// URL');
    InitializeDiagnosticHttp(Pos('https://', ReportOptions.PostURL) = 1);
  end;
  If not ForceDirectories(ReportOptions.Directory) then raise Exception.Create('Cannot create report directory');
  ApplicationName := ExpandFileName(ParamStr(0));
  ApplicationBuild := ApplicationVersion;
  OSDescription := TOSVersion.ToString;
  StartedTick := GetTickCount64;
  InitializeNative;
  OnData := DataProc;
  InitCriticalSection(ReportLock);
  PreviousFrameLimit := RaiseMaxFrameCount;
  RaiseMaxFrameCount := MaxFrames - 1;
  PreviousCapture := ExceptionContextProc;
  {$ifdef LINUX}
  PreviousBacktrace := ExceptionBacktraceProc;
  {$endif}
  PreviousUnhandled := ExceptProc;
  PreviousThreadUnhandled := UnhandledThreadExceptionProc;
  ExceptionContextProc := @CaptureException;
  {$ifdef LINUX}ExceptionBacktraceProc := @CaptureRTLBacktrace;{$endif}
  ExceptProc := @Unhandled;
  UnhandledThreadExceptionProc := @ThreadUnhandled;
  Initialized := True;
end;

finalization
  If Initialized then begin
    If @ExceptionContextProc = @CaptureException then ExceptionContextProc := PreviousCapture;
    {$ifdef LINUX}
    If @ExceptionBacktraceProc = @CaptureRTLBacktrace then ExceptionBacktraceProc := PreviousBacktrace;
    {$endif}
    If @ExceptProc = @Unhandled then ExceptProc := PreviousUnhandled;
    If @UnhandledThreadExceptionProc = @ThreadUnhandled then UnhandledThreadExceptionProc := PreviousThreadUnhandled;
    If RaiseMaxFrameCount = MaxFrames - 1 then RaiseMaxFrameCount := PreviousFrameLimit;
    DoneCriticalSection(ReportLock);
  end;
end.
