program setcc_semantic;
{$IFDEF FPC}{$MODE DELPHI}{$ASMMODE INTEL}{$ENDIF}
{$Q-}{$R-}
uses SysUtils;
type
  TChoice = (First, Second);
  TThree = (Zero, One, Two);
  TCallback = function(V: Integer): Integer;

function Pick(A, B: Integer): TChoice; inline;
begin
  If A < B then
    Result := First
  else
    Result := Second;
end;

function EqOne(A, B: Integer): Integer; {$IFDEF FPC}noinline;{$ENDIF}
begin
  If Pick(A, B) = Second then
    Result := 17
  else
    Result := 29;
end;

function NeOne(A, B: Integer): Integer; {$IFDEF FPC}noinline;{$ENDIF}
begin
  If Pick(A, B) <> Second then
    Result := 41
  else
    Result := 53;
end;

function LiveValue(A, B: Integer): Integer; {$IFDEF FPC}noinline;{$ENDIF}
var
  C: TChoice;
begin
  C := Pick(A, B);
  If C = Second then
    Result := 100 + A
  else
    Result := 200 + B;
  Result := Result + Ord(C);
end;

function Apart(A, B, V: Integer): Integer; {$IFDEF FPC}noinline;{$ENDIF}
var
  C: TChoice;
begin
  C := Pick(A, B);
  V := V + 7;
  If C = Second then
    Result := V + A
  else
    Result := V + B;
end;

function PickThree(A, B: Integer): TThree; inline;
begin
  If A < B then
    Result := One
  else
    Result := Two;
end;

function Sink(V: Integer): Integer; {$IFDEF FPC}noinline;{$ENDIF}
begin
  Result := V xor 42;
end;

function OtherSink(V: Integer): Integer; {$IFDEF FPC}noinline;{$ENDIF}
begin
  Result := V xor 77;
end;

function IsSet(Flags: Integer): Boolean; inline;
begin
  Result := Flags and $40000 <> 0;
end;

function SelectCallback(Flags, V: Integer): Integer; {$IFDEF FPC}noinline;{$ENDIF}
const
  Callbacks: array[Boolean] of TCallback = (Sink, OtherSink);
begin
  Result := Callbacks[not IsSet(Flags)](V);
end;

function MultiplyThree(A, B: Integer): Integer; {$IFDEF FPC}noinline;{$ENDIF}
var
  C: TChoice;
begin
  C := Pick(A, B);
  A := A * 3;
  If C = Second then
    Result := Sink(A)
  else
    Result := Sink(A + 3);
end;

function MultiplySeven(A, B: Integer): Integer; {$IFDEF FPC}noinline;{$ENDIF}
var
  C: TChoice;
begin
  C := Pick(A, B);
  A := A * 7;
  If C = Second then
    Result := Sink(A)
  else
    Result := Sink(A + 3);
end;

function BooleanMultiplySeven(A, B: Integer): Integer; {$IFDEF FPC}noinline;{$ENDIF}
var
  C: Boolean;
begin
  C := A < B;
  A := A * 7;
  If C then
    Result := Sink(A + 3)
  else
    Result := Sink(A);
end;

function OtherFlags(A, B, V: Integer): Integer; {$IFDEF FPC}noinline;{$ENDIF}
var
  C: TChoice;
  Zero: Boolean;
begin
  C := Pick(A, B);
  V := V + 7;
  Zero := V = 0;
  If C = Second then
    Result := Sink(V + Ord(Zero))
  else
    Result := Sink(V + Ord(Zero) + 3);
end;

function BooleanOtherFlags(A, B, V: Integer): Integer; {$IFDEF FPC}noinline;{$ENDIF}
var
  C, Zero: Boolean;
begin
  C := A < B;
  V := V + 7;
  Zero := V = 0;
  If C then
    Result := Sink(V + Ord(Zero) + 3)
  else
    Result := Sink(V + Ord(Zero));
end;

function NotBoolean(A, B: Integer): Integer; {$IFDEF FPC}noinline;{$ENDIF}
begin
  If PickThree(A, B) = One then
    Result := 67
  else
    Result := 79;
end;

function CompareWide(A, B: Integer): Integer; assembler;
asm
  mov r8d, A
  mov r9d, B
  mov eax, $100
  cmp r8d, r9d
  setl al
  cmp eax, 1
  sete al
  movzx eax, al
end;

function LiveFlags(A, B: Integer): Integer; assembler;
asm
  mov r8d, A
  mov r9d, B
  cmp r8d, r9d
  setl al
  cmp al, 1
  sete dl
  setb cl
  movzx eax, dl
  movzx edx, cl
  shl edx, 8
  or eax, edx
end;

function SignedLess(A, B: Integer): Boolean; assembler;
asm
  mov r8d, A
  mov r9d, B
  cmp r8d, r9d
  setl al
end;

procedure Check(Ok: Boolean; const Name: string);
begin
  If not Ok then begin
    WriteLn('FAIL:', Name);
    Halt(1);
  end;
end;

const
  Values: array[0..8] of Integer = (Low(Integer), Low(Integer)+1, -257, -1, 0, 1, 257, High(Integer)-1, High(Integer));
var
  A, B, E: Integer;
  Less: Boolean;
begin
  for A in Values do
    for B in Values do begin
      Less := SignedLess(A, B);
      If Less then E := 29 else E := 17;
      Check(EqOne(A, B) = E, 'equal one');
      If Less then E := 41 else E := 53;
      Check(NeOne(A, B) = E, 'not equal one');
      If Less then E := 200 + B else E := 101 + A;
      Check(LiveValue(A, B) = E, 'live value');
      If Less then E := B + 10 else E := A + 10;
      Check(Apart(A, B, 3) = E, 'intervening flags');
      If Less then E := 67 else E := 79;
      Check(NotBoolean(A, B) = E, 'not boolean');
      E := A * 3;
      If Less then E := E + 3;
      Check(MultiplyThree(A, B) = (E xor 42), 'multiply three');
      E := A * 7;
      If Less then E := E + 3;
      Check(MultiplySeven(A, B) = (E xor 42), 'multiply seven');
      Check(BooleanMultiplySeven(A, B) = (E xor 42), 'boolean multiply seven');
      If Less then E := 4 else E := 1;
      Check(OtherFlags(A, B, -7) = (E xor 42), 'other flags zero');
      Check(BooleanOtherFlags(A, B, -7) = (E xor 42), 'boolean other flags zero');
      If Less then E := 10 else E := 7;
      Check(OtherFlags(A, B, 0) = (E xor 42), 'other flags nonzero');
      Check(BooleanOtherFlags(A, B, 0) = (E xor 42), 'boolean other flags nonzero');
      Check(CompareWide(A, B) = 0, 'wide compare');
      If Less then E := 1 else E := 256;
      Check(LiveFlags(A, B) = E, 'live comparison flags');
      Check(SelectCallback(0, A) = (A xor 77), 'callback false');
      Check(SelectCallback($40000, A) = (A xor 42), 'callback true');
    end;
  WriteLn('SETCC-CMP1:PASS');
end.
