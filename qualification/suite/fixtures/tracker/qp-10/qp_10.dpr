program tracker_qp_10;

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

var
  CmrInit, CmrFini, CmrCopy: Integer;

type
  TWreckingBall = record
    Marker: Integer;
    class operator Initialize({$ifdef FPC}var{$else}out{$endif} Dest: TWreckingBall);
    class operator Finalize(var Dest: TWreckingBall);
{$ifdef FPC}
    class operator Copy(constref Source: TWreckingBall; var Dest: TWreckingBall);
{$else}
    class operator Assign(var Dest: TWreckingBall; const [ref] Source: TWreckingBall);
{$endif}
  end;
  TResultRec = record
    Text: string;
    Marker: Integer;
  end;

class operator TWreckingBall.Initialize({$ifdef FPC}var{$else}out{$endif} Dest: TWreckingBall);
begin Dest.Marker := 7; Inc(CmrInit); end;
class operator TWreckingBall.Finalize(var Dest: TWreckingBall);
begin Inc(CmrFini); end;
{$ifdef FPC}
class operator TWreckingBall.Copy(constref Source: TWreckingBall; var Dest: TWreckingBall);
{$else}
class operator TWreckingBall.Assign(var Dest: TWreckingBall; const [ref] Source: TWreckingBall);
{$endif}
begin Dest.Marker := Source.Marker; Inc(CmrCopy); end;

procedure ApplyWreckingBall(const Value: TWreckingBall);
begin Check(Value.Marker = 7, 'cmr-parameter'); end;

function MakeResult: TResultRec;
begin Result.Text := 'managed-result'; Result.Marker := 42; end;

procedure Consume(const Value: TResultRec);
begin Check((Value.Text = 'managed-result') and (Value.Marker = 42), 'result-temp'); end;

procedure Run;
begin
var W: TWreckingBall;
  ApplyWreckingBall(W);
  Consume(MakeResult);
  Check(CmrInit >= 1, 'init');
end;

begin
  try
    Run;
    WriteLn('PASS QP-10');
  except
    on E: Exception do
    begin
      WriteLn('FAIL QP-10: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
