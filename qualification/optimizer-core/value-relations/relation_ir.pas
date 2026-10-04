program relation_ir;
{$mode objfpc}
uses cclasses,procinfo,cgbase,cgutils,globtype,globals,cpubase,aasmbase,aasmtai,aasmcpu,aasmdata,aoptobj,aoptcpu;
type
  TProbeProc=class(tprocinfo)
    constructor Create(ParentInfo:tprocinfo); override;
  end;
  TProbe=class(TCpuAsmOptimizer)
    function Run(P:tai):Boolean;
  end;
var Failures,MatrixCount,MatrixFolds:Integer;
    Truth:array[TAsmCond] of UInt32;
constructor TProbeProc.Create(ParentInfo:tprocinfo);
begin
  framepointer:=NR_FRAME_POINTER_REG;
end;
function TProbe.Run(P:tai):Boolean;
begin
  Result:=RemoveRedundantCmpJump(P);
end;
procedure Check(Ok:Boolean;const Name:string);
begin
  If not Ok then begin
    WriteLn('FAIL:',Name);
    Inc(Failures);
  end;
end;
function FlagCondition(C:TAsmCond;F:Integer):Boolean;
var CF,PF,ZF,SF,OF_:Boolean;
begin
  CF:=F and 1<>0;
  PF:=F and 2<>0;
  ZF:=F and 4<>0;
  SF:=F and 8<>0;
  OF_:=F and 16<>0;
  case C of
    C_A,C_NBE:Result:=not CF and not ZF;
    C_AE,C_NB,C_NC:Result:=not CF;
    C_B,C_C,C_NAE:Result:=CF;
    C_BE,C_NA:Result:=CF or ZF;
    C_E,C_Z:Result:=ZF;
    C_G,C_NLE:Result:=not ZF and (SF=OF_);
    C_GE,C_NL:Result:=SF=OF_;
    C_L,C_NGE:Result:=SF<>OF_;
    C_LE,C_NG:Result:=ZF or (SF<>OF_);
    C_NE,C_NZ:Result:=not ZF;
    C_NO:Result:=not OF_;
    C_O:Result:=OF_;
    C_P,C_PE:Result:=PF;
    C_NP,C_PO:Result:=not PF;
    C_S:Result:=SF;
    C_NS:Result:=not SF;
    else Result:=False;
  end;
end;
procedure BuildTruth;
var A,B,R,F,K,Parity:Integer; C:TAsmCond;
begin
  for A:=0 to 255 do for B:=0 to 255 do begin
    R:=(A-B) and 255;
    F:=Ord(A<B);
    Parity:=0;
    for K:=0 to 7 do Inc(Parity,(R shr K) and 1);
    If Parity and 1=0 then Inc(F,2);
    If R=0 then Inc(F,4);
    If R and 128<>0 then Inc(F,8);
    If ((A xor B) and (A xor R) and 128)<>0 then Inc(F,16);
    for C:=Succ(C_None) to High(TAsmCond) do
      If FlagCondition(C,F) then Truth[C]:=Truth[C] or (UInt32(1) shl F);
  end;
end;
function Probe(const Name:string;Kind:Integer;FirstCond,LaterCond:TAsmCond):Boolean;
var L:TAsmList; O:TProbe; Symbols:TFPHashObjectList; ExitLabel,JoinLabel:TAsmLabel;
    P,Cmp2,Jump2,Reader:tai; Ins:taicpu; Ref:TReference; BeforeRefs:Integer;
  procedure Jump(C:TAsmCond;Target:TAsmLabel);
  var J:taicpu;
  begin
    J:=taicpu.op_cond_sym(A_Jcc,C,S_NO,Target);
    J.is_jmp:=True;
    L.Concat(J);
  end;
  procedure Opaque;
  begin
    L.Concat(tai_marker.Create(mark_NoPropInfoStart));
    L.Concat(taicpu.op_const_reg(A_ADD,S_L,1,NR_EAX));
    L.Concat(tai_marker.Create(mark_NoPropInfoEnd));
  end;
  function Contains(Node:tai):Boolean;
  var T:tai;
  begin
    T:=tai(L.First);
    while Assigned(T) do begin
      If T=Node then Exit(True);
      T:=tai(T.Next);
    end;
    Result:=False;
  end;
