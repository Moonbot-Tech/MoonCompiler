program tracker_so_02;

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

function ProcessNumber(Value: Integer): Boolean; inline;
begin Result := False; if Value = 0 then Exit; Result := True; end;
procedure Sink(Value: Boolean; Expected: Boolean);
begin Check(Value = Expected, 'sink'); end;

procedure Run;
begin
Sink(ProcessNumber(0), False); Sink(ProcessNumber(1), True);
end;

begin
  try
    Run;
    WriteLn('PASS SO-02');
  except
    on E: Exception do
    begin
      WriteLn('FAIL SO-02: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
