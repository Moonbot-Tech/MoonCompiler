program tracker_qp_50;

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
  TKey = class
  public Value: Integer; class var DestroyedA, DestroyedB: Integer; constructor Create(AValue: Integer); destructor Destroy; override; end;
  TKeyComparer = class(TInterfacedObject, IEqualityComparer<TKey>)
    function Equals(const Left, Right: TKey): Boolean;
    {$ifdef FPC}
    function GetHashCode(const Value: TKey): Cardinal;
    {$else}
    function GetHashCode(const Value: TKey): Integer;
    {$endif}
  end;
constructor TKey.Create(AValue: Integer); begin inherited Create; Value := AValue; end;
destructor TKey.Destroy; begin if Self.Value = 101 then Inc(DestroyedA) else Inc(DestroyedB); inherited; end;
function TKeyComparer.Equals(const Left, Right: TKey): Boolean; begin Result := Left.Value mod 100 = Right.Value mod 100; end;
{$ifdef FPC}
function TKeyComparer.GetHashCode(const Value: TKey): Cardinal;
{$else}
function TKeyComparer.GetHashCode(const Value: TKey): Integer;
{$endif}
begin Result := Value.Value mod 100; end;

procedure Run;
begin
TKey.DestroyedA := 0; TKey.DestroyedB := 0;
  var Dictionary := TObjectDictionary<TKey,Integer>.Create([doOwnsKeys], TKeyComparer.Create);
  var Stored := TKey.Create(101); var Probe := TKey.Create(201);
  Dictionary.Add(Stored, 7);
  Dictionary.Remove(Probe);
  Check(not Dictionary.ContainsKey(Probe), 'remove');
  Check((TKey.DestroyedA = 1) and (TKey.DestroyedB = 0), 'stored-key-destroyed');
  Probe.Free; Dictionary.Free;
  Check((TKey.DestroyedA = 1) and (TKey.DestroyedB = 1), 'probe-caller-owned');
end;

begin
  try
    Run;
    WriteLn('PASS QP-50');
  except
    on E: Exception do
    begin
      WriteLn('FAIL QP-50: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
