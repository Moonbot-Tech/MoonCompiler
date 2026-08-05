{ %OPT=-O2 }
program tdelphiexceptionreplace1;

{$ifdef FPC}
  {$mode delphi}
{$endif}

uses
  SysUtils;

type
  ETracked = class(Exception)
  private
    FKind: Integer;
  public
    class var Destroyed: array[1..3] of Integer;
    constructor CreateKind(AKind: Integer);
    destructor Destroy; override;
  end;

  EVictim = class(ETracked);
  EUsurper = class(ETracked);
  EInner = class(ETracked);

constructor ETracked.CreateKind(AKind: Integer);
begin
  inherited Create('tracked');
  FKind := AKind;
end;

destructor ETracked.Destroy;
begin
  Inc(Destroyed[FKind]);
  inherited Destroy;
end;

procedure Check(ACondition: Boolean; ACode: Integer);
begin
  If not ACondition then begin
    WriteLn('FAIL ', ACode, ' destroyed=', ETracked.Destroyed[1], ',',
      ETracked.Destroyed[2], ',', ETracked.Destroyed[3]);
    Halt(ACode);
  end;
end;

procedure RaiseUsurperThroughFrame;
begin
  try
    raise EUsurper.CreateKind(2);
  finally
    { Force propagation through another exception frame. }
  end;
end;

procedure CatchInnerThroughFrame;
begin
  try
    raise EInner.CreateKind(3);
  except
    on EInner do
      ;
  end;
end;

procedure TestDirectReplacement;
begin
  try
    try
      raise EVictim.CreateKind(1);
    finally
      raise EUsurper.CreateKind(2);
    end;
  except
    on EUsurper do
      ;
  end;
  Check(ETracked.Destroyed[1] = 1, 10);
  Check(ETracked.Destroyed[2] = 1, 11);
end;

procedure TestReplacementThroughCall;
begin
  try
    try
      raise EVictim.CreateKind(1);
    finally
      RaiseUsurperThroughFrame;
    end;
  except
    on EUsurper do
      ;
  end;
  Check(ETracked.Destroyed[1] = 2, 20);
  Check(ETracked.Destroyed[2] = 2, 21);
end;

procedure TestCaughtInnerException;
begin
  try
    try
      raise EVictim.CreateKind(1);
    finally
      try
        raise EInner.CreateKind(3);
      except
        on EInner do
          ;
      end;
    end;
  except
    on EVictim do
      ;
  end;
  Check(ETracked.Destroyed[1] = 3, 30);
  Check(ETracked.Destroyed[3] = 1, 31);
end;

procedure TestNestedExceptReplacement;
begin
  try
    try
      raise EVictim.CreateKind(1);
    except
      raise EUsurper.CreateKind(2);
    end;
  except
    on EUsurper do
      ;
  end;
  Check(ETracked.Destroyed[1] = 4, 40);
  Check(ETracked.Destroyed[2] = 3, 41);
end;

procedure TestNormalFinallyRaise;
begin
  try
    try
      { normal try path }
    finally
      raise EUsurper.CreateKind(2);
    end;
  except
    on EUsurper do
      ;
  end;
  Check(ETracked.Destroyed[2] = 4, 50);
end;

procedure TestCaughtInnerThroughCall;
begin
  try
    try
      raise EVictim.CreateKind(1);
    finally
      CatchInnerThroughFrame;
    end;
  except
    on EVictim do
      ;
  end;
  Check(ETracked.Destroyed[1] = 5, 60);
  Check(ETracked.Destroyed[3] = 2, 61);
end;

procedure TestCaughtSameTypeInsideFinally;
begin
  try
    try
      raise EVictim.CreateKind(1);
    finally
      try
        raise EVictim.CreateKind(1);
      except
        on EVictim do
          ;
      end;
    end;
  except
    on EVictim do
      ;
  end;
  Check(ETracked.Destroyed[1] = 7, 70);
end;

procedure TestCaughtByCatchAllInsideFinally;
begin
  try
    try
      raise EVictim.CreateKind(1);
    finally
      try
        raise EInner.CreateKind(3);
      except
        ;
      end;
    end;
  except
    on EVictim do
      ;
  end;
  Check(ETracked.Destroyed[1] = 8, 80);
  Check(ETracked.Destroyed[3] = 3, 81);
end;

begin
  TestDirectReplacement;
  TestReplacementThroughCall;
  TestCaughtInnerException;
  TestNestedExceptReplacement;
  TestNormalFinallyRaise;
  TestCaughtInnerThroughCall;
  TestCaughtSameTypeInsideFinally;
  TestCaughtByCatchAllInsideFinally;
  WriteLn('OK');
end.
