program pulse_ordinal_scan;

{$ifndef FPC}{$APPTYPE CONSOLE}{$endif}
{$ifdef FPC}{$mode delphiunicode}{$H+}{$endif}
{$Q-}{$R-}{$POINTERMATH ON}

uses
  {$if defined(FPC) and not defined(PULSE_DEFAULT_MM)}mormot.core.fpcx64mm,{$ifend}
  {$I ../common/pulse_placement_uses.inc}
  SysUtils, Generics.Collections,
  perf_clock in '..\common\perf_clock.pas',
  pulse_process_metrics in '..\common\pulse_process_metrics.pas',
  pulse_harness in '..\common\pulse_harness.pas';

{$I ../common/pulse_program_prefix.inc}

const Counts: array[0..1] of Integer = (64,256);
type
  TSmallKey = record Bytes: array[0..7] of Byte; end;
  TLargeKey = record Bytes: array[0..191] of Byte; end;
  TScan<T> = class
    class var Dictionary: TDictionary<T,Integer>;
    class var Count, Mode: Integer;
    class function Measure(Iterations: Integer): UInt64; static;
    class procedure Prepare(ACount, ReserveFactor, AMode: Integer); static;
  end;
var SelectedKeySize: Integer;

class procedure TScan<T>.Prepare(ACount, ReserveFactor, AMode: Integer);
var
  I, J, Index: Integer;
  Key: T;
  State: Cardinal;
  Bytes: PByte;
begin
  Count := ACount;
  Mode := AMode;
  Dictionary := TDictionary<T,Integer>.Create(Count*ReserveFactor);
  for I := 0 to Count-1 do
  begin
    Index := (I*4051) and (Count-1);
    State := Cardinal(Index)+$659a834b;
    Bytes := @Key;
    for J := 0 to SizeOf(T)-1 do
    begin
      State := State xor (State shl 13);
      State := State xor (State shr 17);
      State := State xor (State shl 5);
      Bytes[J] := Byte(State);
    end;
    Dictionary.Add(Key,Index*3);
    If (Mode=2) and (Index=0) then Dictionary.Remove(Key);
  end;
  for I := 0 to Count-1 do
    If Dictionary.ContainsValue(I*3)<>((Mode<>2) or (I<>0)) then
      raise Exception.Create('ordinal scan value oracle');
  If Dictionary.ContainsValue(-1) then raise Exception.Create('ordinal scan miss oracle');
end;

class function TScan<T>.Measure(Iterations: Integer): UInt64;
var
  I, Value: Integer;
begin
  Result := 0;
  for I := 0 to Iterations-1 do
  begin
    Value := -1;
    If Mode=1 then
    begin
      If I and 1=0 then Value := ((I*17) and (Count-1))*3;
    end
    else If Mode=2 then Value := 0;
    If Dictionary.ContainsValue(Value) then Inc(Result);
  end;
  If Result<>UInt64(Ord(Mode=1))*UInt64((Iterations+1) div 2) then
    raise Exception.Create('ordinal scan useful result');
end;

function CaseScan(Iterations: Integer): UInt64;
begin
  If SelectedKeySize=0 then Result := TScan<TSmallKey>.Measure(Iterations)
  else Result := TScan<TLargeKey>.Measure(Iterations);
end;

var
  Profile: TPulseProfile;
  SelectedCase, CaseName: string;
  Found: Boolean;
  KeySize, Count, ReserveFactor, Mode: Integer;
begin
  {$ifdef PULSE_PROGRAM_PREFIX}PulseProgramPrefix;{$endif}
  PulseInitialize('pulse_ordinal_scan',Profile,SelectedCase);
  Found := False;
  for KeySize := 0 to 1 do
    for Count in Counts do
      for ReserveFactor in [1,8] do
        for Mode := 0 to 2 do
        begin
          SelectedKeySize := KeySize;
          CaseName := Format('key%d-count%d-reserve%d-mode%d',[KeySize,Count,ReserveFactor,Mode]);
          If (Profile.Name='list') or not CaseSelected(SelectedCase,CaseName) then
          begin
            PulseRunCase('pulse_ordinal_scan',CaseName,'collections+memory','ContainsValue',@CaseScan,
              1,Profile,SelectedCase,Found);
            Continue;
          end;
          If KeySize=0 then TScan<TSmallKey>.Prepare(Count,ReserveFactor,Mode)
          else TScan<TLargeKey>.Prepare(Count,ReserveFactor,Mode);
          try
            PulseRunCase('pulse_ordinal_scan',CaseName,'collections+memory','ContainsValue',@CaseScan,
              1,Profile,SelectedCase,Found);
          finally
            If KeySize=0 then FreeAndNil(TScan<TSmallKey>.Dictionary)
            else FreeAndNil(TScan<TLargeKey>.Dictionary);
          end;
        end;
  PulseFinish('pulse_ordinal_scan',SelectedCase,Found);
end.
