program lightweight_mrew_semantic;

{$mode delphi}{$H+}

{ SyncObjs.TLightweightMREW: a zero-filled record is a ready lock, readers
  share, a writer excludes and waits for the readers, Try* never block, the
  timed forms (Linux) answer False when the time is up. }

uses
  SysUtils,
  Classes,
  SyncObjs;

var
  Failures: Integer;

procedure Check(Cond: Boolean; const Msg: string);
begin
  If not Cond then begin
    Inc(Failures);
    WriteLn('FAIL ', Msg);
  end;
end;

type
  TShared = record
    Lock: TLightweightMREW;     { zero by static allocation, never initialised }
    Value: Integer;
    InsideReaders: Integer;
    MaxInsideReaders: Integer;
    WriterInside: Integer;
    Torn: Integer;
  end;

var
  Shared: TShared;
  Go: Boolean;

type
  TReader = class(TThread)
  protected
    procedure Execute; override;
  end;

  TWriter = class(TThread)
  protected
    procedure Execute; override;
  end;

  THolder = class(TThread)
  public
    Acquired, Release: TEvent;
    Exclusive: Boolean;
  protected
    procedure Execute; override;
  end;

  {$IFDEF UNIX}
  TWriteProbe = class(TThread)
  public
    Acquired: Boolean;
  protected
    procedure Execute; override;
  end;
  {$ENDIF}

procedure TReader.Execute;
var
  I, N, A, B: Integer;
begin
  while not Go do
    Sleep(0);
  for I := 1 to 2000 do begin
    Shared.Lock.BeginRead;
    try
      N := InterlockedIncrement(Shared.InsideReaders);
      If N > Shared.MaxInsideReaders then
        Shared.MaxInsideReaders := N;             { racy max, only ever grows }
      If Shared.WriterInside <> 0 then
        InterlockedIncrement(Shared.Torn);
      A := Shared.Value;
      Sleep(0);
      B := Shared.Value;
      If A <> B then
        InterlockedIncrement(Shared.Torn);        { a writer changed it under a reader }
      InterlockedDecrement(Shared.InsideReaders);
    finally
      Shared.Lock.EndRead;
    end;
  end;
end;

procedure TWriter.Execute;
var
  I: Integer;
begin
  while not Go do
    Sleep(0);
  for I := 1 to 400 do begin
    Shared.Lock.BeginWrite;
    try
      If (Shared.InsideReaders <> 0) or (Shared.WriterInside <> 0) then
        InterlockedIncrement(Shared.Torn);
      InterlockedIncrement(Shared.WriterInside);
      Inc(Shared.Value);
      Sleep(0);
      Inc(Shared.Value);
      InterlockedDecrement(Shared.WriterInside);
    finally
      Shared.Lock.EndWrite;
    end;
  end;
end;

procedure THolder.Execute;
begin
  If Exclusive then
    Shared.Lock.BeginWrite
  else
    Shared.Lock.BeginRead;
  Acquired.SetEvent;
  Release.WaitFor(INFINITE);
  If Exclusive then
    Shared.Lock.EndWrite
  else
    Shared.Lock.EndRead;
end;

function StartHolder(Exclusive: Boolean): THolder;
begin
  Result := THolder.Create(True);
  Result.Exclusive := Exclusive;
  Result.Acquired := TEvent.Create(nil, True, False, '');
  Result.Release := TEvent.Create(nil, True, False, '');
  Result.Start;
  Result.Acquired.WaitFor(INFINITE);
end;

procedure StopHolder(H: THolder);
begin
  H.Release.SetEvent;
  H.WaitFor;
  H.Acquired.Free;
  H.Release.Free;
  H.Free;
end;

{$IFDEF UNIX}
procedure TWriteProbe.Execute;
begin
  Acquired := Shared.Lock.TryBeginWrite;
  If Acquired then
    Shared.Lock.EndWrite;
end;

procedure ZeroTimeoutAcquires(Exclusive, BesideReader: Boolean);
var
  Taken: Boolean;
  Probe: TWriteProbe;
  Holder: THolder;
  Name: string;
begin
  Holder := nil;
  If BesideReader then
    Holder := StartHolder(False);
  If Exclusive then begin
    Name := 'TryBeginWrite(0)';
    Taken := Shared.Lock.TryBeginWrite(0);
  end else begin
    Name := 'TryBeginRead(0)';
    Taken := Shared.Lock.TryBeginRead(0);
  end;
  If BesideReader then begin
    Name := Name + ' beside a reader';
    StopHolder(Holder);
  end;
  Check(Taken, Name + ' acquires');
  Probe := TWriteProbe.Create(False);
  Probe.WaitFor;
  Check(not Probe.Acquired, Name + ' holds the lock against a foreign writer');
  { Release only a real acquisition, including when the returned Boolean
    was wrong; never unlock a free lock in the negative control. }
  If not Probe.Acquired then begin
    If Exclusive then
      Shared.Lock.EndWrite
    else
      Shared.Lock.EndRead;
  end;
  Probe.Free;
end;
{$ENDIF}

procedure Concurrency;
var
  Readers: array[0..5] of TReader;
  Writers: array[0..1] of TWriter;
  I: Integer;
