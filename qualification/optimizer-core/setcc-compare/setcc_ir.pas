program setcc_ir;
{$mode objfpc}
uses cclasses, procinfo, cgbase, globtype, globals, cpubase, aasmbase, aasmtai, aasmcpu, aasmdata, aoptobj, aoptcpu;
type
  TProbeProc = class(tprocinfo)
    constructor Create(ParentInfo: tprocinfo); override;
  end;
  TProbe = class(TCpuAsmOptimizer)
    function Run(var P: tai): Boolean;
  end;
var
  Failures: Integer;
constructor TProbeProc.Create(ParentInfo: tprocinfo);
begin
  framepointer:=NR_FRAME_POINTER_REG;
end;
function TProbe.Run(var P: tai): Boolean;
begin
  Result := OptPass2SETcc(P);
end;
procedure Check(Ok: Boolean; const Name: string);
begin
  If not Ok then begin
    WriteLn('FAIL:', Name);
    Inc(Failures);
  end;
end;
procedure Probe(const Name: string; CompareSize: topsize; Value: Integer;
  Consumer: tasmop; Cond: TAsmCond; FlagsLive, ValueLive: Boolean; Between: Integer; Want: Boolean;
  BetweenSize: topsize = S_L; MiddleConsumer: Integer = 0; ReallocateFlags: Boolean = false;
  StackSource: Boolean = false; DelayRelease: Integer = 0);
var
  L: TAsmList;
  O: TProbe;
  P: tai;
  Setter, Cmp, UseCond, Middle, ReadFlags: taicpu;
  Target: TAsmLabel;
  Symbols: TFPHashObjectList;
  Changed: Boolean;
  SourceReg, DestReg: TRegister;
  ExpectedCond: TAsmCond;
