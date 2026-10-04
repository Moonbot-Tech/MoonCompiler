program method_class_receivers;
{$IFDEF MSWINDOWS}{$APPTYPE CONSOLE}{$ENDIF}
{$IFDEF FPC}{$mode objfpc}{$H+}{$modeswitch functionreferences}{$ENDIF}
{ A class method stored in an event or a function reference carries the
  selected class as Self, including an inherited method selected on a child.
  The FPC @ form attaches that receiver during procvar conversion. }
uses SysUtils;

type
  TMethodProc = procedure(Step: Integer) of object;
  TPlainProc = procedure(Step: Integer);
  TProcRef = reference to procedure(Step: Integer);
  TBase = class
    class procedure Step(A: Integer);
    class procedure VirtualStep(A: Integer); virtual;
    class procedure StaticStep(A: Integer); static;
    class procedure RaiseError(A: Integer);
    procedure InstanceStep(A: Integer);
  end;
  TChild = class(TBase)
    class procedure VirtualStep(A: Integer); override;
  end;
  TBaseClass = class of TBase;
  TLogger = class
    FEvent: TMethodProc;
    property OnEvent: TMethodProc read FEvent write FEvent;
  end;

var
  Logger: TLogger;
  Seen: Pointer;
  Total, Failures: Integer;

procedure Check(const Name: string; Ok: Boolean);
begin
  if not Ok then
  begin
    WriteLn('FAIL ', Name);
    Inc(Failures);
  end;
end;

class procedure TBase.Step(A: Integer);
begin
  Seen := Pointer(Self);
  Inc(Total, A);
end;

class procedure TBase.VirtualStep(A: Integer);
begin
  Seen := Pointer(Self);
  Inc(Total, A * 10);
end;

class procedure TChild.VirtualStep(A: Integer);
begin
  Seen := Pointer(Self);
  Inc(Total, A * 100);
end;

class procedure TBase.StaticStep(A: Integer);
begin
  Inc(Total, A * 1000);
end;

class procedure TBase.RaiseError(A: Integer);
begin
  Step(A);
  raise Exception.Create('callback exception');
end;

procedure TBase.InstanceStep(A: Integer);
begin
  Seen := Pointer(Self);
  Inc(Total, A);
end;

function GetLogger: TLogger; inline;
begin
  Result := Logger;
end;

procedure CheckMethod(const Name: string; M: TMethodProc; Data: Pointer; Amount: Integer);
var
  Before: Integer;
begin
  Check(Name + '-data', TMethod(M).Data = Data);
  Before := Total;
  Seen := nil;
  M(2);
  Check(Name + '-call', (Seen = Data) and (Total = Before + Amount));
end;

procedure Run;
var
  M: TMethodProc;
  C: TBaseClass;
  Obj: TBase;
  P: TPlainProc;
  R: TProcRef;
  Before: Integer;
begin
  GetLogger.OnEvent := {$IFDEF FPC}@{$ENDIF}TBase.Step;
  CheckMethod('class-event', Logger.OnEvent, Pointer(TBase), 2);
  M := {$IFDEF FPC}@{$ENDIF}TChild.Step;
  CheckMethod('inherited-class', M, Pointer(TChild), 2);
  C := TChild;
  M := {$IFDEF FPC}@{$ENDIF}C.Step;
  CheckMethod('class-reference', M, Pointer(TChild), 2);
  M := {$IFDEF FPC}@{$ENDIF}C.VirtualStep;
  CheckMethod('virtual-class', M, Pointer(TChild), 200);
  C := nil;
  M := {$IFDEF FPC}@{$ENDIF}C.Step;
  CheckMethod('nil-class-reference', M, nil, 2);

  Obj := TChild.Create;
  try
    M := {$IFDEF FPC}@{$ENDIF}Obj.Step;
    CheckMethod('instance-class', M, Pointer(TChild), 2);
    M := {$IFDEF FPC}@{$ENDIF}Obj.VirtualStep;
    CheckMethod('instance-virtual-class', M, Pointer(TChild), 200);
    M := {$IFDEF FPC}@{$ENDIF}Obj.InstanceStep;
    CheckMethod('instance-method', M, Pointer(Obj), 2);
  finally
    Obj.Free;
  end;

  P := {$IFDEF FPC}@{$ENDIF}TBase.StaticStep;
  Before := Total;
  P(2);
  Check('static-method', Total = Before + 2000);
  R := {$IFDEF FPC}@{$ENDIF}TChild.Step;
  Before := Total;
  R(3);
  Check('function-reference', (Seen = Pointer(TChild)) and (Total = Before + 3));

  M := {$IFDEF FPC}@{$ENDIF}TChild.RaiseError;
  Before := Total;
  try
    M(5);
    Check('exception-missing', False);
  except
    on E: Exception do
      Check('exception', (E.Message = 'callback exception') and
        (Seen = Pointer(TChild)) and (Total = Before + 5));
  end;
  M := {$IFDEF FPC}@{$ENDIF}TBase.Step;
  CheckMethod('return-after-reassignment', M, Pointer(TBase), 2);
end;

begin
  Logger := TLogger.Create;
  try
    Run;
  finally
    Logger.Free;
  end;
  if Failures <> 0 then Halt(1);
  WriteLn('METHOD_CLASS_RECEIVERS_OK');
end.
