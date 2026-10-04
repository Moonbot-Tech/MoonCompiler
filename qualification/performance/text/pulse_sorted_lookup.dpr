program pulse_sorted_lookup;
{$ifdef FPC}{$mode delphiunicode}{$else}{$APPTYPE CONSOLE}{$endif}
{$R-}{$Q-}
uses
  {$if defined(FPC) and not defined(PULSE_DEFAULT_MM)}mormot.core.fpcx64mm,{$endif}
  {$I ../common/pulse_placement_uses.inc}
  SysUtils, Classes, perf_clock, pulse_process_metrics, pulse_harness;
{$I ../common/pulse_program_prefix.inc}
type
  TRow = class
    Id: Integer;
  end;
const Counts: array[0..2] of Integer = (4, 32, 256);
var
  Names: TStringList;
  Rows: array of TRow;
  Queries: array[0..7] of UnicodeString;
  Expected: array[0..7] of Integer;
  Shape, N: Integer;
function Key(I: Integer): UnicodeString;
begin
  If Shape = 0 then
    Result := Format('field%.4d', [I])
  else
    Result := WideChar(Ord('A') + I mod 26) + Format('%.4d', [I]);
end;
function CaseLookup(Iterations: Integer): UInt64;
var
  I, J, Index: Integer;
  List: TStringList;
begin
  List := Names;
  Result := 0;
  for I := 0 to Iterations - 1 do
    for J := 0 to 7 do
      If List.Find(Queries[J], Index) then
        Result := Result + UInt64(TRow(List.Objects[Index]).Id)
      else
        Inc(Result);
end;
procedure Prepare;
var
  I, Index: Integer;
  Sum: UInt64;
begin
  Names := TStringList.Create;
  Names.Sorted := True;
  {$ifdef FPC}
  Names.UseLocale := False;
  {$endif}
  SetLength(Rows, N);
  for I := 0 to N - 1 do
  begin
    Rows[I] := TRow.Create;
    Rows[I].Id := I + 100;
    Names.AddObject(Key(I), Rows[I]);
  end;
  Sum := 0;
  for I := 0 to 7 do
  begin
    Index := (I * 173) mod N;
    Expected[I] := Index + 100;
    Queries[I] := Key(Index);
    If I and 3 = 3 then
    begin
      Queries[I] := '!missing';
      Expected[I] := 1;
    end;
    If I and 1 = 0 then
      Queries[I] := UpperCase(Queries[I]);
    Sum := Sum + UInt64(Expected[I]);
  end;
  for I := 0 to 7 do
  begin
    If Names.Find(Queries[I], Index) then
    begin
      If TRow(Names.Objects[Index]).Id <> Expected[I] then
        raise Exception.Create('sorted row identity');
    end else If Expected[I] <> 1 then
      raise Exception.Create('sorted row missing');
  end;
  If CaseLookup(1) <> Sum then
    raise Exception.Create('sorted row lookup');
end;
procedure Cleanup;
var R: TRow;
begin
  Names.Free;
  for R in Rows do
    R.Free;
  Rows := nil;
end;
var
  Profile: TPulseProfile;
  SelectedCase, Name: UnicodeString;
  Found: Boolean;
  CountIndex: Integer;
begin
  {$ifdef PULSE_PROGRAM_PREFIX}PulseProgramPrefix;{$endif}
  PulseInitialize('pulse_sorted_lookup', Profile, SelectedCase);
  Found := False;
  for Shape := 0 to 1 do
    for CountIndex := 0 to 2 do
    begin
      N := Counts[CountIndex];
      Prepare;
      Name := Format('sorted-n%d-shape%d', [N, Shape]);
      PulseRunCase('pulse_sorted_lookup', Name, 'rtl', 'TStringList.Find', @CaseLookup, 8,
        Profile, SelectedCase, Found, @CaseLookup);
      Cleanup;
    end;
  PulseFinish('pulse_sorted_lookup', SelectedCase, Found);
end.