begin
  L := TAsmList.Create;
  Symbols:=TFPHashObjectList.Create(true);
  Setter := taicpu.op_reg(A_SETcc,S_B,NR_AL);
  Setter.SetCondition(C_L);
  L.Concat(Setter);
  Middle := nil;
  SourceReg:=NR_ECX;
  DestReg:=NR_EDX;
  If BetweenSize=S_W then begin
    SourceReg:=NR_CX;
    DestReg:=NR_DX;
  end;
  If BetweenSize=S_Q then begin
    SourceReg:=NR_RCX;
    DestReg:=NR_RDX;
  end;
  If StackSource then SourceReg:=NR_RSP;
  If Between<>0 then begin
    If Between=-1 then Middle := taicpu.op_reg(A_CALL,S_NO,NR_RCX)
    else If Between=1 then Middle := taicpu.op_const_reg(A_ADD,S_L,7,NR_ECX)
    else Middle := taicpu.op_const_reg_reg(A_IMUL,BetweenSize,Between,SourceReg,DestReg);
    L.Concat(Middle);
  end;
  If MiddleConsumer<>0 then begin
    If MiddleConsumer=1 then ReadFlags:=taicpu.op_reg(A_SETcc,S_B,NR_BL)
    else ReadFlags:=taicpu.op_reg_reg(A_CMOVcc,S_L,NR_EDX,NR_EBX);
    ReadFlags.SetCondition(C_E);
    L.Concat(ReadFlags);
  end;
  If Value=0 then Cmp:=taicpu.op_reg_reg(A_TEST,S_B,NR_AL,NR_AL)
  else If CompareSize=S_B then Cmp:=taicpu.op_const_reg(A_CMP,S_B,Value,NR_AL)
  else Cmp:=taicpu.op_const_reg(A_CMP,CompareSize,Value,NR_EAX);
  L.Concat(Cmp);
  Target:=nil;
  If Consumer=A_Jcc then begin
    Target:=TAsmLabel.CreateLocal(Symbols,1,alt_jump);
    UseCond:=taicpu.op_cond_sym(A_Jcc,Cond,S_NO,Target);
    UseCond.is_jmp:=true;
  end else begin
    UseCond:=taicpu.op_reg(Consumer,S_B,NR_DL);
    UseCond.SetCondition(Cond);
  end;
  L.Concat(UseCond);
  If DelayRelease=2 then begin
    L.Concat(tai_marker.Create(mark_NoPropInfoStart));
    ReadFlags:=taicpu.op_reg(A_SETcc,S_B,NR_BL);
    ReadFlags.SetCondition(C_B);
    L.Concat(ReadFlags);
    L.Concat(tai_marker.Create(mark_NoPropInfoEnd));
  end;
  If DelayRelease<>0 then L.Concat(taicpu.op_reg_reg(A_MOV,S_L,NR_ECX,NR_EBX));
  If DelayRelease=3 then L.Concat(taicpu.op_reg(A_CALL,S_NO,NR_RCX));
  If FlagsLive and (Consumer=A_SETcc) then begin
    ReadFlags:=taicpu.op_reg(A_SETcc,S_B,NR_BL);
    ReadFlags.SetCondition(C_B);
    L.Concat(ReadFlags);
  end;
  If not FlagsLive then L.Concat(tai_regalloc.DeAlloc(NR_DEFAULTFLAGS,nil));
  If ReallocateFlags then L.Concat(tai_regalloc.Alloc(NR_DEFAULTFLAGS,nil));
  { Fallthrough overwrites flags; the taken path still needs them in live case. }
  L.Concat(taicpu.op_const_reg(A_CMP,S_L,5,NR_ECX));
  L.Concat(taicpu.op_none(A_RET,S_NO));
  If Assigned(Target) then begin
    L.Concat(tai_label.Create(Target));
    If FlagsLive then begin
      Middle:=taicpu.op_reg(A_SETcc,S_B,NR_DL);
      Middle.SetCondition(C_B);
      L.Concat(Middle);
      L.Concat(tai_regalloc.DeAlloc(NR_DEFAULTFLAGS,nil));
    end;
    L.Concat(taicpu.op_none(A_RET,S_NO));
  end;
  O:=TProbe.Create(L);
  O.IncludeRegInUsedRegs(NR_DEFAULTFLAGS,O.UsedRegs);
  If ValueLive then O.IncludeRegInUsedRegs(NR_AL,O.UsedRegs);
  P:=Setter;
  Changed:=O.Run(P);
  Check(Changed=Want,Name+' changed');
  If Changed then begin
    ExpectedCond:=C_L;
    If conditions_equal(Cond,C_NE) xor (Value=0) then ExpectedCond:=inverse_cond(ExpectedCond);
    Check(conditions_equal(UseCond.condition,ExpectedCond),Name+' condition mapping');
    If ValueLive then Check(L.First=Setter,Name+' live result')
    else If (Between=0) and (MiddleConsumer=0) then Check(L.First=UseCond,Name+' dead result');
    If Between<>0 then begin
      Check(Middle.opcode=A_LEA,Name+' preserve original flags');
      Check(Middle.ops=2,Name+' two LEA operands');
      If Between<>1 then begin
        Check(Middle.oper[1]^.reg=DestReg,Name+' destination');
        Check(Middle.oper[0]^.ref^.index=SourceReg,Name+' source');
        If Between in [2,4,8] then begin
          Check(Middle.oper[0]^.ref^.scalefactor=Between,Name+' scale');
          Check(Middle.oper[0]^.ref^.base=NR_NO,Name+' no base');
        end else begin
          Check(Middle.oper[0]^.ref^.scalefactor=Between-1,Name+' scale plus base');
          Check(Middle.oper[0]^.ref^.base=SourceReg,Name+' base');
        end;
      end;
    end;
  end else begin
    If Value=0 then Check(Cmp.opcode=A_TEST,Name+' kept test')
    else Check(Cmp.opcode=A_CMP,Name+' kept compare');
    If Between<>0 then Check(Middle.opcode<>A_LEA,Name+' no partial rewrite');
  end;
  O.Free;
  L.Free;
  Symbols.Free;
  WriteLn('CHECKED:',Name);
end;
procedure CallLifetimeQuery;
var
  L: TAsmList;
  O: TProbe;
  Call, BeforeCall: taicpu;
begin
  L:=TAsmList.Create;
  BeforeCall:=taicpu.op_reg_reg(A_MOV,S_L,NR_ECX,NR_EDX);
  L.Concat(BeforeCall);
  Call:=taicpu.op_reg(A_CALL,S_NO,NR_RCX);
  L.Concat(Call);
  O:=TProbe.Create(L);
  Check(not O.InstructionLoadsFromReg(NR_DEFAULTFLAGS,Call),'call does not extend released arithmetic flags');
  Check(O.InstructionLoadsFromReg(NR_RCX,Call),'call keeps argument lifetime');
  Check(O.InstructionLoadsFromReg(newreg(getregtype(NR_DEFAULTFLAGS),RS_DEFAULTFLAGS,R_SUBFLAGDIRECTION),Call),
    'call keeps direction flag contract');
  Check(O.RegReadByInstruction(NR_DEFAULTFLAGS,Call),'call remains conservative motion barrier');
  Check(not O.RegLoadedWithNewValue(NR_DEFAULTFLAGS,Call),'call is not an explicit full flags overwrite');
  O.IncludeRegInUsedRegs(NR_DEFAULTFLAGS,O.UsedRegs);
  Check(O.RegUsedAfterInstruction(NR_DEFAULTFLAGS,BeforeCall,O.UsedRegs),'call retains a live flags lifetime');
  O.Free;
  L.Free;
  WriteLn('CHECKED:call lifetime query');
