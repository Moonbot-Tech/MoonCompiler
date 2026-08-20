program asm_byref_width_semantic;

{ Intel inline asm: a register-passed by-reference formal dereferences to
  its own scalar type.  The red form (audit 9dde393b): after converting the
  parameter register into a reference base the parser reset the operand
  width unconditionally, so the ambiguous "mov [Value],0" and "inc [Value]"
  on a var/out UInt64 fell back to dword and silently corrupted the upper
  half.  A value Pointer keeps the width unknown (the register only carries
  an address), an explicit "ptr" stays authoritative, and instructions with
  a sized second operand (movss) were already recovered by the matcher. }
{$mode delphiunicode}{$H+}{$asmmode intel}
uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}cthreads,cwstring,{$endif UNIX}
  SysUtils;
var
  Fails: Integer = 0;
procedure ZeroStore(var Value: UInt64); assembler; nostackframe;
asm
  mov [Value], 0
end;
procedure IncVal(var Value: UInt64); assembler; nostackframe;
asm
  inc [Value]
end;
procedure OutStore(out Value: UInt64); assembler; nostackframe;
asm
  mov [Value], 0
end;
procedure ViaPointer(Buffer: Pointer); assembler; nostackframe;
asm
  mov dword ptr [Buffer], 7
end;
procedure LoadStoreSingle(P: Pointer); assembler; nostackframe;
asm
  movss xmm0, [P]
  movss [P], xmm0
end;
procedure ByteVar(var Small: Byte); assembler; nostackframe;
asm
  mov [Small], 5
end;
procedure Check(const Name: string; Got, Want: UInt64);
begin
  if Got <> Want then
  begin
    Writeln('FAIL ', Name, ' got=', Got, ' want=', Want);
    Inc(Fails);
  end;
end;
var
  V: UInt64;
  D: Cardinal;
  Sm: Byte;
  F: Single;
begin
  V := UInt64($AABBCCDD00000000) or 5;
  ZeroStore(V);
  Check('zero-store', V, 0);
  V := $00000000FFFFFFFF;
  IncVal(V);
  Check('inc-carry', V, UInt64($0000000100000000));
  V := UInt64($AABBCCDD11223344);
  OutStore(V);
  Check('out-store', V, 0);
  D := 0;
  ViaPointer(@D);
  Check('via-pointer', D, 7);
  F := 1.5;
  LoadStoreSingle(@F);
  Check('movss', PCardinal(@F)^, $3FC00000);
  Sm := 0;
  ByteVar(Sm);
  Check('byte-var', Sm, 5);
  if Fails = 0 then WriteLn('ASM_BYREF_WIDTH_SEMANTIC_OK') else Halt(1);
end.
