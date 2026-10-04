{
    Copyright (c) 1998-2004 by Jonas Maebe

    This unit calls the optimization procedures to optimize the assembler
    code for sparc

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program; if not, write to the Free Software
    Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

 ****************************************************************************
}

unit aoptcpu;

{$i fpcdefs.inc}

interface

uses cpubase, aasmtai, cgbase, aopt, aoptx86;

type
  TCpuAsmOptimizer = class(TX86AsmOptimizer)
  private
    function OptPass1DIV(var p: tai): Boolean;
    function PostPeepholeOptImm64(var p: tai): Boolean;
  public
    function PrePeepHoleOptsCpu(var p: tai): boolean; override;
    function PeepHoleOptPass1Cpu(var p: tai): boolean; override;
    function PeepHoleOptPass2Cpu(var p: tai): boolean; override;
    function PostPeepHoleOptsCpu(var p : tai) : boolean; override;
  end;

implementation

uses
  globals,
  globtype,
  aasmcpu,
  aasmbase,
  cgutils,
  paramgr,
  procinfo;

    function TCpuAsmOptimizer.PostPeepholeOptImm64(var p: tai): Boolean;
      const
        MaxMaterializations = 16;
        MaxInstructions = 64;
        Metadata = [ait_comment,ait_regalloc,ait_tempalloc,ait_force_line];
      var
        Loads, Consumers: array[0..MaxMaterializations-1] of tai;
        Count, Insns, I, SuperReg: Integer;
        Scan, Consumer, Start, Previous, NewLoad: tai;
        Value: TCGInt;
        SharedReg: TRegister;
        RegSet: TCPURegisterSet;
        FreeRange: Boolean;

      function NextLocalInstruction(Current: tai): tai;
        begin
          Result:=tai(Current.Next);
          while Assigned(Result) and (Result.typ in Metadata) do
            Result:=tai(Result.Next);
          if not Assigned(Result) or (Result.typ<>ait_instruction) then
            Result:=nil;
        end;

      function IsMaterialization(Current: tai; out Use: tai): Boolean;
        begin
          Result:=False;
          Use:=nil;
          if not MatchInstruction(Current,A_MOV,[S_Q]) or
            (taicpu(Current).ops<>2) or
            (taicpu(Current).oper[0]^.typ<>top_const) or
            (taicpu(Current).oper[1]^.typ<>top_reg) or
            (taicpu(Current).oper[0]^.val<>Value) then
            exit;
          Use:=NextLocalInstruction(Current);
          { A two-operand IMUL reads the constant and writes only the other
            register. }
          Result:=Assigned(Use) and MatchInstruction(Use,A_IMUL,[S_Q]) and
            (taicpu(Use).ops=2) and
            MatchOperand(taicpu(Use).oper[0]^,taicpu(Current).oper[1]^) and
            (taicpu(Use).oper[1]^.typ=top_reg) and
            not SuperRegistersEqual(taicpu(Use).oper[0]^.reg,taicpu(Use).oper[1]^.reg) and
            RegEndOfLife(taicpu(Current).oper[1]^.reg,taicpu(Use));
        end;

      begin
        Result:=False;
        if not MatchInstruction(p,A_MOV,[S_Q]) or
          (taicpu(p).ops<>2) or
          (taicpu(p).oper[0]^.typ<>top_const) or
          (taicpu(p).oper[1]^.typ<>top_reg) then
          exit;
        Value:=taicpu(p).oper[0]^.val;
        { Keep encodable 32-bit constants on the existing lowering. }
        if (Value>=-2147483648) and (Value<=Int64($FFFFFFFF)) then
          exit;
        if not IsMaterialization(p,Consumer) then
          exit;
        Count:=1;
        Consumers[0]:=Consumer;
        Insns:=0;
        Scan:=Consumer;
        while (Count<MaxMaterializations) and (Insns<MaxInstructions) do
          begin
            Scan:=NextLocalInstruction(Scan);
            if not Assigned(Scan) or
              not MatchInstruction(Scan,[A_MOV,A_LEA,A_ADD,A_SUB,A_XOR,A_AND,A_OR,
                A_SHL,A_SHR,A_SAR,A_IMUL,A_CMP,A_TEST],[]) then
              break;
            Inc(Insns);
            if IsMaterialization(Scan,Consumer) then
              begin
                Loads[Count]:=Scan;
                Consumers[Count]:=Consumer;
                Inc(Count);
              end;
          end;
        if Count<2 then
          exit;

        { An already free volatile physical register cannot introduce a spill
          or a save/restore.  Inspect raw allocation nodes and both endpoints. }
        SharedReg:=NR_NO;
        RegSet:=paramanager.get_volatile_registers_int(current_procinfo.procdef.proccalloption);
        for SuperReg in RegSet do
          begin
            SharedReg:=newreg(R_INTREGISTER,TSuperRegister(SuperReg),R_SUBQ);
            if RegInUsedRegs(SharedReg,UsedRegs) then
              continue;
            FreeRange:=True;
            Scan:=p;
            repeat
              if ((Scan.typ=ait_instruction) and RegInInstruction(SharedReg,Scan)) or
                ((Scan.typ=ait_regalloc) and
                 (tai_regalloc(Scan).ratype<>ra_dealloc) and
                 SuperRegistersEqual(SharedReg,tai_regalloc(Scan).reg)) then
                begin
                  FreeRange:=False;
                  break;
                end;
              if Scan=Consumers[Count-1] then
                break;
              Scan:=tai(Scan.Next);
            until not Assigned(Scan);
            if FreeRange and Assigned(Scan) then
              break;
            SharedReg:=NR_NO;
          end;
        if (SharedReg=NR_NO) or RegInUsedRegs(SharedReg,UsedRegs) then
          exit;

        { Move only a pure immediate load, never an arithmetic operation or a
          memory access.  Stop at every label, boundary and register lifetime. }
        Start:=p;
        Previous:=tai(Start.Previous);
        Insns:=0;
        while Assigned(Previous) and (Insns<MaxInstructions) do
          begin
            if Previous.typ in Metadata then
              begin
                if (Previous.typ=ait_regalloc) and
                  SuperRegistersEqual(SharedReg,tai_regalloc(Previous).reg) then
                  break;
              end
            else if (Previous.typ=ait_instruction) and
              MatchInstruction(Previous,[A_MOV,A_LEA,A_ADD,A_SUB,A_XOR,A_AND,A_OR,
                A_SHL,A_SHR,A_SAR,A_IMUL],[]) and
              not RegInInstruction(SharedReg,Previous) and
              not RegInInstruction(NR_STACK_POINTER_REG,Previous) then
              begin
                Start:=Previous;
                Inc(Insns);
              end
            else
              break;
            Previous:=tai(Previous.Previous);
          end;

        NewLoad:=taicpu.op_const_reg(A_MOV,S_Q,Value,SharedReg);
        taicpu(NewLoad).fileinfo:=taicpu(p).fileinfo;
        AsmL.InsertBefore(NewLoad,Start);
        AllocRegBetween(SharedReg,NewLoad,Consumers[Count-1],UsedRegs);
        for I:=0 to Count-1 do
          begin
            taicpu(Consumers[I]).loadreg(0,SharedReg);
            if I>0 then
              RemoveInstruction(Loads[I]);
          end;
        RemoveCurrentP(p,Consumers[0]);
        Result:=True;
      end;

    function TCpuAsmOptimizer.OptPass1DIV(var p: tai): Boolean;
      var
        FirstSetup,
        FirstExtend,
        FirstCopy,
        SecondSetup,
        SecondExtend,
        SecondDiv,
        SecondCopy: tai;
        NumeratorReg,
        DivisorReg,
        FirstResultReg,
        OtherResultReg: TRegister;

      function MatchExtend(const First, Second: tai): Boolean;
        begin
          Result:=MatchInstruction(Second,taicpu(First).opcode,
            [taicpu(First).opsize]);
          if not Result then
            exit;
          case taicpu(First).opcode of
            A_CDQ,A_CQO:
              Result:=(taicpu(First).ops=0) and
                (taicpu(Second).ops=0);
            A_XOR:
              Result:=(taicpu(First).ops=2) and
                (taicpu(Second).ops=2) and
                MatchOperand(taicpu(First).oper[0]^,
                  taicpu(Second).oper[0]^) and
                MatchOperand(taicpu(First).oper[1]^,
                  taicpu(Second).oper[1]^);
            else
              Result:=False;
          end;
        end;

      function IsExpectedExtend(const Instr: tai): Boolean;
        begin
          if taicpu(p).opcode=A_IDIV then
            if taicpu(p).opsize=S_Q then
              exit(MatchInstruction(Instr,A_CQO,[S_NO]))
            else
              exit(MatchInstruction(Instr,A_CDQ,[S_NO]));
          Result:=MatchInstruction(Instr,A_XOR,[taicpu(p).opsize]) and
            (taicpu(Instr).ops=2) and
            (taicpu(Instr).oper[0]^.typ=top_reg) and
            (taicpu(Instr).oper[1]^.typ=top_reg) and
            (getsupreg(taicpu(Instr).oper[0]^.reg)=RS_EDX) and
            MatchOperand(taicpu(Instr).oper[0]^,
              taicpu(Instr).oper[1]^);
        end;

      begin
        Result:=False;

        { A hardware DIV/IDIV produces quotient and remainder together.  The
          generic lowering historically discarded one projection and repeated
          the same division for an immediately following complementary use.
          Reuse is deliberately recognized after register allocation: only an
          exact uninterrupted register-input sequence is accepted, so no load,
          aliasing store, call or second operand evaluation is removed. }
        if not MatchInstruction(p,A_DIV,A_IDIV,[S_L,S_Q]) or
           (taicpu(p).ops<>1) or
           (taicpu(p).oper[0]^.typ<>top_reg) or
           (getsupreg(taicpu(p).oper[0]^.reg) in [RS_EAX,RS_EDX]) or
           not GetLastInstruction(p,FirstExtend) or
           not IsExpectedExtend(FirstExtend) or
           not GetLastInstruction(FirstExtend,FirstSetup) or
           not MatchInstruction(FirstSetup,A_MOV,[taicpu(p).opsize]) or
           (taicpu(FirstSetup).ops<>2) or
           (taicpu(FirstSetup).oper[0]^.typ<>top_reg) or
           (taicpu(FirstSetup).oper[1]^.typ<>top_reg) or
           (getsupreg(taicpu(FirstSetup).oper[0]^.reg) in [RS_EAX,RS_EDX]) or
           (getsupreg(taicpu(FirstSetup).oper[1]^.reg)<>RS_EAX) or
           not GetNextInstruction(p,FirstCopy) or
           not MatchInstruction(FirstCopy,A_MOV,[taicpu(p).opsize]) or
           (taicpu(FirstCopy).ops<>2) or
           (taicpu(FirstCopy).oper[0]^.typ<>top_reg) or
           not GetNextInstruction(FirstCopy,SecondSetup) or
           not MatchInstruction(SecondSetup,A_MOV,[taicpu(p).opsize]) or
           (taicpu(SecondSetup).ops<>2) or
           not MatchOperand(taicpu(FirstSetup).oper[0]^,
             taicpu(SecondSetup).oper[0]^) or
           not MatchOperand(taicpu(FirstSetup).oper[1]^,
             taicpu(SecondSetup).oper[1]^) or
           not GetNextInstruction(SecondSetup,SecondExtend) or
           not MatchExtend(FirstExtend,SecondExtend) or
           not GetNextInstruction(SecondExtend,SecondDiv) or
           not MatchInstruction(SecondDiv,taicpu(p).opcode,
             [taicpu(p).opsize]) or
           (taicpu(SecondDiv).ops<>1) or
           not MatchOperand(taicpu(p).oper[0]^,
             taicpu(SecondDiv).oper[0]^) or
           not GetNextInstruction(SecondDiv,SecondCopy) or
           not MatchInstruction(SecondCopy,A_MOV,[taicpu(p).opsize]) or
           (taicpu(SecondCopy).ops<>2) or
           (taicpu(SecondCopy).oper[0]^.typ<>top_reg) then
          exit;

        NumeratorReg:=taicpu(FirstSetup).oper[0]^.reg;
        DivisorReg:=taicpu(p).oper[0]^.reg;
        FirstResultReg:=taicpu(FirstCopy).oper[0]^.reg;
        if getsupreg(FirstResultReg)=RS_EAX then
          OtherResultReg:=NR_RDX
        else if getsupreg(FirstResultReg)=RS_EDX then
          OtherResultReg:=NR_RAX
        else
          exit;
        setsubreg(OtherResultReg,getsubreg(FirstResultReg));

        if not MatchOperand(taicpu(SecondCopy).oper[0]^,OtherResultReg) or
           RegModifiedByInstruction(NumeratorReg,FirstCopy) or
           RegModifiedByInstruction(DivisorReg,FirstCopy) or
           RegModifiedByInstruction(OtherResultReg,FirstCopy) then
          exit;

        DebugMsg('DivMod pair reuses quotient/remainder',SecondDiv);
        RemoveInstruction(SecondSetup);
        RemoveInstruction(SecondExtend);
        RemoveInstruction(SecondDiv);
        Result:=True;
      end;

    function TCpuAsmOptimizer.PrePeepHoleOptsCpu(var p : tai) : boolean;
      begin
        result := false;
        case p.typ of
          ait_instruction:
            begin
              case taicpu(p).opcode of
                A_IMUL:
                  result:=PrePeepholeOptIMUL(p);
                A_SAR,A_SHR:
                  result:=PrePeepholeOptSxx(p);
                A_AND:
                  Result:=PrePeepholeOptAND(p);
                else
                  ;
              end;
            end;
          else
            ;
        end;

        { If this flag is set, something was optimised ahead of p, so move
          ahead by 1 instruction but treat as if Result was set to True }
        if aoc_ForceNewIteration in OptsToCheck then
          begin
            Exclude(OptsToCheck, aoc_ForceNewIteration);

            if not Result then
              begin
                if (p.typ in SkipInstr) then
                  UpdateUsedRegs(p);

                p := tai(p.Next);
                Result := True;
              end;
          end;
      end;


    function TCpuAsmOptimizer.PeepHoleOptPass1Cpu(var p: tai): boolean;
      begin
        result:=False;
        case p.typ of
          ait_instruction:
            begin
              case taicpu(p).opcode of
                A_ADD:
                  Result:=OptPass1ADD(p);
                A_AND:
                  Result:=OptPass1AND(p);
                A_CMOVcc:
                  Result:=OptPass1CMOVcc(p);
                A_IMUL:
                  Result:=OptPass1Imul(p);
                A_DIV,
                A_IDIV:
                  Result:=OptPass1DIV(p);
                A_MOV:
                  Result:=OptPass1MOV(p);
                A_MOVD,
                A_MOVQ,
                A_VMOVD,
                A_VMOVQ:
                  Result:=OptPass1MOVD(p);
                A_MOVSX,
                A_MOVSXD,
                A_MOVZX:
                  Result:=OptPass1Movx(p);
                A_NOT:
                  Result:=OptPass1NOT(p);
                A_MOVDQA,
                A_MOVAPD,
                A_MOVAPS,
                A_MOVUPD,
                A_MOVUPS,
                A_VMOVAPS,
                A_VMOVAPD,
                A_VMOVUPS,
                A_VMOVUPD:
                  result:=OptPass1_V_MOVAP(p);
                A_VMINSS,
                A_VMINSD,
                A_VMAXSS,
                A_VMAXSD,
                A_VSQRTSD,
                A_VSQRTSS,
                A_VDIVSD,
                A_VDIVSS,
                A_VSUBSD,
                A_VSUBSS,
                A_VMULSD,
                A_VMULSS,
                A_VADDSD,
                A_VADDSS,
                A_VANDPD,
                A_VANDPS,
                A_VORPD,
                A_VORPS:
                  result:=OptPass1VOP(p);
                A_MULSD,
                A_MULSS,
                A_ADDSD,
                A_ADDSS:
                  result:=OptPass1OP(p);
                A_VMOVSD,
                A_VMOVSS,
                A_MOVSD,
                A_MOVSS:
                  result:=OptPass1MOVXX(p);
                A_LEA:
                  result:=OptPass1LEA(p);
                A_SUB:
                  result:=OptPass1Sub(p);
                A_SHL,A_SAL:
                  result:=OptPass1SHLSAL(p);
                A_SHR:
                  result:=OptPass1SHR(p);
                A_FSTP,A_FISTP:
                  result:=OptPass1FSTP(p);
                A_FLD:
                  result:=OptPass1FLD(p);
                A_CMP:
                  result:=OptPass1Cmp(p);
                A_VPXORD,
                A_VPXORQ,
                A_VXORPS,
                A_VXORPD,
                A_VPXOR:
                  Result:=OptPass1VPXor(p);
                A_VMOVDQA,
                A_VMOVDQU:
                  Result:=OptPass1VMOVDQ(p);
                A_XORPS,
                A_XORPD,
                A_PXOR:
                  Result:=OptPass1PXor(p);
                A_TEST:
                  Result:=OptPass1Test(p);
                A_Jcc:
                  Result:=OptPass1Jcc(p);
                A_SHRX,
                A_SHLX:
                  Result:=OptPass1SHXX(p);
                A_VCVTSS2SD,
                A_CVTSS2SD:
                  Result:=OptPass1_V_Cvtss2sd(p);
                A_CLC,
                A_STC:
                  Result:=OptPass1STCCLC(p);
                else
                  ;
              end;
            end;
          else
            ;
        end;
        { If this flag is set, force another run of pass 1 even if p wasn't
          changed }
        if aoc_ForceNewIteration in OptsToCheck then
          begin
            Exclude(OptsToCheck, aoc_ForceNewIteration);

            if not Result then
              begin
                if (p.typ in SkipInstr) then
                  begin
                    UpdateUsedRegs(p);
                    p := tai(p.Next);
                  end
                else
                  begin
                    p := tai(p.Next);
                    UpdateUsedRegs(p);
                  end;
                Result := True;
              end;
          end;
      end;


    function TCpuAsmOptimizer.PeepHoleOptPass2Cpu(var p : tai) : boolean;
      begin
        Result := False;
        case p.typ of
          ait_instruction:
            begin
              case taicpu(p).opcode of
                A_MOV:
                  Result:=OptPass2MOV(p);
                A_MOVZX:
                  Result:=OptPass2Movx(p);
                A_IMUL:
                  Result:=OptPass2Imul(p);
                A_JMP:
                  Result:=OptPass2Jmp(p);
                A_Jcc:
                  Result:=OptPass2Jcc(p);
                A_Lea:
                  Result:=OptPass2Lea(p);
                A_SUB:
                  Result:=OptPass2SUB(p);
                A_ADD:
                  Result:=OptPass2ADD(p);
                A_CMOVcc:
                  Result:=OptPass2CMOVcc(p);
                A_SETcc:
                  result:=OptPass2SETcc(p);
                A_CMP:
                  Result:=OptPass2CMP(p);
                A_TEST:
                  Result:=OptPass2TEST(p);
                A_CLC,
                A_STC:
                  Result:=OptPass2STCCLC(p);
                else
                  ;
              end;
            end;
          else
            ;
        end;
        { If this flag is set, force another run of pass 2 even if p wasn't
          changed (-O3 only), but otherwise move p ahead by 1 instruction
          and treat as if Result was set to True }
        if aoc_ForceNewIteration in OptsToCheck then
          begin
            Exclude(OptsToCheck, aoc_ForceNewIteration);

            if not Result then
              begin
                if (p.typ in SkipInstr) then
                  begin
                    UpdateUsedRegs(p);
                    p := tai(p.Next);
                  end
                else
                  begin
                    p := tai(p.Next);
                    UpdateUsedRegs(p);
                  end;
                Result := True;
              end;
          end;
      end;


    function TCpuAsmOptimizer.PostPeepHoleOptsCpu(var p: tai): boolean;
      begin
        result := false;
        case p.typ of
          ait_instruction:
            begin
              case taicpu(p).opcode of
                A_MOV:
                  begin
                    Result:=PostPeepholeOptImm64(p);
                    if not Result then
                      Result:=PostPeepholeOptMov(p);
                  end;
                A_AND:
                  Result:=PostPeepholeOptAnd(p);
                A_MOVSX,
                A_MOVSXD:
                  Result:=PostPeepholeOptMOVSX(p);
                A_MOVZX:
                  Result:=PostPeepholeOptMovzx(p);
                A_CMP:
                  Result:=PostPeepholeOptCmp(p);
                A_OR,
                A_TEST:
                  Result:=PostPeepholeOptTestOr(p);
                A_XOR:
                  Result:=PostPeepholeOptXor(p);
                A_CALL:
                  Result:=PostPeepholeOptCall(p);
                A_LEA:
                  Result:=PostPeepholeOptLea(p);
                A_PUSH:
                  Result:=PostPeepholeOptPush(p);
                A_SHR:
                  Result:=PostPeepholeOptShr(p);
                A_ADD,
                A_SUB:
                  Result:=PostPeepholeOptADDSUB(p);
                A_RET:
                  Result:=PostPeepholeOptRET(p);
                A_VPXOR:
                  Result:=PostPeepholeOptVPXOR(p);
                A_SARX,
                A_SHLX,
                A_SHRX:
                  Result:=PostPeepholeOptSARXSHLXSHRX(p);
                A_RORX:
                  Result:=PostPeepholeOptRORX(p);
                else
                  ;
              end;

              { Optimise any reference-type operands (if Result is True, the
                instruction will be checked on the next iteration) }
              if not Result then
                OptimizeRefs(taicpu(p));

            end;
          else
            ;
        end;
        { If this flag is set, something was optimised ahead of p, so move
          ahead by 1 instruction but treat as if Result was set to True }
        if aoc_ForceNewIteration in OptsToCheck then
          begin
            Exclude(OptsToCheck, aoc_ForceNewIteration);

            if not Result then
              begin
                if (p.typ in SkipInstr) then
                  UpdateUsedRegs(p);

                p := tai(p.Next);
                Result := True;
              end;
          end;
      end;


begin
  casmoptimizer := TCpuAsmOptimizer;
end.

