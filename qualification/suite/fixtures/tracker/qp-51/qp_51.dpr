program tracker_qp_51;

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
  TObjectAction = reference to procedure(Value: TObject);
  TPlainAction = reference to procedure;
  TMarkerObject = class
  public Marker: Integer; constructor Create(AMarker: Integer); end;
constructor TMarkerObject.Create(AMarker: Integer); begin inherited Create; Marker := AMarker; end;
function Pick(Value: TObject): Integer; overload; begin Result := TMarkerObject(Value).Marker; Value.Free; end;
function Pick(const Value: TPlainAction): Integer; overload; begin Value(); Result := -1; end;

procedure Run;
begin
Check(Pick(TMarkerObject.Create(73)) = 73, 'constructor-expression');
end;

begin
  try
    Run;
    WriteLn('PASS QP-51');
  except
    on E: Exception do
    begin
      WriteLn('FAIL QP-51: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
