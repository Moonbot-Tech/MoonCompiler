program inline_value_alias_semantic;
{$APPTYPE CONSOLE}
{$IFDEF FPC}{$mode delphi}{$H+}{$ENDIF}
{$INLINE ON}{$Q-}{$R-}

{ Value arguments are evaluated before the inlined body. A var argument,
  a captured variable or record Self must not turn a value into an alias.
  The call and branch controls also exercise reads preceding the mutation. }
type
  TPair = record
    A, B: Integer;
    function Bump(Value: Integer): Integer; inline;
  end;

function IntegerSnapshot(Value: Integer; var Original: Integer): Integer; inline;
begin
  Inc(Original);
  Result := Value;
end;

function FloatSnapshot(Value: Double; var Original: Integer): Double; inline;
begin
  Inc(Original);
  Result := Value;
end;

function CallTarget(Value: Integer; var Original: Integer): Integer;
{$IFDEF FPC}noinline;{$ENDIF}
begin
  Inc(Original);
  Result := Value;
end;

function BeforeCall(Value: Integer; var Original: Integer): Integer; inline;
begin
  Result := CallTarget(Value, Original);
end;

function BranchSnapshot(Value: Integer; var Original: Integer; Change: Boolean): Integer; inline;
begin
  If Change then Inc(Original);
  Result := Value;
end;

function OtherBranch(Value: Integer; var Original: Integer; Change: Boolean): Integer; inline;
begin
  If Change then begin
    Inc(Original);
    Result := -1;
  end else
    Result := Value;
end;

function LoopSnapshot(Value: Integer; var Original: Integer): Integer; inline;
var I: Integer;
begin
  Result := 0;
  I := 0;
  while I < 2 do begin
    Inc(Result, Value);
    Inc(Original);
    Inc(I);
  end;
end;

function LoopCallSnapshot(Value: Integer; var Original: Integer): Integer; inline;
var I: Integer;
begin
  for I := 1 to 2 do
    Result := CallTarget(Value, Original);
end;

function Mutate(var V: Integer): Integer;
{$IFDEF FPC}noinline;{$ENDIF}
begin
  Inc(V);
  Result := 3;
end;

function MixedSnapshot(Value: Integer; var Original: Integer): Integer; inline;
begin
  Result := Mutate(Original) + Value;
end;

function NestedCall(Value: Integer; var Original: Integer): Integer; inline;
begin
  Result := CallTarget(Value + Mutate(Original), Original);
end;

function CaseSnapshot(Value: Integer; var Original: Integer; Choice: Integer): Integer; inline;
begin
  case Choice of
    0: Inc(Original);
    1: Inc(Original, 2);
  end;
  Result := Value;
end;

function FinallySnapshot(Value: Integer; var Original: Integer): Integer; inline;
begin
  try
    Inc(Original);
  finally
    Result := Value;
  end;
end;

function GotoSnapshot(Value: Integer; var Original: Integer): Integer; inline;
label Again;
var I: Integer;
begin
  I := 0;
  Result := 0;
Again:
  Inc(Result, Value);
  Inc(Original);
  Inc(I);
  If I < 2 then goto Again;
end;

function TPair.Bump(Value: Integer): Integer;
begin
  Inc(A);
  Result := Value;
end;

function StringSnapshot(Value: string; var Original: string): string; inline;
begin
  Original := Original + '!';
  Result := Value;
end;

function Outer(Value: Integer): Integer; inline;
var Local: Integer;
begin
  Local := Value;
  Result := IntegerSnapshot(Local, Local);
end;

function Converted(Value: Integer): Double;
{$IFDEF FPC}noinline;{$ENDIF}
begin
  Result := FloatSnapshot(Double(Value), Value);
end;

function Captured(Value: Integer): Integer;
{$IFDEF FPC}noinline;{$ENDIF}
  function Nested(Snapshot: Integer): Integer;
  {$IFDEF FPC}inline;{$ENDIF}
  begin
    Inc(Value);
    Result := Snapshot;
  end;
begin
  Result := Nested(Value);
end;

procedure Check(Ok: Boolean; const Name: string);
begin
  If not Ok then begin
    WriteLn('INLINE_VALUE_ALIAS_FAIL ', Name);
    Halt(1);
  end;
end;

procedure Run(Value: Integer);
{$IFDEF FPC}noinline;{$ENDIF}
var
  V, Actual: Integer;
  Twin: Integer absolute V;
  Pair: TPair;
  S, Seen: string;
begin
  V := Value;
  Actual := IntegerSnapshot(V, V);
  Check((Actual = Value) and (V = Value + 1), 'same var');
  V := Value;
  Actual := IntegerSnapshot(V, Twin);
  Check((Actual = Value) and (V = Value + 1), 'absolute twin');
  Check(Converted(Value) = Value, 'integer to double');
  V := Value;
  Actual := BeforeCall(V, V);
  Check((Actual = Value) and (V = Value + 1), 'call arguments before mutation');
  V := Value;
  Check(BranchSnapshot(V, V, False) = Value, 'untaken mutation');
  Check(BranchSnapshot(V, V, True) = Value, 'taken mutation');
  V := Value;
  Check(OtherBranch(V, V, False) = Value, 'read in other branch');
  Check(OtherBranch(V, V, True) = -1, 'write in other branch');
  V := Value;
  Actual := LoopSnapshot(V, V);
  Check((Actual = Value * 2) and (V = Value + 2), 'loop carried alias');
  V := Value;
  Actual := LoopCallSnapshot(V, V);
  Check((Actual = Value) and (V = Value + 2), 'repeated forwarding call');
  V := Value;
  Check(MixedSnapshot(V, V) = Value + 3, 'call in expression');
  V := Value;
  Actual := NestedCall(V, V);
  Check((Actual = Value + 3) and (V = Value + 2), 'nested calls');
  V := Value;
  Check(CaseSnapshot(V, V, 0) = Value, 'case write before read');
  V := Value;
  Check(FinallySnapshot(V, V) = Value, 'finally after mutation');
  V := Value;
  Actual := GotoSnapshot(V, V);
  Check((Actual = Value * 2) and (V = Value + 2), 'backward goto');
  Pair.A := Value;
  Pair.B := 0;
  Check(Pair.Bump(Pair.A) = Value, 'record Self');
  Check(Pair.A = Value + 1, 'record mutation');
  Check(Outer(Value) = Value, 'temp of outer inline');
  Check(Captured(Value) = Value, 'captured source');
  S := Copy('_abc', 2, 3);
  Seen := StringSnapshot(S, S);
  Check((Seen = 'abc') and (S = 'abc!'), 'managed value lifetime');
end;

var I: Integer;
begin
  for I := -10 to 10 do Run(I);
  WriteLn('INLINE_VALUE_ALIAS_OK');
end.
