program Fpc41630MovssPointerAsm;

{$mode objfpc}

procedure LoadSingle(Buffer: Pointer); assembler;
asm
  movss xmm2, [Buffer]
end;

begin
end.
