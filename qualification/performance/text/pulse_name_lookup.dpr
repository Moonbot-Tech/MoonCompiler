program pulse_name_lookup;

{$ifndef FPC}
  {$APPTYPE CONSOLE}
{$else}
  {$mode delphi}{$H+}
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

var
  Keys, Queries: array[0..7] of string;
  Shape, Mode: Integer;

function CaseLookup(Iterations: Integer): UInt64;
var
  I, J, Index, FoundIndex: Integer;
  Miss: Boolean;
begin
  Miss := Mode=2;
  Result := 0;
  for I := 0 to Iterations-1 do
  begin
    Index := I and 7;
    FoundIndex := -1;
    for J := 0 to 7 do
      If SameText(Queries[Index],Keys[J]) then
      begin
        FoundIndex := J;
        Break;
      end;
    If (Miss and (FoundIndex<>-1)) or (not Miss and (FoundIndex<>Index)) then
      raise Exception.Create('field lookup result');
    Result := Result+UInt64(FoundIndex+2)*(UInt64(Index)+1);
  end;
end;

procedure PrepareKeys;
const
  Names: array[0..7] of string = ('AccountState','RequestLimit','PayloadBytes','ResponseCode',
    'SessionCount','MessageFlags','RetryTimeout','TimeoutValue');
var I: Integer;
begin
  for I := 0 to 7 do
  begin
    Keys[I] := Names[I];
    If Shape=1 then Keys[I] := 'ServiceConfiguration.'+Keys[I];
    Queries[I] := Copy(Keys[I],1,Length(Keys[I]));
    If Mode=1 then Queries[I] := UpperCase(Queries[I]);
    If Mode=2 then Queries[I][1] := 'X';
  end;
end;

var
  Profile: TPulseProfile;
  SelectedCase, CaseName: string;
  Found: Boolean;
begin
  {$ifdef PULSE_PROGRAM_PREFIX}PulseProgramPrefix;
  {$endif}
  PulseInitialize('pulse_name_lookup',Profile,SelectedCase);
  Found := False;
  for Shape := 0 to 1 do
    for Mode := 0 to 2 do
    begin
      PrepareKeys;
      CaseName := Format('fields-shape%d-mode%d',[Shape,Mode]);
      PulseRunCase('pulse_name_lookup',CaseName,'rtl','SameText',@CaseLookup,1,
        Profile,SelectedCase,Found,@CaseLookup);
    end;
  PulseFinish('pulse_name_lookup',SelectedCase,Found);
end.
