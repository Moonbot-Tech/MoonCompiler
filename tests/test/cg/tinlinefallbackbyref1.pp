{ %OPT=-O3 -OoAUTOINLINE }

program tinlinefallbackbyref1;

{$mode delphiunicode}

uses
  SysUtils,
  Variants;

type
  TData = record
    A, B, C, D: Int64;
  end;
  TIntArray = array of Integer;
  TTrackedToken = class(TInterfacedObject)
    constructor Create;
    destructor Destroy; override;
  end;

var
  G: TData;
  TokensAlive: Integer;

constructor TTrackedToken.Create;
begin
  inherited;
  Inc(TokensAlive);
end;

destructor TTrackedToken.Destroy;
begin
  Dec(TokensAlive);
  inherited;
end;

function SafeAlias(const Data: TData; out Value: PInt64): Boolean; inline;
begin
  Inc(G.A);
  Value := @G.A;
  Result := Data.A > 0;
end;

procedure UpdateAlias(var Value: Integer; const Data: TData); inline;
begin
  Inc(G.A);
  Inc(Value, Integer(Data.A));
end;

procedure SetAlias(out Value: Integer; const Data: TData); inline;
begin
  Inc(G.A);
  Value := Integer(Data.A);
end;

procedure UpdateWithManagedExpression(var Value: Integer); inline;
begin
  Inc(Value, Length(IntToStr(Value)));
end;

function CheckVar(Count: Integer): Int64; noinline;
var
  I, Value: Integer;
begin
  G.A := 0;
  Value := 0;
  Result := 0;
  for I := 1 to Count do
  begin
    UpdateAlias(Value, G);
    Inc(Result, Value);
  end;
end;

function CheckOut(Count: Integer): Int64; noinline;
var
  I, Value: Integer;
begin
  G.A := 0;
  Value := 0;
  Result := 0;
  for I := 1 to Count do
  begin
    SetAlias(Value, G);
    Inc(Result, Value);
  end;
end;

function CheckManagedRefusal: Integer; noinline;
begin
  Result := 8;
  UpdateWithManagedExpression(Result);
  UpdateWithManagedExpression(Result);
  UpdateWithManagedExpression(Result);
  UpdateWithManagedExpression(Result);
end;

procedure ConsumeOwnedString(const Value: UnicodeString); noinline;
begin
  Inc(G.C,Length(Value));
end;

procedure ConsumeOwnedArray(const Values: TIntArray); noinline;
begin
  Inc(G.C,Length(Values));
end;

procedure ConsumeOwnedInterface(const Token: IInterface;
  RaiseNow: Boolean); noinline;
begin
  If TokensAlive <> 1 then
    Halt(7);
  Inc(G.C,Ord(Token <> nil));
  If RaiseNow then
    raise Exception.Create('owned interface');
end;

function MakeOwnedArray: TIntArray; noinline;
begin
  SetLength(Result,2);
end;

function MakeOwnedInterface: IInterface; noinline;
begin
  Result := TTrackedToken.Create;
end;

procedure ForwardOwnedString(Value: Integer); inline;
begin
  ConsumeOwnedString(IntToStr(Value));
end;

procedure ForwardOwnedArray; inline;
begin
  ConsumeOwnedArray(MakeOwnedArray);
end;

procedure ForwardOwnedInterface(RaiseNow: Boolean); inline;
begin
  ConsumeOwnedInterface(MakeOwnedInterface,RaiseNow);
end;

function CheckOwnedActuals: Integer; noinline;
begin
  G.C := 0;
  ForwardOwnedString(123);
  ForwardOwnedArray;
  ForwardOwnedInterface(False);
  If TokensAlive <> 0 then
    Halt(8);
  Result := G.C;
end;

procedure CheckOwnedException; noinline;
begin
  try
    ForwardOwnedInterface(True);
    Halt(9);
  except
    on Exception do
      If TokensAlive <> 0 then
        Halt(10);
  end;
end;

procedure ConsumeManagedParameters(const Wide: UnicodeString;
  const Narrow: AnsiString; const Values: TIntArray;
  const Token: IInterface); noinline;
begin
  G.B := Length(Wide) + Length(Narrow) + Length(Values) + Ord(Token <> nil);
end;

procedure ForwardManagedParameters(const Wide: UnicodeString;
  const Narrow: AnsiString; const Values: TIntArray;
  const Token: IInterface); inline;
begin
  ConsumeManagedParameters(Wide,Narrow,Values,Token);
end;

function CheckManagedForwarding(const Wide: UnicodeString;
  const Narrow: AnsiString; const Values: TIntArray;
  const Token: IInterface): Int64; noinline;
begin
  G.B := 0;
  ForwardManagedParameters(Wide,Narrow,Values,Token);
  Result := G.B;
end;

function CheckShortCircuitOut: Boolean; noinline;
var
  Value: PInt64;
begin
  G.A := 0;
  Value := nil;
  Result := SafeAlias(G, Value) and (Value^ = 1);
end;

function SafeVariantAlias(const Data: Variant; out Value: Pointer): Boolean; inline;
begin
  Value := @Data;
  Result := True;
end;

function CheckVariantOut(const Data: Variant): Boolean; noinline;
var
  Value: Pointer;
  Ok: Boolean;
begin
  Value := nil;
  Ok := SafeVariantAlias(Data,Value);
  Result := Ok and (Value = @Data);
end;

var
  V: Variant;
  Values: TIntArray;
  Token: IInterface;

begin
  If CheckVar(10) <> 220 then
    Halt(1);
  If CheckOut(10) <> 55 then
    Halt(2);
  If CheckManagedRefusal <> 14 then
    Halt(3);
  If not CheckShortCircuitOut then
    Halt(4);
  V := 42;
  If not CheckVariantOut(V) then
    Halt(5);
  SetLength(Values,2);
  Token := nil;
  If CheckManagedForwarding('wide','narrow',Values,Token) <> 12 then
    Halt(6);
  If CheckOwnedActuals <> 6 then
    Halt(11);
  CheckOwnedException;
  WriteLn('INLINE_FALLBACK_BYREF_OK');
end.