end;
begin
  current_procinfo:=TProbeProc.Create(nil);
  current_settings.optimizerswitches:=[cs_opt_level3,cs_opt_peephole];
  Probe('eq branch',S_B,1,A_Jcc,C_E,false,false,0,true);
  Probe('ne branch',S_B,1,A_Jcc,C_NE,false,false,0,true);
  Probe('eq set',S_B,1,A_SETcc,C_E,false,false,0,true);
  Probe('ne set',S_B,1,A_SETcc,C_NE,false,false,0,true);
  Probe('live value',S_B,1,A_Jcc,C_E,false,true,0,true);
  Probe('between add',S_B,1,A_Jcc,C_E,false,false,1,true);
  Probe('between imul3',S_B,1,A_Jcc,C_E,false,false,3,true);
  Probe('between imul2',S_B,1,A_Jcc,C_E,false,false,2,true);
  Probe('between imul4',S_B,1,A_Jcc,C_E,false,false,4,true);
  Probe('between imul5',S_B,1,A_Jcc,C_E,false,false,5,true);
  Probe('between imul8',S_B,1,A_Jcc,C_E,false,false,8,true);
  Probe('between imul9',S_B,1,A_Jcc,C_E,false,false,9,true);
  Probe('between imul64',S_B,1,A_Jcc,C_E,false,false,3,true,S_Q);
  Probe('between imul16',S_B,1,A_Jcc,C_E,false,false,3,false,S_W);
  Probe('between imul stack source',S_B,1,A_Jcc,C_E,false,false,3,false,S_Q,0,false,true);
  Probe('between imul7',S_B,1,A_Jcc,C_E,false,false,7,false);
  Probe('old test imul3',S_B,0,A_Jcc,C_E,false,false,3,true);
  Probe('old test imul7',S_B,0,A_Jcc,C_E,false,false,7,false);
  Probe('other SET flags',S_B,1,A_Jcc,C_E,false,false,1,false,S_L,1);
  Probe('other CMOV flags',S_B,1,A_Jcc,C_E,false,false,1,false,S_L,2);
  Probe('same SET flags',S_B,1,A_Jcc,C_E,false,false,0,true,S_L,1);
  Probe('same CMOV flags',S_B,1,A_Jcc,C_E,false,false,0,true,S_L,2);
  Probe('old test other flags',S_B,0,A_Jcc,C_E,false,false,1,false,S_L,1);
  Probe('live flags branch',S_B,1,A_Jcc,C_E,true,false,0,false);
  Probe('live flags set',S_B,1,A_SETcc,C_E,true,false,0,false);
  Probe('old test live flags branch',S_B,0,A_Jcc,C_E,true,false,0,false);
  Probe('old test live flags set',S_B,0,A_SETcc,C_E,true,false,0,false);
  Probe('new flags lifetime',S_B,1,A_Jcc,C_E,false,false,0,true,S_L,0,true);
  Probe('old test new flags lifetime',S_B,0,A_Jcc,C_E,false,false,0,true,S_L,0,true);
  Probe('delayed SET release',S_B,1,A_SETcc,C_E,false,false,0,true,S_L,0,false,false,1);
  Probe('delayed TEST SET release',S_B,0,A_SETcc,C_E,false,false,0,true,S_L,0,false,false,1);
  Probe('delayed live SET flags',S_B,1,A_SETcc,C_E,true,false,0,false,S_L,0,false,false,1);
  Probe('opaque flags reader',S_B,1,A_SETcc,C_E,false,false,0,false,S_L,0,false,false,2);
  Probe('call before flags release',S_B,1,A_SETcc,C_E,false,false,0,false,S_L,0,false,false,3);
  Probe('intervening call',S_B,1,A_Jcc,C_E,false,false,-1,false);
  Probe('wide compare',S_L,1,A_Jcc,C_E,false,false,0,false);
  Probe('other constant',S_B,2,A_Jcc,C_E,false,false,0,false);
  Probe('other condition',S_B,1,A_Jcc,C_B,false,false,0,false);
  CallLifetimeQuery;
  If Failures<>0 then Halt(1);
  WriteLn('SETCC-IR:PASS');
end.
