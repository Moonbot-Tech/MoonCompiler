program tracker_qp_01;

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch anonymousfunctions}
  {$modeswitch functionreferences}
  {$modeswitch nestedprocvars}
  {$modeswitch inlinevars}
{$endif}
{$APPTYPE CONSOLE}
{$Q-}{$R-}

uses
  SysUtils, Classes, Math, Variants, TypInfo, Rtti,
  Generics.Defaults, Generics.Collections;

procedure Check(Condition: Boolean; const Name: string);
begin
  if not Condition then
    raise Exception.Create(Name);
end;

type
  TBox<T> = class
  public type
    TCallback = procedure;
  public
    class procedure Invoke(Callback: TCallback = nil); static;
  end;

var
  CallbackCalls: Integer;

procedure MarkCalled;
begin
  Inc(CallbackCalls);
end;

class procedure TBox<T>.Invoke(Callback: TCallback);
begin
  Check(not Assigned(Callback) or (PPointer(@Callback)^ <> nil), 'partial-nil');
  if Assigned(Callback) then
    Callback;
end;

procedure Run;
begin
CallbackCalls := 0;
  TBox<Integer>.Invoke;
  TBox<Integer>.Invoke(nil);
  TBox<Integer>.Invoke(MarkCalled);
  Check(CallbackCalls = 1, 'callback-count');
end;

begin
  try
    Run;
    WriteLn('PASS QP-01');
  except
    on E: Exception do
    begin
      WriteLn('FAIL QP-01: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
