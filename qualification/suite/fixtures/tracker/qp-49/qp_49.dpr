program tracker_qp_49;

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
  ITracked = interface ['{525437FD-9E11-4F23-93AA-54A1753960D2}'] end;
  TTracked = class(TInterfacedObject, ITracked)
  public class var Alive: Integer; constructor Create; destructor Destroy; override; end;
constructor TTracked.Create; begin inherited; Inc(Alive); end;
destructor TTracked.Destroy; begin Dec(Alive); inherited; end;
procedure ExerciseInterfaces;
var Values: TArray<ITracked>;
begin
  SetLength(Values, 3);
  for var I := 0 to High(Values) do Values[I] := TTracked.Create;
  for var Value in Values do if Value = nil then Halt(2);
  Values := nil;
end;

procedure Run;
begin
ExerciseInterfaces;
  Check(TTracked.Alive = 0, 'post-loop-lifetime');
end;

begin
  try
    Run;
    WriteLn('PASS QP-49');
  except
    on E: Exception do
    begin
      WriteLn('FAIL QP-49: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