begin
  L:=TAsmList.Create;
  Symbols:=TFPHashObjectList.Create(True);
  ExitLabel:=TAsmLabel.CreateLocal(Symbols,1,alt_jump);
  JoinLabel:=TAsmLabel.CreateLocal(Symbols,2,alt_jump);
  If Kind=19 then JoinLabel.bind:=AB_GLOBAL;
  If Kind=24 then JoinLabel.is_public:=True;
  If Kind=16 then P:=taicpu.op_const_reg(A_CMP,S_L,17,NR_EAX)
  else P:=taicpu.op_reg_reg(A_CMP,S_L,NR_EDX,NR_EAX);
  L.Concat(P);
  If Kind=9 then Opaque;
  If Kind=2 then Jump(FirstCond,JoinLabel) else Jump(FirstCond,ExitLabel);
  If Kind=28 then taicpu(L.Last).oper[0]^.ref^.offset:=1;
  case Kind of
    1,3,4,19,20,24:begin
      Jump(C_P,JoinLabel);
      L.Concat(tai_label.Create(JoinLabel));
    end;
    2:L.Concat(tai_label.Create(JoinLabel));
    5:L.Concat(taicpu.op_const_reg(A_MOV,S_B,3,NR_AH));
    6:L.Concat(taicpu.op_const_reg(A_MOV,S_L,3,NR_EDX));
    7:L.Concat(taicpu.op_reg(A_MUL,S_L,NR_ECX));
    8:Opaque;
    11:L.Concat(taicpu.op_reg(A_CALL,S_NO,NR_R11));
    12:begin
      Ins:=taicpu.op_sym(A_JMP,S_NO,ExitLabel);
      Ins.is_jmp:=True;
      L.Concat(Ins);
    end;
    13:L.Concat(taicpu.op_const_reg(A_ADD,S_L,1,NR_ECX));
    15:begin
      L.Concat(taicpu.op_reg_reg(A_COMISD,S_NO,NR_XMM0,NR_XMM1));
      Jump(C_P,JoinLabel);
      L.Concat(tai_label.Create(JoinLabel));
    end;
    21:L.Concat(tai_marker.Create(mark_AsmBlockStart));
    22:begin
      Jump(C_P,JoinLabel);
      Jump(C_E,JoinLabel);
      L.Concat(tai_label.Create(JoinLabel));
    end;
    23:begin
      reference_reset(Ref,4,[]);
      Ref.base:=NR_RAX;
      L.Concat(taicpu.op_reg_ref(A_MOV,S_L,NR_EDX,Ref));
    end;
    25:L.Concat(tai_label.Create(JoinLabel));
    26:begin
      Jump(C_P,JoinLabel);
      taicpu(L.Last).oper[0]^.ref^.offset:=1;
      L.Concat(tai_label.Create(JoinLabel));
    end;
    27:L.Concat(tai_regalloc.DeAlloc(NR_R11,nil));
    29,30:begin
      If Kind=29 then Ins:=taicpu.op_sym(A_JRCXZ,S_NO,ExitLabel)
      else Ins:=taicpu.op_sym(A_LOOP,S_NO,ExitLabel);
      Ins.is_jmp:=True;
      L.Concat(Ins);
    end;
  end;
  If Kind=3 then JoinLabel.IncRefs;
  If Kind=20 then begin
    Jump(C_P,JoinLabel);
    L.Concat(taicpu.op_const_reg(A_ADD,S_L,1,NR_EAX));
  end;
  If Kind=16 then Cmp2:=taicpu.op_const_reg(A_CMP,S_L,17,NR_EAX)
  else If Kind=17 then Cmp2:=taicpu.op_reg_reg(A_CMP,S_Q,NR_RDX,NR_RAX)
  else If Kind=18 then Cmp2:=taicpu.op_reg_reg(A_CMP,S_L,NR_EAX,NR_EDX)
  else Cmp2:=taicpu.op_reg_reg(A_CMP,S_L,NR_EDX,NR_EAX);
  L.Concat(Cmp2);
  If Kind=10 then Opaque;
  Jump(LaterCond,ExitLabel);
  Jump2:=tai(L.Last);
  Reader:=taicpu.op_reg(A_SETcc,S_B,NR_CL);
  taicpu(Reader).SetCondition(C_B);
  L.Concat(Reader);
  If Kind=4 then Jump(C_P,JoinLabel);
  L.Concat(tai_label.Create(ExitLabel));
  L.Concat(taicpu.op_none(A_RET,S_NO));
  BeforeRefs:=ExitLabel.getrefs;
  O:=TProbe.Create(L);
  Result:=O.Run(P);
  Check(Contains(Cmp2),Name+' CMP flags preserved');
  Check(Contains(Reader),Name+' flags consumer preserved');
  Check(Contains(Jump2)<>Result,Name+' change result');
  Check(ExitLabel.getrefs=BeforeRefs-Ord(Result),Name+' symbol refs');
  O.Free;
  L.Free;
  Symbols.Free;
