program anonymous_exception_capture_matrix;

{$IFDEF FPC}
{$mode delphi}
{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}
{$ENDIF}

uses
{$IFDEF FPC}
  SysUtils;
{$ELSE}
  System.SysUtils;
{$ENDIF}

type
  TProc = reference to procedure;
  TProc2 = reference to procedure;

  TCountingException = class(Exception)
  public
    destructor Destroy; override;
  end;

var
  DestroyCount: Integer;

destructor TCountingException.Destroy;
begin
  Inc(DestroyCount);
  inherited Destroy;
end;

procedure Check(ACondition: Boolean; const AName: string);
begin
  If not ACondition then begin
    WriteLn('FAIL ', AName);
    Halt(1);
  end;
end;

procedure Invoke(const AProc: TProc); inline;
begin
  AProc;
end;

procedure InvokeCast(const AProc: TProc); inline;
begin
  TProc2(AProc)();
end;

function HasProc(const AProc: TProc): Boolean; inline;
begin
  Result := Assigned(AProc);
end;

procedure CopyProc(const AProc: TProc; var ADest: TProc); inline;
begin
  ADest := AProc;
end;

procedure CheckOrdinaryLocalAndException;
var
  LocalValue: Integer;
  Seen: string;
begin
  LocalValue := 17;
  try
    raise Exception.Create('outer');
  except
    on E: Exception do
      Invoke(
        procedure
        begin
          Seen := E.Message + ':' + IntToStr(LocalValue);
        end);
  end;
  Check(Seen = 'outer:17', 'ordinary-local-and-exception');
end;

procedure CheckNestedAndShadowedExceptions;
var
  OuterProc,
  InnerProc: TProc;
  OuterSeen,
  InnerSeen: string;
begin
  try
    raise Exception.Create('outer');
  except
    on E: Exception do begin
      OuterProc :=
        procedure
        begin
          OuterSeen := E.Message;
        end;
      try
        raise Exception.Create('inner');
      except
        on E: Exception do begin
          InnerProc :=
            procedure
            begin
              InnerSeen := E.Message;
            end;
          OuterProc;
          InnerProc;
        end;
      end;
    end;
  end;
  Check(OuterSeen = 'outer', 'shadowed-outer');
  Check(InnerSeen = 'inner', 'shadowed-inner');
end;

procedure CheckSharedExceptionSlot;
var
  FirstProc,
  SecondProc: TProc;
  FirstSeen,
  SecondSeen: string;
begin
  try
    raise Exception.Create('shared');
  except
    on E: Exception do begin
      FirstProc :=
        procedure
        begin
          FirstSeen := E.Message;
        end;
      SecondProc :=
        procedure
        begin
          SecondSeen := E.Message;
        end;
      FirstProc;
      SecondProc;
    end;
  end;
  Check(FirstSeen = 'shared', 'shared-first');
  Check(SecondSeen = 'shared', 'shared-second');
end;

procedure CheckEscapedLifetime;
var
  Escaped: TProc;
begin
  DestroyCount := 0;
  try
    raise TCountingException.Create('lifetime');
  except
    on E: TCountingException do
      Escaped :=
        procedure
        begin
          If E = nil then
            Halt(2);
        end;
  end;
  Check(DestroyCount = 1, 'destroy-at-handler-exit');
  Check(Assigned(Escaped), 'escaped-created');
  Escaped := nil;
  Check(DestroyCount = 1, 'closure-does-not-own-exception');
end;

procedure CheckExceptionVariableMutation;
var
  Captured: TProc;
  Seen: string;
begin
  DestroyCount := 0;
  try
    raise TCountingException.Create('before');
  except
    on E: TCountingException do begin
      Captured :=
        procedure
        begin
          If E = nil then
            Seen := 'nil'
          else
            Seen := E.Message;
        end;
      E := nil;
      Captured;
    end;
  end;
  Check(Seen = 'nil', 'exception-variable-is-captured-by-reference');
  Check(DestroyCount = 1, 'mutated-exception-still-destroyed-once');
end;

procedure CheckBareReraise;
var
  Captured: TProc;
  Seen: string;
begin
  try
    try
      raise Exception.Create('reraised');
    except
      on E: Exception do begin
        Captured :=
          procedure
          begin
            Seen := E.Message;
          end;
        Captured;
        raise;
      end;
    end;
  except
    on E: Exception do
      Check((E.Message = 'reraised') and (Seen = 'reraised'), 'bare-reraise');
  end;
end;

procedure CheckMaterializedAndDirect;
var
  Materialized,
  CopyOfMaterialized: TProc;
  Count: Integer;
begin
  Count := 0;
  Materialized :=
    procedure
    begin
      Inc(Count);
    end;
  Invoke(Materialized);
  Invoke(
    procedure
    begin
      Inc(Count, 2);
    end);
  InvokeCast(Materialized);
  Check(HasProc(Materialized), 'non-invoking-assigned-wrapper');
  CopyProc(Materialized, CopyOfMaterialized);
  Check(Assigned(CopyOfMaterialized), 'non-invoking-copy-wrapper');
  Check(Count = 4, 'materialized-direct-and-cast');
end;

begin
  CheckOrdinaryLocalAndException;
  CheckNestedAndShadowedExceptions;
  CheckSharedExceptionSlot;
  CheckEscapedLifetime;
  CheckExceptionVariableMutation;
  CheckBareReraise;
  CheckMaterializedAndDirect;
  WriteLn('EXCEPTION_CAPTURE_MATRIX_OK');
end.
