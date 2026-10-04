{ %OPT=-O3 -OoAUTOINLINE }
program tmoontinyfinally1;

{$mode delphiunicode}
{$Q-}{$R-}

uses SysUtils, umoontinyfinally1;

type
  TState = class
    Value: NativeInt;
    Active: Boolean;
    procedure Change(NewValue: NativeInt; Fail: Boolean);
  end;

var
  Visits, OuterVisits: Integer;

procedure Require(Condition: Boolean; Code: Integer);
begin
  if not Condition then
    Halt(Code);
end;

procedure TState.Change(NewValue: NativeInt; Fail: Boolean);
var
  Saved: NativeInt;
  WasActive: Boolean;
begin
  Saved := Value;
  WasActive := Active;
  Value := NewValue;
  Active := True;
  try
    if Fail then
      raise Exception.Create('body');
    Inc(Visits);
  finally
    Value := Saved;
    Active := WasActive;
  end;
end;

function ExitPath(Value: Integer): Integer;
begin
  try
    Result := Value;
    if Value <> 0 then
      Exit;
    Result := 17;
  finally
    Inc(Visits);
  end;
  Inc(Result);
end;

procedure FaultInCleanup(BodyRaises: Boolean);
var
  P: PInteger;
begin
  P := nil;
  try
    try
      if BodyRaises then
        raise Exception.Create('replaced');
    finally
      Inc(Visits);
      P^ := 1;
    end;
  except
    on E: EAccessViolation do
      Inc(OuterVisits);
  end;
end;

procedure NestedUnwind;
begin
  try
    try
      try
        raise Exception.Create('nested');
      finally
        Inc(Visits);
      end;
    finally
      Inc(OuterVisits);
    end;
  except
    on E: Exception do
      Require(E.Message = 'nested', 10);
  end;
end;

procedure LoopEscapes;
var
  I, Sum: Integer;
begin
  Sum := 0;
  for I := 1 to 10 do
    try
      if I = 3 then
        Continue;
      if I = 7 then
        Break;
      Inc(Sum, I);
    finally
      Inc(Visits);
    end;
  Require(Sum = 18, 11);
end;

procedure WriteThroughVar(var Value: Integer);
begin
  try
    Value := 7;
  finally
    Inc(Visits);
  end;
end;

procedure CheckedBody;
var
  Value: Integer;
begin
  Value := High(Integer);
  try
    try
      {$Q+}
      Value := Value + 1;
    finally
      {$Q-}
      Inc(Visits);
    end;
    Halt(13);
  except
    on E: EIntOverflow do
      Inc(OuterVisits);
  end;
end;

var
  State: TState;
  I, V: Integer;
  P: PInteger;
begin
  State := TState.Create;
  try
    State.Value := 123;
    State.Active := False;
    State.Change(999, False);
    Require((State.Value = 123) and not State.Active and (Visits = 1), 1);
    try
      State.Change(888, True);
      Halt(2);
    except
      on E: Exception do
        Require(E.Message = 'body', 3);
    end;
    Require((State.Value = 123) and not State.Active and (Visits = 1), 4);
  finally
    State.Free;
  end;
  Require(ExitPath(42) = 42, 5);
  Require(ExitPath(0) = 18, 6);
  FaultInCleanup(False);
  FaultInCleanup(True);
  Require((Visits = 5) and (OuterVisits = 2), 7);
  NestedUnwind;
  Require((Visits = 6) and (OuterVisits = 3), 8);
  LoopEscapes;
  Require(Visits = 13, 9);
  V := 0;
  for I := 1 to 10 do
    Inc(V, InlineCleanup(I, Visits));
  Require((V = 110) and (Visits = 23), 12);
  P := nil;
  try
    WriteThroughVar(P^);
    Halt(14);
  except
    on E: EAccessViolation do
      Inc(OuterVisits);
  end;
  CheckedBody;
  Require((Visits = 25) and (OuterVisits = 5), 15);
  WriteLn('tiny finally ok');
end.