end;
procedure CaseProbe(const Name:string;Kind:Integer;Want:Boolean);
begin
  Check(Probe(Name,Kind,C_NG,C_LE)=Want,Name);
  WriteLn(Name,':',Want);
end;
var A,B:TAsmCond;Changed,Valid:Boolean;
begin
  current_procinfo:=TProbeProc.Create(nil);
  current_settings.optimizerswitches:=[cs_opt_level3,cs_opt_peephole];
  BuildTruth;
  for A:=Succ(C_None) to High(TAsmCond) do for B:=Succ(C_None) to High(TAsmCond) do begin
    Changed:=Probe('condition-'+cond2str[A]+'-'+cond2str[B],0,A,B);
    Valid:=(Truth[B] and not Truth[A])=0;
    Check(not Changed or Valid,'invalid implication '+cond2str[A]+' -> '+cond2str[B]);
    If A=B then Check(Changed,'equal condition '+cond2str[A]);
    Inc(MatrixCount);
    Inc(MatrixFolds,Ord(Changed));
  end;
  CaseProbe('straight-alias',0,True);
  CaseProbe('internal-join',1,True);
  CaseProbe('first-taken-entry',2,False);
  CaseProbe('external-entry',3,False);
  CaseProbe('future-backedge',4,False);
  CaseProbe('partial-write',5,False);
  CaseProbe('other-operand-write',6,False);
  CaseProbe('implicit-write',7,False);
  CaseProbe('opaque-between',8,False);
  CaseProbe('opaque-first-flags',9,False);
  CaseProbe('opaque-second-flags',10,False);
  CaseProbe('call',11,False);
  CaseProbe('unconditional',12,False);
  CaseProbe('other-flags',13,True);
  CaseProbe('fp-flags-join',15,True);
  CaseProbe('constant-operand',16,True);
  CaseProbe('different-width',17,False);
  CaseProbe('swapped-operands',18,False);
  CaseProbe('global-entry',19,False);
  CaseProbe('earlier-backedge',20,False);
  CaseProbe('asm-marker',21,False);
  CaseProbe('two-internal-refs',22,True);
  CaseProbe('memory-write-only',23,True);
  CaseProbe('public-entry',24,False);
  CaseProbe('unused-local-label',25,True);
  CaseProbe('offset-entry',26,False);
  CaseProbe('transparent-allocation',27,True);
  CaseProbe('first-offset-target',28,False);
  CaseProbe('jrcxz-barrier',29,False);
  CaseProbe('loop-barrier',30,False);
  Check(not Probe('no-first-condition',0,C_None,C_E),'no-first-condition');
  Check(not Probe('no-second-condition',0,C_E,C_None),'no-second-condition');
  WriteLn('CONDITION_MATRIX:',MatrixCount,':FOLDS:',MatrixFolds);
  current_procinfo.Free;
  If Failures<>0 then Halt(1);
  WriteLn('RELATION-IR:PASS');
end.
