program tracker_so_01;

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
  TBase = class
    procedure Setup(const Values: array of Integer); virtual;
  end;
  TChild = class(TBase)
    procedure Setup(const Values: array of Integer); override;
  end;
procedure TBase.Setup(const Values: array of Integer);
begin
  if Length(Values) = 0 then Check(High(Values) = -1, 'empty-high')
  else begin Check(High(Values) = Length(Values) - 1, 'high'); for var I := 0 to High(Values) do Check(Values[I] = I + 10, 'payload'); end;
end;
procedure TChild.Setup(const Values: array of Integer);
begin inherited; end;

procedure Run;
begin
var Child := TChild.Create;
  try Child.Setup([]); Child.Setup([10]); Child.Setup([10, 11, 12]); finally Child.Free; end;
end;

begin
  try
    Run;
    WriteLn('PASS SO-01');
  except
    on E: Exception do
    begin
      WriteLn('FAIL SO-01: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
