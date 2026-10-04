program pulse_record_stream;

{$ifndef FPC}
  {$APPTYPE CONSOLE}
{$endif}

{$ifdef FPC}
  {$mode delphi}{$H+}
{$endif}

{$Q-}{$R-}
{$POINTERMATH ON}

uses
  {$if defined(FPC) and not defined(PULSE_DEFAULT_MM)}
  mormot.core.fpcx64mm,
  {$ifend}
  {$I ../common/pulse_placement_uses.inc}
  SysUtils,
  perf_clock in '..\common\perf_clock.pas',
  pulse_process_metrics in '..\common\pulse_process_metrics.pas',
  pulse_harness in '..\common\pulse_harness.pas';

{$I ../common/pulse_program_prefix.inc}

type TMoveProc=procedure(const Source;var Dest;Count:NativeInt);
function ConsumeBytes(P: PByte; Count: NativeInt): UInt64;
var i: NativeInt;
  Sum: UInt64;
begin
  Sum := 0;
  i := 0;
  while i+8 <= Count do
  begin
    Sum := Sum xor PUInt64(P+i)^;
    Inc(i,8);
  end;
  while i < Count do
  begin
    Sum := Sum xor (UInt64(P[i]) shl ((i and 7)*8));
    Inc(i);
  end;
  Result := Sum;
end;

type
  TFrameHeader=record
    Id,Length,Digest:UInt64;
  end;
  PFrameHeader=^TFrameHeader;
  TFrameInputs=array[0..7] of PByte;
  TFrameOutputs=array[0..63] of PByte;

var FrameInputs:TFrameInputs;
  FrameOutputs:TFrameOutputs;
  FrameWindow:PByte;
  FrameLengths:array[0..7] of NativeInt;
  FrameDigests:array[0..7] of UInt64;
  SeenFrame:array[0..127] of Boolean;

function ConsumeFrame(P:PByte; Verify:Boolean):UInt64;
var H:PFrameHeader;
  i,Index:NativeInt;
  Digest:UInt64;
begin
  H:=PFrameHeader(P);
  Index:=H.Id and 7;
  If H.Length<>UInt64(FrameLengths[Index]) then raise Exception.Create('frame length corrupted');
  Digest:=ConsumeBytes(P+SizeOf(TFrameHeader),H.Length);
  If Digest<>H.Digest then raise Exception.Create('frame content digest corrupted');
  If Verify then
    for i:=0 to H.Length-1 do
      If P[SizeOf(TFrameHeader)+i]<>FrameInputs[Index][i] then
        raise Exception.Create('retained frame content corrupted');
  Result:=Digest+H.Id;
end;

function FrameStream(F:TMoveProc; Priority,Live,Iterations:Integer; Verify:Boolean):UInt64;
var Header:TFrameHeader;
  Window:PByte;
  Used,Pending,Produced,Slot,Index,Length:NativeInt;
  Serial,RetainedCount:Integer;
  Sum:UInt64;
  procedure PopFrame;
  var H:PFrameHeader;
    Total:NativeInt;
  begin
    H:=PFrameHeader(Window);
    If Verify then
    begin
      If H.Id>=UInt64(Iterations) then raise Exception.Create('frame ID bounds');
      If SeenFrame[H.Id] then raise Exception.Create('duplicate frame ID');
      SeenFrame[H.Id]:=True;
    end;
    Total:=SizeOf(TFrameHeader)+H.Length;
    If (Total>Used) or (Total<=SizeOf(TFrameHeader)) then raise Exception.Create('framing bounds');
    Slot:=Produced and (Live-1);
    If Produced>=Live then Sum:=Sum+ConsumeFrame(FrameOutputs[Slot],Verify);
    F(Window^,FrameOutputs[Slot]^,Total);
    Inc(Produced);
    Dec(Used,Total);
    Dec(Pending);
    If Used>0 then F(Window[Total],Window[0],Used);
  end;
