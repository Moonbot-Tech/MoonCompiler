program tail_contracts;
{$mode delphi}
{$inline off}
{$asmmode intel}
uses SysUtils;
type
  TPick = function(A,B,C,D: NativeInt): NativeInt;
  TFloat = function(A,B: Double): Double;
  TBig = record A,B,C: NativeInt; end;
  TBigFn = function(A: NativeInt): TBig;
  TCtorBox = class
    Value: NativeInt;
    constructor Create; virtual;
  end;
  TCtorBoxClass = class of TCtorBox;
var
  Pick: TPick;
  FloatPick: TFloat;
  BigPick: TBigFn;
  Cleaned: Integer;
  Stored: NativeInt;

constructor TCtorBox.Create;
begin
  inherited Create;
  Value := 53;
end;
function Factory(C: TCtorBoxClass): TCtorBox; noinline;
begin
  Result := C.Create;
end;
function Target(A,B,C,D: NativeInt): NativeInt; noinline;
begin
  Result := A+10*B+100*C+1000*D;
end;
function FloatTarget(A,B: Double): Double; noinline;
begin
  Result := A+2*B;
end;
function BigTarget(A: NativeInt): TBig; noinline;
begin
  Result.A := A;
  Result.B := A+1;
  Result.C := A+2;
end;
function ForwardArgs(A,B,C,D: NativeInt): NativeInt; noinline;
begin
  Result := Pick(D,C,B,A);
end;
function ConstantArgs: NativeInt; noinline;
begin
  Result := Pick(1,2,3,4);
end;
function DirectArgs(A,B,C,D: NativeInt): NativeInt; noinline;
begin
  Result := Target(D,C,B,A);
end;
function FloatArgs(A,B: Double): Double; noinline;
begin
  Result := FloatPick(B,A);
end;
function BigArgs(A: NativeInt): TBig; noinline;
begin
  Result := BigPick(A);
end;
function StackTarget(A,B,C,D,E,F,G,H,I,J: NativeInt): NativeInt; noinline;
begin
  Result := A+2*B+3*C+4*D+5*E+6*F+7*G+8*H+9*I+10*J;
end;
function StackArgs(A,B,C,D,E,F,G,H,I,J: NativeInt): NativeInt; noinline;
begin
  Result := StackTarget(J,I,H,G,F,E,D,C,B,A);
end;
function ReadLocal(P: PNativeInt): NativeInt; noinline;
begin
  Result := P^;
end;
function LocalArg(A: NativeInt): NativeInt; noinline;
var
  B: NativeInt;
begin
  B := A+1;
  Result := ReadLocal(@B);
end;
function FinallyArg(A: NativeInt): NativeInt; noinline;
begin
  try
    Result := Pick(A,2,3,4);
  finally
    Inc(Cleaned);
  end;
end;
function ManagedArg(A: NativeInt): NativeInt; noinline;
var
  S: UnicodeString;
begin
  S := IntToStr(A);
  Result := Pick(Length(S),2,3,4);
end;
function DirtyHigh: Cardinal; assembler; nostackframe;
asm
  mov rax, $FEDCBA9800000001
end;
function WidenReturn: UInt64; noinline;
begin
  Result := DirtyHigh;
end;
procedure StoreTarget(A: NativeInt); noinline;
begin
  Stored := A;
end;
procedure ProcArg(A: NativeInt); noinline;
begin
  StoreTarget(A);
end;
{ A target's volatile set must participate in the wrapper's save contract.
  The checker preserves its own nonvolatiles on both host ABIs. }
function SysVTarget: NativeInt; sysv_abi_default; assembler; nostackframe;
asm
  xor edi, edi
  xor esi, esi
  mov eax, 7
end;
function MsAbiForward: NativeInt; ms_abi_default; noinline;
begin
  Result := SysVTarget;
end;
function CheckCrossAbi: NativeInt; assembler; nostackframe;
asm
  push rdi
  push rsi
  mov edi, 123
  mov esi, 456
  sub rsp, 40
  call MsAbiForward
  add rsp, 40
  cmp rax, 7
  jne @Bad
  cmp rdi, 123
  jne @Bad
  cmp rsi, 456
  jne @Bad
  mov eax, 1
  jmp @Done
@Bad:
  xor eax, eax
@Done:
  pop rsi
  pop rdi
end;
function VaOracleCode(Marker: NativeInt): NativeInt; cdecl; assembler; nostackframe; public name 'tail_va_oracle';
asm
{$ifdef MSWINDOWS}
  movq rax, xmm1
  cmp rax, rdx
  sete al
  movzx eax, al
{$else}
  movzx eax, al
{$endif}
end;
function VarArgCall(Marker: NativeInt): NativeInt; cdecl; varargs; external name 'tail_va_oracle';
function ForwardVarArgs: NativeInt; noinline;
begin
  Result := VarArgCall(5, Double(1.25));
end;
var
  R: TBig;
  Box: TCtorBox;
begin
  Pick := Target;
  FloatPick := FloatTarget;
  BigPick := BigTarget;
  If ForwardArgs(1,2,3,4) <> 1234 then Halt(1);
  If ConstantArgs <> 4321 then Halt(2);
  If DirectArgs(1,2,3,4) <> 1234 then Halt(3);
  If FloatArgs(1,2) <> 4 then Halt(4);
  R := BigArgs(7);
  If (R.A <> 7) or (R.B <> 8) or (R.C <> 9) then Halt(5);
  If StackArgs(1,2,3,4,5,6,7,8,9,10) <> 220 then Halt(6);
  If LocalArg(9) <> 10 then Halt(7);
  If FinallyArg(1) <> 4321 then Halt(8);
  If Cleaned <> 1 then Halt(9);
  If ManagedArg(21) <> 4322 then Halt(10);
  Writeln('WIDEN=',WidenReturn);
  If WidenReturn <> 1 then Halt(11);
  ProcArg(89);
  If Stored <> 89 then Halt(12);
  If CheckCrossAbi <> 1 then Halt(13);
  If ForwardVarArgs <> 1 then Halt(14);
  Box := Factory(TCtorBox);
  If (Box.ClassType <> TCtorBox) or (Box.Value <> 53) then Halt(15);
  Box.Free;
  Writeln('TAIL_CONTRACTS_PASS');
end.
