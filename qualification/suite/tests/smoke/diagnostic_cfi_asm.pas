program diagnostic_cfi_asm;
{$mode delphi}{$asmmode att}
uses SysUtils, Moon.Diagnostics;

type TCallback = procedure;

procedure ASMBridge(Callback: TCallback); assembler; nostackframe;
{$ifdef ILLEGAL_INLINE}inline;{$endif}
asm
  pushq %rax
  .cfi_def_cfa_offset 16
  call *%rdi
  popq %rax
  .cfi_def_cfa_offset 8
end;

procedure Capture;
begin
  WriteManualReport('through standalone ASM');
end;

procedure ThrowLeaf;
begin
  raise Exception.Create('through ASM');
end;

var Caught: Boolean;
begin
  InitializeReports(ParamStr(1));
  ASMBridge(Capture);
  Caught := False;
  try
    ASMBridge(ThrowLeaf);
  except
    on E: Exception do Caught := E.Message = 'through ASM';
  end;
  If not Caught then Halt(1);
  WriteLn('CFI_ASM_PASS');
end.
