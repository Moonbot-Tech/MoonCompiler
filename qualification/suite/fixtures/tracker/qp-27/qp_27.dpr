program tracker_qp_27;

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

type EOuter = class(Exception); EInner = class(Exception);
procedure RaiseNested;
begin
  try
    raise EOuter.Create('outer');
  except
    on E: EOuter do
    begin
      try
        raise EInner.Create(E.Message + ':inner');
      except
        on E: EInner do raise;
      end;
    end;
  end;
end;

procedure Run;
begin
for var I := 1 to 256 do
  begin
    try
      RaiseNested;
      Check(False, 'not-raised');
    except
      on E: EInner do Check(E.Message = 'outer:inner', 'message');
    end;
    Check(ExceptObject = nil, 'exception-state');
  end;
end;

begin
  try
    Run;
    WriteLn('PASS QP-27');
  except
    on E: Exception do
    begin
      WriteLn('FAIL QP-27: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
