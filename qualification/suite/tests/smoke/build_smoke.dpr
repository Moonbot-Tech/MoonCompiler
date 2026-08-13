program build_smoke;

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  {$endif UNIX}
  SysUtils;

var
  Buffer: Pointer;

function IntelAsmIdentity(Value: PtrUInt): PtrUInt;
asm
  {$ifdef MSWINDOWS}
  mov rax, rcx
  {$else}
  mov rax, rdi
  {$endif MSWINDOWS}
end;

begin
  If IntelAsmIdentity($123456789ABCDEF0) <> $123456789ABCDEF0 then
    Halt(2);
  GetMem(Buffer, 256);
  try
    FillChar(Buffer^, 256, $A5);
    If PByte(Buffer)[0] <> $A5 then
      Halt(1);
  finally
    FreeMem(Buffer);
  end;
  Writeln('MOONBOT_BUILD_OK');
end.