begin
  Window:=FrameWindow;
  RetainedCount:=Live;
  If RetainedCount>Iterations then RetainedCount:=Iterations;
  Sum:=0;
  Used:=0;
  Pending:=0;
  Produced:=0;
  If Verify then
  begin
    If Iterations>High(SeenFrame)+1 then raise Exception.Create('frame oracle extent');
    FillChar(SeenFrame,SizeOf(SeenFrame),0);
  end;
  for Serial:=0 to Iterations-1 do
  begin
    Index:=Serial and 7;
    Header.Id:=Serial;
    Header.Length:=FrameLengths[Index];
    Header.Digest:=FrameDigests[Index];
    Length:=SizeOf(Header)+Header.Length;
    If (Priority<>0) and ((Serial and 3)=0) then
    begin
      If Used>0 then F(Window[0],Window[Length],Used);
      F(Header,Window[0],SizeOf(Header));
      F(FrameInputs[Index]^,Window[SizeOf(Header)],Header.Length);
    end else begin
      F(Header,Window[Used],SizeOf(Header));
      F(FrameInputs[Index]^,Window[Used+SizeOf(Header)],Header.Length);
    end;
    Inc(Used,Length);
    Inc(Pending);
    If Pending>=4 then PopFrame;
  end;
  while Pending>0 do PopFrame;
  for Slot:=0 to RetainedCount-1 do Sum:=Sum+ConsumeFrame(FrameOutputs[Slot],Verify);
  If Produced<>Iterations then raise Exception.Create('framing count');
  If Verify then
    for Serial:=0 to Iterations-1 do
      If not SeenFrame[Serial] then raise Exception.Create('missing frame ID');
  Result:=Sum;
end;

procedure PrepareFrames(Profile:Integer);
const Sizes:array[0..1,0..7] of Integer=((12,16,24,33,48,63,80,96),(129,193,320,512,1024,2048,4096,16384));
var i,j:Integer;
  State:Cardinal;
begin
  for j:=0 to High(FrameInputs) do
  begin
    FrameLengths[j]:=Sizes[Profile,j];
    State:=$59a6173b xor Cardinal(j*65537);
    for i:=0 to FrameLengths[j]-1 do
    begin
      State:=State xor(State shl 13);
      State:=State xor(State shr 17);
      State:=State xor(State shl 5);
      FrameInputs[j][i]:=Byte(State);
    end;
    FrameDigests[j]:=ConsumeBytes(FrameInputs[j],FrameLengths[j]);
  end;
end;


var ActivePriority,ActiveLive:Integer;
function CaseRecordStream(Iterations:Integer):UInt64;
var Expected,BlockDigest:UInt64;
  i:Integer;
begin
  Result:=FrameStream(TMoveProc(@System.Move),ActivePriority,ActiveLive,Iterations,False);
  BlockDigest:=0;
  for i:=0 to 7 do BlockDigest:=BlockDigest+FrameDigests[i];
  Expected:=UInt64(Iterations)*(Iterations-1) div 2+UInt64(Iterations div 8)*BlockDigest;
  for i:=0 to (Iterations and 7)-1 do Expected:=Expected+FrameDigests[i];
  If Result<>Expected then raise Exception.Create('record stream ID/content sequence');
end;
var Profile:TPulseProfile;
  SelectedCase,CaseName:string;
  Found:Boolean;
  InputMem:TFrameInputs;
  OutputMem:TFrameOutputs;
  WindowMem:PByte;
  Shape,Phase,Priority,Live,i:Integer;
begin
  {$ifdef PULSE_PROGRAM_PREFIX}PulseProgramPrefix;
  {$endif}
  PulseInitialize('pulse_record_stream',Profile,SelectedCase);
  for i:=0 to High(InputMem) do GetMem(InputMem[i],16384+128);
  for i:=0 to High(OutputMem) do GetMem(OutputMem[i],16384+SizeOf(TFrameHeader)+128);
  GetMem(WindowMem,128*1024+128);
  try
    Found:=False;
    for Shape:=0 to 1 do
      for Phase:=0 to 1 do
      begin
        for i:=0 to High(InputMem) do FrameInputs[i]:=InputMem[i]+Phase*32;
        for i:=0 to High(OutputMem) do FrameOutputs[i]:=OutputMem[i]+Phase*16;
        FrameWindow:=WindowMem+Phase*32;
        PrepareFrames(Shape);
        for Priority:=0 to 1 do
          for Live in [8,64] do
          begin
            ActivePriority:=Priority;
            ActiveLive:=Live;
            CaseName:=Format('shape%d-priority%d-retain%d-phase%d',[Shape,Priority,Live,Phase]);
            If (Profile.Name<>'list') and CaseSelected(SelectedCase,CaseName) then
              FrameStream(TMoveProc(@System.Move),Priority,Live,128,True);
            PulseRunCaseData('pulse_record_stream',CaseName,'rtl+memory','System.Move',@CaseRecordStream,1,
              Profile,SelectedCase,Found,@FrameStream,PulseData('window',FrameWindow));
          end;
      end;
    PulseFinish('pulse_record_stream',SelectedCase,Found);
  finally
    FreeMem(WindowMem);
    for i:=0 to High(OutputMem) do FreeMem(OutputMem[i]);
    for i:=0 to High(InputMem) do FreeMem(InputMem[i]);
  end;
end.
