program spin_overloads_semantic;

{$IFDEF FPC}
{$mode delphi}{$modeswitch anonymousfunctions}{$modeswitch functionreferences}
{$ELSE}
{$APPTYPE CONSOLE}
{$ENDIF}

uses
  SysUtils,
  SyncObjs,
  System.TimeSpan;

type
  {$IFDEF FPC}
  TCondition = TSpinFunction;
  {$ELSE}
  TCondition = TFunc<Boolean>;
  {$ENDIF}

var
  Failures: Integer;

procedure Check(Cond: Boolean; const Msg: string);
begin
  If not Cond then begin
    Inc(Failures);
    WriteLn('FAIL ', Msg);
  end;
end;

procedure LockOverload(UseSpan: Boolean; Timeout: Cardinal);
var
  Lock: TSpinLock;
  Taken: Boolean;
  Name: string;
begin
  Name := 'Cardinal';
  If UseSpan then
    Name := 'TimeSpan';
  Name := Name + '(' + IntToStr(Timeout) + ')';
  Lock := TSpinLock.Create(False);
  If UseSpan then
    Taken := Lock.TryEnter(TTimeSpan.FromMilliseconds(Timeout))
  else
    Taken := Lock.TryEnter(Timeout);
  Check(Taken, Name + ' acquires a free lock');
  Check(Lock.IsLocked, Name + ' really holds the lock');
  { If the timed call falsely reported success, this probe acquires the
    free lock itself; Exit below therefore always releases a real owner. }
  Check(not Lock.TryEnter, Name + ' excludes another acquisition');
  Lock.Exit;
  Check(not Lock.IsLocked, Name + ' releases');

  Lock.Enter;
  If UseSpan then
    Taken := Lock.TryEnter(TTimeSpan.FromMilliseconds(Timeout))
  else
    Taken := Lock.TryEnter(Timeout);
  Check(not Taken, Name + ' refuses an occupied lock');
  Check(Lock.IsLocked, Name + ' preserves the existing owner');
  Lock.Exit;
end;

function WaitForCondition(const Condition: TCondition; UseSpan: Boolean; Timeout: Cardinal): Boolean;
begin
  If UseSpan then
    Result := TSpinWait.SpinUntil(Condition, TTimeSpan.FromMilliseconds(Timeout))
  else
    Result := TSpinWait.SpinUntil(Condition, Timeout);
end;

procedure WaitOverload(UseSpan: Boolean);
var
  Calls: Integer;
  Taken: Boolean;
  Name: string;
begin
  Name := 'Cardinal';
  If UseSpan then
    Name := 'TimeSpan';
  Calls := 0;
  Taken := WaitForCondition(
    function: Boolean
    begin
      Inc(Calls);
      Result := True;
    end, UseSpan, 0);
  Check(Ord(Taken) = 1, Name + ' returns a true predicate');
  Check(Calls = 1, Name + ' evaluates an immediately true predicate once');

  Calls := 0;
  Taken := WaitForCondition(
    function: Boolean
    begin
      Inc(Calls);
      Result := False;
    end, UseSpan, 0);
  Check(Ord(Taken) = 0, Name + ' returns a false predicate');
  Check(Calls = 1, Name + ' zero timeout tries only once');

  Calls := 0;
  Taken := WaitForCondition(
    function: Boolean
    begin
      Inc(Calls);
      Result := Calls = 20;
    end, UseSpan, 1000);
  Check(Ord(Taken) = 1, Name + ' keeps waiting across a yield');
  Check(Calls = 20, Name + ' reaches the satisfied predicate');

  Taken := WaitForCondition(
    function: Boolean
    begin
      Result := False;
    end, UseSpan, 1);
  Check(Ord(Taken) = 0, Name + ' finite timeout expires');
end;

procedure WaitBoundaries;
var
  Calls, I: Integer;
  Taken, Raised: Boolean;
  Timeout: TTimeSpan;
begin
  Calls := 0;
  Taken := TSpinWait.SpinUntil(
    function: Boolean
    begin
      Inc(Calls);
      Result := Calls = 20;
    end, High(Cardinal));
  Check(Taken and (Calls = 20), 'INFINITE waits for the condition');
  Taken := TSpinWait.SpinUntil(function: Boolean begin Result := True; end, High(Cardinal) - 1);
  Check(Taken, 'Cardinal timeout accepts its full finite range');

  for I := 0 to 1 do begin
    If I = 0 then
      Timeout := TTimeSpan.FromMilliseconds(-1)
    else
      Timeout := TTimeSpan.FromMilliseconds(Int64(MaxInt) + 1);
    Calls := 0;
    Raised := False;
    try
      TSpinWait.SpinUntil(
        function: Boolean
        begin
          Inc(Calls);
          Result := True;
        end, Timeout);
    except
      on E: EArgumentOutOfRangeException do
        Raised := True;
    end;
    Check(Raised and (Calls = 0), 'invalid TimeSpan is rejected before the predicate');
  end;

  for I := -1 to 1 do begin
    Calls := 0;
    Taken := TSpinWait.SpinUntil(
      function: Boolean
      begin
        Inc(Calls);
        Result := False;
      end, TTimeSpan.FromTicks(I * 9000));
    Check((Ord(Taken) = 0) and (Calls = 1), 'fractional milliseconds truncate to zero');
  end;
  Taken := TSpinWait.SpinUntil(
    function: Boolean begin Result := True; end, TTimeSpan.FromMilliseconds(MaxInt));
  Check(Taken, 'TimeSpan accepts MaxInt milliseconds');
end;

var
  Calls: Integer;
begin
  LockOverload(False, 0);
  LockOverload(True, 0);
  LockOverload(False, 1);
  LockOverload(True, 1);
  WaitOverload(False);
  WaitOverload(True);
  WaitBoundaries;
  Calls := 0;
  TSpinWait.SpinUntil(
    function: Boolean
    begin
      Inc(Calls);
      Result := Calls = 20;
    end);
  Check(Calls = 20, 'untimed wait reaches the satisfied predicate');
  If Failures <> 0 then
    Halt(1);
  WriteLn('SPIN_OVERLOADS_PASS');
end.
