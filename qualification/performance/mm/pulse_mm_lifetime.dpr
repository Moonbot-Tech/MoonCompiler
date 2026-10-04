program pulse_mm_lifetime;

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

type
  PMessage=^TMessage;
  TMessage=record
    Payload:PByte;
    Length:NativeInt;
    Id,Digest:UInt64;
  end;
  TMessages=array[0..255] of PMessage;
const PayloadSizes:array[0..8] of Integer=(24,32,48,96,128,193,512,2048,8192);
  LiveCounts:array[0..2] of Integer=(8,64,256);
var InputData:array[0..8,0..8191] of Byte;
  InputDigest:array[0..8] of UInt64;

function DigestBytes(P:PByte; Count:NativeInt):UInt64;
var i:NativeInt;
  Sum:UInt64;
begin
  Sum:=0;
  i:=0;
  while i+8<=Count do
  begin
    Sum:=Sum xor PUInt64(P+i)^;
    Inc(i,8);
  end;
  while i<Count do
  begin
    Sum:=Sum xor(UInt64(P[i]) shl((i and 7)*8));
    Inc(i);
  end;
  Result:=Sum;
end;

function NewMessage(Id:UInt64; Index:Integer):PMessage;
begin
  GetMem(Result,SizeOf(TMessage));
  Result.Length:=PayloadSizes[Index];
  Result.Id:=Id;
  GetMem(Result.Payload,Result.Length);
  Move(InputData[Index,0],Result.Payload^,Result.Length);
  Result.Digest:=InputDigest[Index];
end;

function Consume(Message:PMessage; Verify:Boolean):UInt64;
var i,Index:Integer;
  Digest:UInt64;
begin
  Digest:=DigestBytes(Message.Payload,Message.Length);
  If Digest<>Message.Digest then raise Exception.Create('message content digest');
  If Verify then
  begin
    Index:=0;
    while (Index<High(PayloadSizes)) and (PayloadSizes[Index]<>Message.Length) do Inc(Index);
    If PayloadSizes[Index]<>Message.Length then raise Exception.Create('payload length');
    for i:=0 to Message.Length-1 do
    begin
      If Message.Payload[i]<>InputData[Index,i] then raise Exception.Create('retained payload content');
    end;
  end;
  Result:=Digest+Message.Id;
  FreeMem(Message.Payload);
  FreeMem(Message);
end;

function RunMessages(Kind,Live,Roots,Iterations:Integer; Verify:Boolean):UInt64;
var Queue,Retained:TMessages;
  i,Slot,Index:Integer;
  Next:PMessage;
  Sum:UInt64;
begin
  for i:=0 to Roots-1 do Retained[i]:=NewMessage(i,i mod Length(PayloadSizes));
  for i:=0 to Live-1 do Queue[i]:=NewMessage(i,i mod Length(PayloadSizes));
  Sum:=0;
  for i:=0 to Iterations-1 do
  begin
    Slot:=i and(Live-1);
    case Kind of
      0: Index:=1;
      1: Index:=i and 7;
    else Index:=(i xor(i shr 4)) and 7;
    end;
    If (Kind<>0) and (Index<>0) then Inc(Index);
    Next:=NewMessage(i+Live,Index);
    Sum:=Sum+Consume(Queue[Slot],Verify);
    Queue[Slot]:=Next;
  end;
  for i:=0 to Live-1 do Sum:=Sum+Consume(Queue[i],Verify);
  for i:=0 to Roots-1 do Sum:=Sum+Consume(Retained[i],Verify);
  Result:=Sum;
end;


var ActiveKind,ActiveLive,ActiveRoots:Integer;
const ReplacementsPerTrace=8192;
function CaseMessages(Iterations:Integer):UInt64;
var i,Kind,Live,Roots:Integer;
begin
  Kind:=ActiveKind;
  Live:=ActiveLive;
  Roots:=ActiveRoots;
  Result:=0;
  for i:=1 to Iterations do
    Result:=Result+RunMessages(Kind,Live,Roots,ReplacementsPerTrace,False);
end;
var Profile:TPulseProfile;
  SelectedCase,CaseName:string;
  Found:Boolean;
  i,j,Kind,Live,Roots:Integer;
  State:Cardinal;
begin
  {$ifdef PULSE_PROGRAM_PREFIX}PulseProgramPrefix;
  {$endif}
  PulseInitialize('pulse_mm_lifetime',Profile,SelectedCase);
  If SizeOf(TMessage)<>32 then raise Exception.Create('message header ABI');
  for j:=0 to High(PayloadSizes) do
  begin
    State:=$659a834b xor Cardinal(j*65537);
    for i:=0 to PayloadSizes[j]-1 do
    begin
      State:=State xor(State shl 13);
      State:=State xor(State shr 17);
      State:=State xor(State shl 5);
      InputData[j,i]:=Byte(State);
    end;
    InputDigest[j]:=DigestBytes(@InputData[j,0],PayloadSizes[j]);
  end;
  Found:=False;
  for Kind:=0 to 2 do
    for Live in LiveCounts do
      for Roots in [0,64] do
      begin
        ActiveKind:=Kind;
        ActiveLive:=Live;
        ActiveRoots:=Roots;
        CaseName:=Format('kind%d-live%d-roots%d',[Kind,Live,Roots]);
        If (Profile.Name<>'list') and CaseSelected(SelectedCase,CaseName) then
          RunMessages(Kind,Live,Roots,512,True);
        PulseRunCase('pulse_mm_lifetime',CaseName,'mm+memory','GetMem/FreeMem',@CaseMessages,ReplacementsPerTrace,
          Profile,SelectedCase,Found,@RunMessages);
      end;
  PulseFinish('pulse_mm_lifetime',SelectedCase,Found);
end.
