program thread_stdio_semantic;

{$ifdef FPC}
  {$mode delphi}
{$endif}

{$Q-}{$R-}

uses
  {$ifdef FPC}
  mormot.core.fpcx64mm,
  Windows,
  {$else}
  Winapi.Windows,
  {$endif}
  SysUtils,
  Classes;

procedure Fail(const NameText: string);
begin
  WriteLn('FAIL ', NameText);
  Halt(1);
end;

type
  TCpProbe = class(TThread)
  public
    InCp, OutCp, ErrCp: Cardinal;
    procedure Execute; override;
  end;

procedure TCpProbe.Execute;
begin
  InCp := TextRec(Input).CodePage;
  OutCp := TextRec(Output).CodePage;
  ErrCp := TextRec(ErrOutput).CodePage;
end;

function ProbeThread: TCpProbe;
begin
  Result := TCpProbe.Create(False);
  Result.FreeOnTerminate := False;
  Result.WaitFor;
end;

var
  MainIn, MainOut, LiveOut, AltCp: Cardinal;
  Probe: TCpProbe;
  I: Integer;
begin
  MainIn := TextRec(Input).CodePage;
  MainOut := TextRec(Output).CodePage;

  { every worker thread re-opens its threadvar stdio; the code pages must
    match what the main thread was set up with }
  for I := 1 to 8 do
  begin
    Probe := ProbeThread;
    If Probe.InCp <> MainIn then
      Fail('worker input codepage differs from main');
    If (Probe.OutCp <> MainOut) or (Probe.ErrCp <> MainOut) then
      Fail('worker output codepage differs from main');
    FreeAndNil(Probe);
  end;

  LiveOut := GetConsoleOutputCP;
  If (LiveOut <> 0) and (MainOut <> LiveOut) then
    Fail('main output codepage does not match the console');

  { the console code page is snapshotted per process: a change after startup
    must not leak into stdio of new threads, exactly like the main thread
    keeps its startup value }
  If LiveOut <> 0 then
  begin
    AltCp := 437;
    If LiveOut = 437 then
      AltCp := 850;
    If SetConsoleOutputCP(AltCp) then
    begin
      try
        Probe := ProbeThread;
        If Probe.OutCp <> MainOut then
          Fail('runtime console change leaked into a new thread');
        FreeAndNil(Probe);
      finally
        SetConsoleOutputCP(LiveOut);
      end;
    end;
  end;

  WriteLn('THREAD_STDIO_SEMANTIC_OK');
end.
