{ %OPT=-O2 }
program tdelphiinterfacefuncret1;

{$ifdef FPC}
  {$mode delphi}
{$endif}

uses
  SysUtils;

type
  IAlpha = interface
    ['{EADE1DA8-C61E-44AA-8CB6-2A80297E8E41}']
  end;

  IBeta = interface
    ['{E2A7991D-B549-48AB-84D5-95D74075379B}']
  end;

  TProbe = class(TInterfacedObject, IAlpha, IBeta)
  private
    FTag: Integer;
  public
    class var Alive: Integer;
    class var Destroyed: array[1..8] of Integer;
    constructor Create(ATag: Integer);
    destructor Destroy; override;
  end;

  TManagedRec = record
    Ref: IAlpha;
  end;
  TManagedRecAlias = type TManagedRec;

constructor TProbe.Create(ATag: Integer);
begin
  inherited Create;
  FTag := ATag;
  Inc(Alive);
end;

destructor TProbe.Destroy;
begin
  Inc(Destroyed[FTag]);
  Dec(Alive);
  inherited Destroy;
end;

function NewProbeClass(ATag: Integer): TProbe; inline;
begin
  Result := TProbe.Create(ATag);
end;

function MakeAlpha(ATag: Integer): IAlpha; inline;
begin
  Result := TProbe.Create(ATag);
end;

function MakeManagedRec(ATag: Integer): TManagedRec;
begin
  Result.Ref := MakeAlpha(ATag);
end;

procedure Check(ACondition: Boolean; ACode: Integer);
begin
  If not ACondition then
    Halt(ACode);
end;

procedure TestTwoCasts;
var
  A: IAlpha;
  B: IBeta;
  U1, U2: IInterface;
begin
  A := TProbe.Create(1);
  Check(Supports(A, IBeta, B), 10);
  U1 := A as IInterface;
  U2 := B as IInterface;
  U1 := nil;
  U2 := nil;
  B := nil;
  A := nil;
  Check(TProbe.Alive = 0, 11);
  Check(TProbe.Destroyed[1] = 1, 12);
end;

procedure TestReplaceAndAlias;
var
  A: IAlpha;
  U: IInterface;
begin
  A := TProbe.Create(2);
  U := A as IInterface;
  A := nil;

  A := TProbe.Create(3);
  U := A as IInterface;
  Check(TProbe.Destroyed[2] = 1, 20);
  Check(TProbe.Alive = 1, 21);

  U := A as IInterface;
  A := nil;
  U := nil;
  Check(TProbe.Alive = 0, 22);
  Check(TProbe.Destroyed[3] = 1, 23);
end;

procedure TestClassResult;
var
  A: IAlpha;
begin
  A := NewProbeClass(4);
  Check(TProbe.Alive = 1, 30);
  A := nil;
  Check(TProbe.Alive = 0, 31);
  Check(TProbe.Destroyed[4] = 1, 32);
end;

procedure TestImplicitInterfaceResult;
var
  U: IInterface;
begin
  U := MakeAlpha(5);
  U := nil;
  Check(TProbe.Alive = 0, 40);
  Check(TProbe.Destroyed[5] = 1, 41);
end;

procedure TestExplicitInterfaceCast;
var
  U: IInterface;
begin
  U := IInterface(MakeAlpha(6));
  U := nil;
  Check(TProbe.Alive = 1, 50);
end;

procedure TestExplicitManagedRecordCast;
var
  R: TManagedRecAlias;
begin
  R := TManagedRecAlias(MakeManagedRec(7));
  R.Ref := nil;
  Check(TProbe.Alive = 1, 60);
end;

procedure TestFunctionAsCast;
var
  B: IBeta;
begin
  B := MakeAlpha(8) as IBeta;
  B := nil;
  Check(TProbe.Alive = 1, 70);
end;

begin
  TestTwoCasts;
  TestReplaceAndAlias;
  TestClassResult;
  TestImplicitInterfaceResult;
  TestExplicitInterfaceCast;
  Check(TProbe.Alive = 0, 51);
  Check(TProbe.Destroyed[6] = 1, 52);
  TestExplicitManagedRecordCast;
  Check(TProbe.Alive = 0, 61);
  Check(TProbe.Destroyed[7] = 1, 62);
  TestFunctionAsCast;
  Check(TProbe.Alive = 0, 71);
  Check(TProbe.Destroyed[8] = 1, 72);
  WriteLn('OK');
end.
