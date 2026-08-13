program tracker_so_08;

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
  TKind = (kOne, kTwo);
  TKindHelper = record helper for TKind
    function GetIsTwo: Boolean; inline;
    property IsTwo: Boolean read GetIsTwo;
  end;
  THolder = class private FKind: TKind; function GetKind: TKind; public constructor Create(AKind: TKind); function IsTwo: Boolean; inline; end;
function TKindHelper.GetIsTwo: Boolean; begin Result := Self = kTwo; end;
constructor THolder.Create(AKind: TKind); begin inherited Create; FKind := AKind; end;
function THolder.GetKind: TKind; begin Result := FKind; end;
function THolder.IsTwo: Boolean; begin Result := GetKind.IsTwo; end;

procedure Run;
begin
var A := THolder.Create(kOne); var B := THolder.Create(kTwo);
  try Check(not A.IsTwo, 'one'); Check(B.IsTwo, 'two'); finally A.Free; B.Free; end;
end;

begin
  try
    Run;
    WriteLn('PASS SO-08');
  except
    on E: Exception do
    begin
      WriteLn('FAIL SO-08: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
