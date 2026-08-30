program asm_oracle;

{ Independent machine-level oracles for compiler-generated Pascal code.
  This is deliberately not a Chimera product organ: the Pascal bodies are
  the subject, while handwritten x86-64 performs the same work by an
  independent path. }

{$mode delphiunicode}{$H+}
{$modeswitch advancedrecords}
{$modeswitch INLINEVARS}
{$APPTYPE CONSOLE}
{$Q-}{$R-}

uses
  SysUtils,
  chimera_body,
  chimera_asm_int,
  chimera_asm_mem,
  chimera_asm_hash,
  chimera_asm_float,
  chimera_asm_str,
  chimera_asm_crypt,
  chimera_asm_road;

var
  I, M, H, F, S, C, R: Int64;
begin
  I := ChiAsmIntRun;
  M := ChiAsmMemRun;
  H := ChiAsmHashRun;
  F := ChiAsmFloatRun;
  S := ChiAsmStrRun;
  C := ChiAsmCryptRun;
  R := ChiAsmRoadRun;
  Write(ChiCoverageReport);
  if ChiFailures = 0 then
    WriteLn('ASM_ORACLE_OK int=', I, ' mem=', M, ' hash=', H,
            ' float=', F, ' str=', S, ' crypt=', C, ' road=', R)
  else
  begin
    WriteLn('ASM_ORACLE_BAD claims=', ChiFailures, ' ', ChiFailureList);
    Halt(1);
  end;
end.
