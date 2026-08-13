program tracker_qp_04;

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

procedure RaiseAndReplace;
begin
  try
    raise EArgumentException.Create('inner');
  except
    on E: EArgumentException do
    begin
      var MessageCopy := E.Message;
      raise Exception.Create(MessageCopy + ':replacement');
    end;
  end;
end;

procedure Run;
begin
for var I := 1 to 128 do
  begin
    try
      RaiseAndReplace;
      Check(False, 'not-raised');
    except
      on E: Exception do
        Check(E.Message = 'inner:replacement', 'replacement-message');
    end;
    Check(ExceptObject = nil, 'exception-frame-not-cleared');
  end;
end;

begin
  try
    Run;
    WriteLn('PASS QP-04');
  except
    on E: Exception do
    begin
      WriteLn('FAIL QP-04: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
