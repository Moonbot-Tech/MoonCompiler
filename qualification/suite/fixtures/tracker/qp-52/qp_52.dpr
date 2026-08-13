program tracker_qp_52;

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
  TOwner<T> = class
  public type
    TResult = record Value: T; end;
    TEnvelope = record Item: TResult; end;
    TFactory = reference to function: TEnvelope;
    class function SafeCall(const Factory: TFactory): TEnvelope; static;
  end;
class function TOwner<T>.SafeCall(const Factory: TFactory): TEnvelope;
begin Result := Factory(); end;

procedure Run;
begin
var Value := TOwner<Integer>.SafeCall(
    function: TOwner<Integer>.TEnvelope
    begin Result := Default(TOwner<Integer>.TEnvelope); Result.Item.Value := 73; end);
  Check(Value.Item.Value = 73, 'nested-default-callback');
end;

begin
  try
    Run;
    WriteLn('PASS QP-52');
  except
    on E: Exception do
    begin
      WriteLn('FAIL QP-52: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