begin
  Go := False;
  for I := 0 to High(Readers) do
    Readers[I] := TReader.Create(False);
  for I := 0 to High(Writers) do
    Writers[I] := TWriter.Create(False);
  Go := True;
  for I := 0 to High(Readers) do begin
    Readers[I].WaitFor;
    Readers[I].Free;
  end;
  for I := 0 to High(Writers) do begin
    Writers[I].WaitFor;
    Writers[I].Free;
  end;
  Check(Shared.Torn = 0, 'readers and writers never overlap: ' + IntToStr(Shared.Torn));
  Check(Shared.Value = 2 * 400 * Length(Writers), 'every write counted: ' + IntToStr(Shared.Value));
  { sharing itself is proven deterministically in TryForms; the maximum seen
    here depends on scheduling and is only reported }
  WriteLn('readers inside at once (max): ', Shared.MaxInsideReaders);
end;

procedure TryForms;
var
  H: THolder;
  Local: TLightweightMREW;
begin
  { under a foreign writer nothing can be taken }
  H := StartHolder(True);
  try
    Check(not Shared.Lock.TryBeginRead, 'TryBeginRead under a writer');
    Check(not Shared.Lock.TryBeginWrite, 'TryBeginWrite under a writer');
    {$IFDEF UNIX}
    Check(not Shared.Lock.TryBeginWrite(50), 'TryBeginWrite(50) times out under a writer');
    Check(not Shared.Lock.TryBeginRead(50), 'TryBeginRead(50) times out under a writer');
    Check(not Shared.Lock.TryBeginWrite(0), 'TryBeginWrite(0) under a writer');
    Check(not Shared.Lock.TryBeginRead(0), 'TryBeginRead(0) under a writer');
    {$ENDIF}
  finally
    StopHolder(H);
  end;
  Check(Shared.Lock.TryBeginWrite, 'TryBeginWrite after the writer left');
  Shared.Lock.EndWrite;
  { under a foreign reader: more readers yes, a writer no }
  H := StartHolder(False);
  try
    Check(Shared.Lock.TryBeginRead, 'TryBeginRead beside a reader');
    Shared.Lock.EndRead;
    Check(not Shared.Lock.TryBeginWrite, 'TryBeginWrite beside a reader');
    {$IFDEF UNIX}
    Check(not Shared.Lock.TryBeginWrite(20), 'TryBeginWrite(20) times out beside a reader');
    Check(not Shared.Lock.TryBeginWrite(0), 'TryBeginWrite(0) beside a reader');
    Check(Shared.Lock.TryBeginRead(20), 'TryBeginRead(20) beside a reader');
    Shared.Lock.EndRead;
    Check(Shared.Lock.TryBeginRead(INFINITE), 'TryBeginRead(INFINITE) beside a reader');
    Shared.Lock.EndRead;
    {$ENDIF}
  finally
    StopHolder(H);
  end;
  Check(Shared.Lock.TryBeginWrite, 'TryBeginWrite after the reader left');
  { the writer itself asking again: the Try forms answer False, they do not
    raise (glibc reports the timed request of the owning thread as EDEADLK,
    not EBUSY) }
  Check(not Shared.Lock.TryBeginWrite, 'TryBeginWrite by the writer itself');
  Check(not Shared.Lock.TryBeginRead, 'TryBeginRead by the writer itself');
  {$IFDEF UNIX}
  try
    Check(not Shared.Lock.TryBeginWrite(0), 'TryBeginWrite(0) by the writer itself');
    Check(not Shared.Lock.TryBeginRead(0), 'TryBeginRead(0) by the writer itself');
    Check(not Shared.Lock.TryBeginWrite(20), 'TryBeginWrite(20) by the writer itself');
    Check(not Shared.Lock.TryBeginRead(20), 'TryBeginRead(20) by the writer itself');
  except
    on E: Exception do
      Check(False, 'timed Try by the writer itself raised ' + E.ClassName + ': ' + E.Message);
  end;
  {$ENDIF}
  Shared.Lock.EndWrite;
  { a shared lock may be taken again by the same thread }
  Shared.Lock.BeginRead;
  Check(Shared.Lock.TryBeginRead, 'recursive shared');
  Shared.Lock.EndRead;
  Shared.Lock.EndRead;
  { a zero-filled local is a ready lock, and nothing has to be finalised }
  Local := Default(TLightweightMREW);
  Check(Local.TryBeginWrite, 'Default() value is an unlocked lock');
  Local.EndWrite;
  Local.BeginRead;
  Local.EndRead;
  {$IFDEF UNIX}
  ZeroTimeoutAcquires(False, False);
  ZeroTimeoutAcquires(True, False);
  ZeroTimeoutAcquires(False, True);
  Check(Local.TryBeginWrite(INFINITE), 'TryBeginWrite(INFINITE) on a free lock');
  Local.EndWrite;
  {$ENDIF}
end;

begin
  Failures := 0;
  {$IFDEF MSWINDOWS}
  Check(SizeOf(TLightweightMREW) = SizeOf(Pointer), 'size of the SRW lock');
  {$ENDIF}
  {$IFDEF LINUX}
  Check(SizeOf(TLightweightMREW) = 56, 'size of pthread_rwlock_t: ' + IntToStr(SizeOf(TLightweightMREW)));
  {$ENDIF}
  Concurrency;
  TryForms;
  If Failures <> 0 then
    Halt(1);
  WriteLn('LIGHTWEIGHT_MREW_PASS');
end.
