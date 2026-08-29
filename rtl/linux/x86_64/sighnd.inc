{
    This file is part of the Free Pascal run time library.
    Copyright (c) 1999-2000 by Michael Van Canneyt,
    member of the Free Pascal development team.

    Signal handler is arch dependant due to processor to language
    exception conversion.

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}

{ $define SYSTEM_DEBUG}

{ Trampoline between the signal-to-exception conversion and
  HandleErrorAddrFrame.  The signal handler already stored the faulting RIP
  on the interrupted stack as this trampoline's return-address slot (so the
  PSABI unwinder walks tramp -> faulting routine -> its callers over their
  own CFI), and the interrupted RSP has ARBITRARY 16-byte parity: a routine
  compiled without a stack frame traps at rsp ≡ 8 (mod 16), a framed one at
  rsp ≡ 0.  The old `pushq addr; jmp` shape added exactly 8 bytes, which
  kept ABI alignment only for the framed parity and entered the whole
  raise/unwind chain misaligned for the frameless one - an aligned SSE
  spill inside libgcc's _Unwind_RaiseException then dies with SIGSEGV.
  A REAL frame (compiler prologue, rbp-based CFI) plus an explicit
  realignment before the call keeps the ABI contract for both parities;
  the rbp-based CFA still recovers the exact interrupted RSP for the
  unwinder no matter what the alignment fixup dropped. }
Procedure SignalToHandleErrorAddrFrame (Errno : longint;addr : CodePointer; frame : Pointer); assembler;
asm
  andq $-16,%rsp        { restore the ABI stack alignment for any trap parity }
  call HandleErrorAddrFrame
  { never returns }
end;

const
  FPU_All = $7f;

function GetFPUState(const SigContext : TSigContext) : word;
  begin
    if assigned(SigContext.fpstate) then
      GetfpuState:=SigContext.fpstate^.swd
    else
      GetFPUState:=0;
  {$ifdef SYSTEM_DEBUG}
    if assigned(SigContext.fpstate) then
    writeln('Tag: ',sigcontext.fpstate^.twd,' Cw: ',sigcontext.fpstate^.cwd);
    Writeln(stderr,'FpuState = ',result);
  {$endif SYSTEM_DEBUG}
  end;

function GetMMState(const SigContext : TSigContext) : dword;
  begin
    if assigned(SigContext.fpstate) then
      Result:=SigContext.fpstate^.mxcsr
    else
      Result:=0;
  {$ifdef SYSTEM_DEBUG}
    Writeln(stderr,'MMState = ',result);
  {$endif SYSTEM_DEBUG}
  end;


procedure SignalToRunerror(sig : longint; SigInfo: PSigInfo; SigContext: PSigContext); public name '_FPC_DEFAULTSIGHANDLER'; cdecl;
  var
    res,fpustate,MMState : word;
  begin
    res:=0;
    case sig of
      SIGFPE :
        begin
          { this is not always necessary but I don't know yet
            how to tell if it is or not PM }
          res:=200;
          if SigInfo^.si_code<>FPE_INTDIV then
            begin
              fpustate:=GetFPUState(SigContext^);
              if (FpuState and FPU_All) <> 0 then
                begin
                  { first check the more precise options }
                  if (FpuState and FPU_DivisionByZero)<>0 then
                    res:=208
                  else if (FpuState and FPU_Overflow)<>0 then
                    res:=205
                  else if (FpuState and FPU_Underflow)<>0 then
                    res:=206
                  else if (FpuState and FPU_Denormal)<>0 then
                    res:=206
                  else if (FpuState and (FPU_StackOverflow or FPU_StackUnderflow or FPU_Invalid))<>0 Then
                    res:=207
                  else
                    res:=207;  {'Coprocessor Error'}
                end
              else
                begin
                  MMState:=getMMState(SigContext^);
                  if (MMState and MM_ExceptionMask)<>0 then
                    begin
                      { first check the more precise options }
                      if (MMState and MM_DivisionByZero)<>0 then
                        res:=208
                      else if (MMState and MM_Invalid)<>0 Then
                        res:=207
                      else if (MMState and MM_Overflow)<>0 then
                        res:=205
                      else if (MMState and MM_Underflow)<>0 then
                        res:=206
                      else if (MMState and MM_Denormal)<>0 then
                        res:=206
                      else
                        res:=207;  {'Coprocessor Error'}
                    end;
                end;
              if assigned(SigContext^.fpstate) then
                with SigContext^.fpstate^ do
                  begin
  {$ifdef SYSTEM_DEBUG}
                    Writeln(stderr,'fpstate^.swd = ',swd);
  {$endif SYSTEM_DEBUG}
                    { actually, I am not sure if we should really touch the control word }
                    cwd:=Default8087CW;
                    { found by trial and error that setting to 0 means empty }
                    twd:=$0;
                    { clear top }
                    swd:=swd and not($3700);
                    { exceptions are handled, clear all flags
                      as we return from SignalToRunerrer, we have to clear the exception flags in the context }
                    mxcsr:=mxcsr and not(MM_ExceptionMask);
                    swd:=swd and not($37ff);
                  end;
            end;
        end;
      SIGILL,
      SIGBUS,
      SIGSEGV:
        res:=216;
    SIGINT:
        res:=217;
    SIGQUIT:
        res:=233;
    end;
    reenable_signal(sig);
    if res<>0 then
      begin
        { store the faulting address as the trampoline's return-address slot
          BEFORE resuming: the unwinder then sees a regular call chain
          trampoline -> faulting routine -> its callers, each over its own
          CFI (the red-zone bytes this overwrites belong to the routine we
          are turning into a raise anyway).  The slot carries RIP+1, not
          RIP: a return address semantically points AFTER the call, and the
          unwinder looks the FDE up at RA-1 - with a fault on the FIRST
          instruction of a routine (the plain shape of a nil dereference)
          a raw RIP would land the lookup BEFORE the routine, in a foreign
          or missing FDE, and the exception escapes every handler.  The
          reported fault address (rsi below) stays the exact RIP. }
        SigContext^.rsp := SigContext^.rsp - sizeof(ptruint);
        PPtrUInt(SigContext^.rsp)^ := SigContext^.rip + 1;
        SigContext^.rdi := res;
        SigContext^.rsi := SigContext^.rip;
        SigContext^.rdx := SigContext^.rbp;
        SigContext^.rip := ptruint(@SignalToHandleErrorAddrFrame);
      end;
  end;


