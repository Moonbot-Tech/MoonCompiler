program loop_counter_observability_semantic;

{$ifdef FPC}
  {$mode delphi}{$H+}
  {$modeswitch inlinevars}
  {$modeswitch anonymousfunctions}
  {$modeswitch functionreferences}
{$endif}

uses
{$ifdef FPC}
  SysUtils;
{$else}
  System.SysUtils;
{$endif}

type
  TIntFunc = reference to function: Integer;

var
  GlobalCounter: Integer;
  GlobalTrail: Integer;

procedure ObserveGlobal; {$ifdef FPC}noinline;{$endif}
begin
  GlobalTrail:=GlobalTrail*10+GlobalCounter;
end;

procedure RaiseAt(const Value, Trigger: Integer); {$ifdef FPC}noinline;{$endif}
begin
  if Value=Trigger then
    raise Exception.Create('loop counter observation');
end;

function ObserveInHandler(const Backward: Boolean): Integer;
var
  Index: Integer;
begin
  Index:=77;
  Result:=-1;
  try
    if Backward then
      for Index:=3 downto 1 do
        RaiseAt(Index,2)
    else
      for Index:=1 to 3 do
        RaiseAt(Index,2);
  except
    Result:=Index;
  end;
end;

function ObserveInFinally: Integer;
var
  Index: Integer;
begin
  Index:=77;
  Result:=-1;
  try
    try
      for Index:=1 to 3 do
        RaiseAt(Index,2);
    finally
      Result:=Index;
    end;
  except
    { The finalizer result is the observation under test. }
  end;
end;

function CapturedClassic: Integer;
var
  Index: Integer;
  Steps: array[1..3] of TIntFunc;
begin
  for Index:=1 to 3 do
    Steps[Index]:=function: Integer
      begin
        Result:=Index;
      end;
  Result:=Steps[1]()*100+Steps[3]();
end;

function CapturedInline: Integer;
var
  Steps: array[1..3] of TIntFunc;
begin
  for var Index:=1 to 3 do
    Steps[Index]:=function: Integer
      begin
        Result:=Index;
      end;
  Result:=Steps[1]()*100+Steps[3]();
end;

begin
  { Delphi captures the loop variable itself, not a per-iteration copy.  The
    terminating increment leaves 4 in the captured storage. }
  if CapturedClassic<>404 then
    Halt(1);
  if CapturedInline<>404 then
    Halt(2);

  GlobalTrail:=0;
  for GlobalCounter:=1 to 3 do
    ObserveGlobal;
  if GlobalTrail<>123 then
    Halt(3);

  if ObserveInHandler(False)<>2 then
    Halt(4);
  if ObserveInHandler(True)<>2 then
    Halt(5);
  if ObserveInFinally<>2 then
    Halt(6);

  WriteLn('LOOP_COUNTER_OBSERVABILITY_PASS');
end.
