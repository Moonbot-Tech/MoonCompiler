program pulse_text_pipeline;

{$ifndef FPC}
  {$APPTYPE CONSOLE}
{$endif}
{$ifdef FPC}
  {$mode delphiunicode}{$H+}
{$endif}
{$Q-}{$R-}

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

const
  RecordsPerTrace = 256;
  Names: array[0..15] of string = ('account', 'balance', 'currency', 'quantity',
    'symbol', 'price', 'timestamp', 'sequence', 'status', 'reason', 'source', 'destination',
    'checksum', 'version', 'flags', 'priority');
  FieldCounts: array[0..2] of Integer = (4,16,64);
type
  TFields = TArray<string>;
  TInput = record
    Key, InputKey, LookupKey, Value: string;
    Fields: TFields;
    Raw: UTF8String;
  end;
  TRetained = record
    Id: Integer;
    Key: string;
    Fields: TFields;
    Raw: UTF8String;
  end;
var
  Inputs: array[0..15] of TInput;
  ActiveLive: Integer;

function Consume(const Key: string; const Fields: TFields; const Raw: UTF8String): UInt64;
var
  I, J: Integer;
  Sum: UInt64;
begin
  Sum := Length(Key)+Length(Fields)+Length(Raw);
  for I := 1 to Length(Key) do Sum := Sum+Ord(Key[I]);
  for I := 0 to High(Fields) do
  begin
    Sum := Sum+Length(Fields[I]);
    for J := 1 to Length(Fields[I]) do Sum := Sum+Ord(Fields[I][J]);
  end;
  for I := 1 to Length(Raw) do Sum := Sum+Ord(Raw[I]);
  Result := Sum;
end;

procedure CheckRecord(Id: Integer; const Key: string; const Fields: TFields; const Raw: UTF8String);
var
  I: Integer;
begin
  If Key<>Inputs[Id].LookupKey then raise Exception.Create('text key identity');
  If Length(Fields)<>Length(Inputs[Id].Fields) then raise Exception.Create('text field count');
  for I := 0 to High(Fields) do
    If Fields[I]<>Inputs[Id].Fields[I] then raise Exception.Create('text field contents');
  If Raw<>Inputs[Id].Raw then raise Exception.Create('text UTF8 output');
end;

function RunTrace(Live: Integer; Verify: Boolean): UInt64;
var
  Retained: array of TRetained;
  Key: string;
  Fields: TFields;
  Raw: UTF8String;
  I, J, Id, Found, Slot, Filled: Integer;
  Sum, Expected: UInt64;
begin
  SetLength(Retained,Live);
  Sum := 0;
  Expected := 0;
  Filled := 0;
  for I := 0 to RecordsPerTrace-1 do
  begin
    Id := (I*5) and 15;
    Key := Trim(Inputs[Id].InputKey);
    Found := -1;
    for J := 0 to High(Inputs) do
      If CompareText(Key,Inputs[J].Key)=0 then
      begin
        Found := J;
        Break;
      end;
    If Found<>Id then raise Exception.Create('text lookup identity');
    Fields := Inputs[Found].Value.Split([',']);
    for J := 0 to High(Fields) do Fields[J] := Trim(Fields[J]);
    Raw := UTF8Encode(Fields[High(Fields)]);
    If Verify then CheckRecord(Id,Key,Fields,Raw);
    Sum := Sum+Consume(Key,Fields,Raw)+UInt64(Id);
    If Verify then Expected := Expected+Consume(Inputs[Id].LookupKey,Inputs[Id].Fields,Inputs[Id].Raw)+UInt64(Id);
    If Live<>0 then
    begin
      Slot := I and (Live-1);
      If I>=Live then
      begin
        If Verify then CheckRecord(Retained[Slot].Id,Retained[Slot].Key,Retained[Slot].Fields,Retained[Slot].Raw);
        Sum := Sum+Consume(Retained[Slot].Key,Retained[Slot].Fields,Retained[Slot].Raw)+UInt64(Retained[Slot].Id);
      end;
      Retained[Slot].Id := Id;
      Retained[Slot].Key := Key;
      Retained[Slot].Fields := Fields;
      Retained[Slot].Raw := Raw;
      If Filled<Live then Inc(Filled);
    end;
  end;
  for I := 0 to Filled-1 do
  begin
    If Verify then CheckRecord(Retained[I].Id,Retained[I].Key,Retained[I].Fields,Retained[I].Raw);
    Sum := Sum+Consume(Retained[I].Key,Retained[I].Fields,Retained[I].Raw)+UInt64(Retained[I].Id);
  end;
  If Verify then
  begin
    If Live<>0 then Expected := Expected*2;
    If Sum<>Expected then raise Exception.Create('text trace digest');
  end;
  Result := Sum;
