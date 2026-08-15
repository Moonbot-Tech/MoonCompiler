program pulse_calibration;

{$ifndef FPC}
  {$APPTYPE CONSOLE}
{$endif}

{$ifdef FPC}
  {$mode delphi}{$H+}
  {$asmmode intel}
{$endif}

{$Q-}{$R-}

uses
  {$if defined(FPC) and not defined(PULSE_DEFAULT_MM)}
  mormot.core.fpcx64mm,
  {$ifend}
  SysUtils,
  perf_clock in '..\common\perf_clock.pas',
  pulse_process_metrics in '..\common\pulse_process_metrics.pas',
  pulse_harness in '..\common\pulse_harness.pas';

const
  MemoryBytes = 64 * 1024 * 1024;
  MemoryQWords = MemoryBytes div SizeOf(UInt64);

var
  ReadData, WriteData: array of UInt64;

function AsmAddChain(Seed: UInt64; Rounds: NativeUInt): UInt64; assembler;
asm
  {$ifdef MSWINDOWS}
  mov rax, rcx
  mov rcx, rdx
  {$else}
  mov rax, rdi
  mov rcx, rsi
  {$endif}
  test rcx, rcx
  jz @@done
@@round:
  add rax, 1
  add rax, 2
  add rax, 3
  add rax, 4
  add rax, 5
  add rax, 6
  add rax, 7
  add rax, 8
  add rax, 9
  add rax, 10
  add rax, 11
  add rax, 12
  add rax, 13
  add rax, 14
  add rax, 15
  add rax, 16
  add rax, 17
  add rax, 18
  add rax, 19
  add rax, 20
  add rax, 21
  add rax, 22
  add rax, 23
  add rax, 24
  add rax, 25
  add rax, 26
  add rax, 27
  add rax, 28
  add rax, 29
  add rax, 30
  add rax, 31
  add rax, 32
  add rax, 33
  add rax, 34
  add rax, 35
  add rax, 36
  add rax, 37
  add rax, 38
  add rax, 39
  add rax, 40
  add rax, 41
  add rax, 42
  add rax, 43
  add rax, 44
  add rax, 45
  add rax, 46
  add rax, 47
  add rax, 48
  add rax, 49
  add rax, 50
  add rax, 51
  add rax, 52
  add rax, 53
  add rax, 54
  add rax, 55
  add rax, 56
  add rax, 57
  add rax, 58
  add rax, 59
  add rax, 60
  add rax, 61
  add rax, 62
  add rax, 63
  add rax, 64
  dec rcx
  jnz @@round
@@done:
end;

function AsmMixedChain(Seed: UInt64; Rounds: NativeUInt): UInt64; assembler;
asm
  {$ifdef MSWINDOWS}
  mov rax, rcx
  mov rcx, rdx
  {$else}
  mov rax, rdi
  mov rcx, rsi
  {$endif}
  test rcx, rcx
  jz @@done
@@round:
  imul rax, rax, 3
  add rax, 17
  ror rax, 13
  imul rax, rax, 5
  xor rax, $5a5a5a5a
  rol rax, 7
  imul rax, rax, 9
  add rax, 31
  ror rax, 11
  imul rax, rax, 3
  xor rax, $33cc33cc
  rol rax, 17
  imul rax, rax, 5
  add rax, 47
  ror rax, 19
  xor rax, $0f0f0f0f
  dec rcx
  jnz @@round
@@done:
end;

function AsmMemoryRead(Data: Pointer; Count: NativeUInt): UInt64; assembler;
asm
  {$ifdef MSWINDOWS}
  mov r8, rcx
  mov r9, rdx
  {$else}
  mov r8, rdi
  mov r9, rsi
  {$endif}
  xor rax, rax
  test r9, r9
  jz @@done
@@loop:
  add rax, [r8]
  add rax, [r8 + 8]
  add rax, [r8 + 16]
  add rax, [r8 + 24]
  add rax, [r8 + 32]
  add rax, [r8 + 40]
  add rax, [r8 + 48]
  add rax, [r8 + 56]
  add r8, 64
  sub r9, 8
  jnz @@loop
@@done:
end;

function AsmMemoryWrite(Data: Pointer; Count: NativeUInt; Seed: UInt64): UInt64;
  assembler;
asm
  {$ifdef MSWINDOWS}
  mov r9, rcx
  mov r10, rdx
  mov rax, r8
  {$else}
  mov r9, rdi
  mov r10, rsi
  mov rax, rdx
  {$endif}
  test r10, r10
  jz @@done
@@loop:
  mov [r9], rax
  mov [r9 + 8], rax
  mov [r9 + 16], rax
  mov [r9 + 24], rax
  mov [r9 + 32], rax
  mov [r9 + 40], rax
  mov [r9 + 48], rax
  mov [r9 + 56], rax
  add r9, 64
  add rax, 1
  sub r10, 8
  jnz @@loop
@@done:
end;

function CaseAsmAdd(Iterations: Integer): UInt64;
begin
  Result := AsmAddChain(UInt64($123456789ABCDEF0), NativeUInt(Iterations));
end;

function CaseAsmMixed(Iterations: Integer): UInt64;
begin
  Result := AsmMixedChain(UInt64($123456789ABCDEF0), NativeUInt(Iterations));
end;

function CaseMemoryRead(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    Result := Result xor AsmMemoryRead(@ReadData[0], MemoryQWords);
end;

function CaseMemoryWrite(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    Result := Result xor AsmMemoryWrite(@WriteData[0], MemoryQWords,
      UInt64($D1B54A32D192ED03) + UInt64(I));
end;

procedure InitializeData;
var
  I: Integer;
begin
  SetLength(ReadData, MemoryQWords);
  SetLength(WriteData, MemoryQWords);
  for I := 0 to High(ReadData) do
  begin
    ReadData[I] := UInt64(I) * UInt64($9E3779B185EBCA87);
    WriteData[I] := 0;
  end;
end;

procedure Run;
var
  Profile: TPulseProfile;
  SelectedCase: string;
  Found: Boolean;
begin
  PulseInitialize('pulse_calibration', Profile, SelectedCase);
  InitializeData;
  Found := False;
  PulseRunCase('pulse_calibration', 'asm-dependent-add', 'calibration',
    'instruction', @CaseAsmAdd, 64, Profile, SelectedCase, Found);
  PulseRunCase('pulse_calibration', 'asm-mixed-integer', 'calibration',
    'instruction', @CaseAsmMixed, 16, Profile, SelectedCase, Found);
  PulseRunCase('pulse_calibration', 'asm-memory-read-64m', 'calibration',
    'byte', @CaseMemoryRead, MemoryBytes, Profile, SelectedCase, Found);
  PulseRunCase('pulse_calibration', 'asm-memory-write-64m', 'calibration',
    'byte', @CaseMemoryWrite, MemoryBytes, Profile, SelectedCase, Found);
  PulseFinish('pulse_calibration', SelectedCase, Found);
end;

begin
  try
    Run;
  except
    on E: Exception do
    begin
      WriteLn(ErrOutput, E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
