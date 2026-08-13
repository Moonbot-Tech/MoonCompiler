program tracker_qp_34;

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
  IValue = interface
    ['{086EE2D6-8D6B-4EEC-AED2-69B3285C4105}']
    procedure SetValue(const Value: Double);
    function GetValue: Double;
  end;
  TDelegate = class(TInterfacedObject, IValue)
  private FValue: Double;
  public procedure SetValue(const Value: Double); function GetValue: Double; end;
  TProxy = class(TInterfacedObject, IValue)
  private
    FDelegate: TDelegate;
    function GetDelegate: TDelegate;
  public
    destructor Destroy; override;
    property Delegate: TDelegate read GetDelegate implements IValue;
  end;
procedure TDelegate.SetValue(const Value: Double); begin FValue := Value; end;
function TDelegate.GetValue: Double; begin Result := FValue; end;
function Clobber(A, B, C, D: NativeInt): NativeInt;
begin Result := A xor B xor C xor D; end;
function TProxy.GetDelegate: TDelegate;
begin
  if Clobber(11,22,33,44) = -1 then raise Exception.Create('unreachable');
  if FDelegate = nil then FDelegate := TDelegate.Create;
  Result := FDelegate;
end;
destructor TProxy.Destroy;
begin FDelegate.Free; inherited; end;

procedure Run;
begin
var Value: IValue := TProxy.Create;
  Value.SetValue(3.1415);
  Check(Abs(Value.GetValue - 3.1415) < 1e-15, 'double-abi');
  Value := nil;
end;

begin
  try
    Run;
    WriteLn('PASS QP-34');
  except
    on E: Exception do
    begin
      WriteLn('FAIL QP-34: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
