program tracker_qp_26;

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
  TAnonymous = reference to procedure;
  TGenericOwner<T> = class
  private
    FCounter: PInteger;
    procedure Touch;
  public
    constructor Create(ACounter: PInteger);
    procedure Run;
  end;
procedure Invoke(const Callback: TAnonymous);
begin Callback(); end;
constructor TGenericOwner<T>.Create(ACounter: PInteger);
begin inherited Create; FCounter := ACounter; end;
procedure TGenericOwner<T>.Touch;
begin Inc(FCounter^); end;
procedure TGenericOwner<T>.Run;
begin
  Invoke(procedure begin Touch; end);
end;

procedure Run;
begin
var Counter := 0;
  var Owner := TGenericOwner<Integer>.Create(@Counter);
  try Owner.Run; finally Owner.Free; end;
  Check(Counter = 1, 'closure-only-reachability');
end;

begin
  try
    Run;
    WriteLn('PASS QP-26');
  except
    on E: Exception do
    begin
      WriteLn('FAIL QP-26: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
