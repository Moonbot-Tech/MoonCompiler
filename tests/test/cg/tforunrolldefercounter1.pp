{ %OPT=-O3 }
program tforunrolldefercounter1;

{$mode delphiunicode}
{$modeswitch autofree}
{$goto on}

uses
  SysUtils;

var
  Observed, HandlerObserved, Sink: Integer;

procedure RaiseAt(const Value: Integer); noinline;
begin
  if Value=2 then
    raise Exception.Create('loop counter observation');
end;

procedure Consume(const Value: Integer); noinline;
begin
  Inc(Sink,Value);
end;

procedure Probe(const Backward: Boolean);
var
  Index: Integer;
begin
  Index:=77;
  defer Observed:=Index;
  if Backward then
    for Index:=3 downto 1 do
      RaiseAt(Index)
  else
    for Index:=1 to 3 do
      RaiseAt(Index);
end;

procedure ProbeUnrelatedDefer;
var
  Index, Other: Integer;
begin
  Other:=91;
  defer Observed:=Other;
  for Index:=1 to 3 do
    Consume(Index);
end;

procedure ProbeLateDefer;
var
  Index: Integer;
begin
  Index:=77;
  try
    for Index:=1 to 3 do
      RaiseAt(Index);
  except
    HandlerObserved:=Index;
  end;
  defer Observed:=99;
end;

procedure ProbeNestedScope;
var
  Index, Other: Integer;
begin
  Other:=37;
  begin
    defer Observed:=Other;
  end;
  for Index:=1 to 3 do
    Consume(Index);
end;

procedure ProbeConditionalDefer(const RegisterCleanup: Boolean);
var
  Index: Integer;
begin
  Index:=77;
  if RegisterCleanup then
    defer Observed:=Index;
  for Index:=1 to 3 do
    RaiseAt(Index);
end;

procedure ProbeBackwardRegistration;
label
  RunLoop, RegisterCleanup;
var
  Index: Integer;
begin
  Index:=77;
  goto RegisterCleanup;
RunLoop:
  for Index:=1 to 3 do
    RaiseAt(Index);
  Exit;
RegisterCleanup:
  defer Observed:=Index;
  goto RunLoop;
end;

begin
  Observed:=-1;
  try
    Probe(False);
  except
  end;
  if Observed<>2 then
    Halt(1);

  Observed:=-1;
  try
    Probe(True);
  except
  end;
  if Observed<>2 then
    Halt(2);

  Sink:=0;
  Observed:=-1;
  ProbeUnrelatedDefer;
  if (Observed<>91) or (Sink<>6) then
    Halt(3);

  Observed:=-1;
  HandlerObserved:=-1;
  ProbeLateDefer;
  if (HandlerObserved<>2) or (Observed<>99) then
    Halt(4);

  Sink:=0;
  Observed:=-1;
  ProbeNestedScope;
  if (Observed<>37) or (Sink<>6) then
    Halt(5);

  Observed:=-1;
  try
    ProbeConditionalDefer(True);
  except
  end;
  if Observed<>2 then
    Halt(6);

  Observed:=-1;
  try
    ProbeConditionalDefer(False);
  except
  end;
  if Observed<>-1 then
    Halt(7);

  Observed:=-1;
  try
    ProbeBackwardRegistration;
  except
  end;
  if Observed<>2 then
    Halt(8);
end.