end;

procedure Prepare(Shape, FieldCount, Mode: Integer);
var
  I, J, K, N: Integer;
  Token: string;
begin
  for I := 0 to High(Inputs) do
  begin
    Inputs[I].Key := Names[I];
    If Shape=1 then Inputs[I].Key := 'group'+IntToStr(I div 4)+'.'+Names[I];
    If Shape=2 then Inputs[I].Key := 'record.configuration.incoming.message.'+Names[I];
    Inputs[I].InputKey := Inputs[I].Key;
    If (Mode=1) and (I and 1<>0) then
    begin
      for K := 1 to Length(Inputs[I].InputKey) do
        If (Inputs[I].InputKey[K]>='a') and (Inputs[I].InputKey[K]<='z') then
          Inputs[I].InputKey[K] := Char(Ord(Inputs[I].InputKey[K])-32);
    end;
    Inputs[I].LookupKey := Inputs[I].InputKey;
    If (Mode=1) and (I and 1<>0) then Inputs[I].InputKey := ' '+Inputs[I].InputKey+' ';
    Inputs[I].Value := '';
    SetLength(Inputs[I].Fields,FieldCount);
    for J := 0 to FieldCount-1 do
    begin
      Token := IntToStr(I)+'-'+IntToStr(J)+'-'+Char($0416);
      Inputs[I].Fields[J] := Token;
      If J<>0 then Inputs[I].Value := Inputs[I].Value+',';
      If (Mode=1) and (J and 1<>0) then Token := ' '+Token+' ';
      Inputs[I].Value := Inputs[I].Value+Token;
    end;
    Token := IntToStr(I)+'-'+IntToStr(FieldCount-1)+'-';
    N := Length(Token);
    SetLength(Inputs[I].Raw,N+2);
    for K := 1 to N do Inputs[I].Raw[K] := AnsiChar(Ord(Token[K]));
    Inputs[I].Raw[N+1] := AnsiChar($d0);
    Inputs[I].Raw[N+2] := AnsiChar($96);
  end;
end;

function CasePipeline(Iterations: Integer): UInt64;
var
  I, Live: Integer;
begin
  Live := ActiveLive;
  Result := 0;
  for I := 1 to Iterations do Result := Result+RunTrace(Live,False);
end;

var
  Profile: TPulseProfile;
  SelectedCase, CaseName: string;
  Found: Boolean;
  Shape, Fields, Mode, Live: Integer;
begin
  {$ifdef PULSE_PROGRAM_PREFIX}PulseProgramPrefix;
  {$endif}
  PulseInitialize('pulse_text_pipeline',Profile,SelectedCase);
  Found := False;
  for Shape := 0 to 2 do
    for Fields in FieldCounts do
      for Mode := 0 to 1 do
      begin
        Prepare(Shape,Fields,Mode);
        for Live in [0,64] do
        begin
          ActiveLive := Live;
          CaseName := Format('shape%d-fields%d-mixed%d-retain%d',[Shape,Fields,Mode,Live]);
          If (Profile.Name<>'list') and CaseSelected(SelectedCase,CaseName) then RunTrace(Live,True);
          PulseRunCase('pulse_text_pipeline',CaseName,'rtl+memory','text pipeline',@CasePipeline,
            RecordsPerTrace,Profile,SelectedCase,Found,@RunTrace);
        end;
      end;
  PulseFinish('pulse_text_pipeline',SelectedCase,Found);
end.
