program value_forward_ir;
{$mode objfpc}
uses SysUtils, cclasses, procinfo, cgbase, cgutils, globtype, globals, cpubase, aasmbase, aasmtai, aasmcpu, aasmdata, aoptobj, aoptcpu;
type
  TProbeProc = class(tprocinfo)
    constructor Create(ParentInfo: tprocinfo); override;
  end;
  TProbe = class(TCpuAsmOptimizer)
    function Run(var P: tai): Boolean;
    function RunSymbol(var P: tai): Boolean;
    function RunCopy(var P: tai): Boolean;
    function RunLea(var P: tai): Boolean;
  end;
var Failures, I: Integer;
constructor TProbeProc.Create(ParentInfo: tprocinfo);
begin
  framepointer:=NR_FRAME_POINTER_REG;
end;
function TProbe.Run(var P: tai): Boolean;
begin
  Result:=OptPass1MOV(P);
end;
function TProbe.RunSymbol(var P: tai): Boolean;
begin
  Result:=TrySymbolAddressToOperands(P);
end;
function TProbe.RunCopy(var P: tai): Boolean;
begin
  Result:=OptPass2MOV(P);
end;
function TProbe.RunLea(var P: tai): Boolean;
begin
  Result:=OptPass1LEA(P);
end;
procedure Check(Ok: Boolean; const Name: string);

begin
  If not Ok then begin
    WriteLn('FAIL:',Name);
    Inc(Failures);
  end;
end;
procedure HighByteProbe(const Name:string; Source,Expected:TRegister; Kind:Integer);
var L:TAsmList; O:TProbe; P:tai; Reader:taicpu; Ref:TReference;
begin
  L:=TAsmList.Create;
  L.Concat(taicpu.op_const_reg(A_MOV,S_L,$1234,Source));
  P:=taicpu.op_reg_reg(A_MOV,S_L,Source,NR_EAX);
  L.Concat(P);
  Reader:=taicpu.op_reg_reg(A_MOVZX,S_BL,NR_AH,NR_EDX);
  If Kind=1 then begin
    Reader.Free;
    reference_reset(Ref,1,[]);
    Ref.base:=NR_RAX;
    Reader:=taicpu.op_reg_ref(A_MOV,S_B,NR_AH,Ref);
  end else If Kind=2 then begin
    Reader.Free;
    Reader:=taicpu.op_reg_reg(A_MOV,S_B,NR_AL,NR_BH);
  end;
  L.Concat(Reader);
  L.Concat(tai_regalloc.DeAlloc(NR_RAX,nil));
  L.Concat(taicpu.op_none(A_RET,S_NO));
  O:=TProbe.Create(L);
  O.IncludeRegInUsedRegs(Source,O.UsedRegs);
  O.IncludeRegInUsedRegs(NR_RAX,O.UsedRegs);
  O.Run(P);
  Check(Reader.oper[0]^.reg=Expected,Name+' register');
  If Kind=1 then Check(Reader.oper[1]^.ref^.base=NR_RAX,Name+' no new REX in address');
  WriteLn(Name,':encoding-check');
  O.Free;
  L.Free;
end;
procedure SymbolProbe(const Name:string; Kind, UsesCount:Integer; Want:Boolean);
var L:TAsmList; O:TProbe; P:tai; Ref,Src:TReference; I:Integer;
    Symbols:TFPHashObjectList; Sym:TAsmSymbol; Reader:taicpu; Reads:array[0..7] of taicpu;
begin
  L:=TAsmList.Create;
  Symbols:=TFPHashObjectList.Create(true);
  Sym:=TAsmSymbol.Create(Symbols,'data',AB_LOCAL,AT_DATA);
  reference_reset(Src,8,[]);
  Src.symbol:=Sym;
  Src.refaddr:=addr_full;
  Src.offset:=17;
  If Kind=13 then Src.offset:=Low(Int64);
  If Kind=15 then Src.offset:=-$3fffffff;
  If Kind=16 then Src.offset:=$3fffffff;
  If Kind=2 then begin
    Src.base:=NR_RIP;
    Src.refaddr:=addr_no;
    P:=taicpu.op_ref_reg(A_LEA,S_Q,Src,NR_RAX);
  end else P:=taicpu.op_ref_reg(A_MOV,S_Q,Src,NR_RAX);
  L.Concat(P);
  For I:=0 to UsesCount-1 do begin
    reference_reset(Ref,4,[]);
    Ref.base:=NR_RAX;
    Ref.index:=NR_RDX;
    Ref.scalefactor:=4;
    If Kind=1 then Ref.index:=NR_NO;
    If Kind=3 then Ref.index:=NR_RAX;
    If Kind=4 then Ref.volatility:=[vol_read];
    If Kind=5 then Ref.symbol:=Sym;
    If Kind=6 then Ref.segment:=NR_FS;
    If Kind=7 then Ref.offset:=$40000000;
    If Kind=8 then Ref.offset:=32;
    If Kind=9 then Ref.offset:=1024;
    If Kind=14 then Ref.offset:=Low(Int64);
    If Kind=15 then Ref.offset:=-$3fffffff;
    If Kind=16 then Ref.offset:=$3fffffff;
    Reader:=taicpu.op_ref_reg(A_MOV,S_L,Ref,NR_R10D);
    Reads[I]:=Reader;
    L.Concat(Reader);
    If Kind=10 then L.Concat(taicpu.op_reg(A_CALL,S_NO,NR_R11));
  end;
  If Kind=11 then L.Concat(taicpu.op_reg_reg(A_MOV,S_Q,NR_RAX,NR_R11));
  L.Concat(tai_regalloc.DeAlloc(NR_RAX,nil));
  L.Concat(taicpu.op_none(A_RET,S_NO));
  O:=TProbe.Create(L);
  O.IncludeRegInUsedRegs(NR_RAX,O.UsedRegs);
  O.IncludeRegInUsedRegs(NR_RDX,O.UsedRegs);
  If Kind=12 then Include(current_settings.moduleswitches,cs_create_pic);
  Check(O.RunSymbol(P)=Want,Name+' transformed');
  Exclude(current_settings.moduleswitches,cs_create_pic);
  If Want then For I:=0 to UsesCount-1 do begin
    Check(Reads[I].oper[0]^.ref^.base=NR_NO,Name+' base removed');
    Check(Reads[I].oper[0]^.ref^.symbol=Sym,Name+' symbol');
    Check(Reads[I].oper[0]^.ref^.offset=Src.offset+Ref.offset,Name+' offset');
  end;
  WriteLn(Name,':address-check');
  O.Free;
  L.Free;
  Symbols.Free;
end;
procedure Probe(const Name: string; BeforeKind, AfterKind: Integer; Want: Boolean);
var
  L: TAsmList;
  O: TProbe;
  P: tai;
  CopyIns, Reader, SecondReader, Ins: taicpu;
  Ref: TReference;
  Symbols: TFPHashObjectList;
  Target: TAsmLabel;
  Changed: Boolean;
begin
  L:=TAsmList.Create;
  Symbols:=TFPHashObjectList.Create(true);
  Target:=TAsmLabel.CreateLocal(Symbols,1,alt_jump);
  If (BeforeKind=4) or (AfterKind=4) then Target.IncRefs;
  case BeforeKind of
    0: L.Concat(taicpu.op_const_reg(A_MOV,S_L,7,NR_EAX));
    1: L.Concat(taicpu.op_const_reg(A_MOV,S_Q,$100000007,NR_RAX));
    2: L.Concat(taicpu.op_const_reg(A_MOV,S_W,7,NR_AX));
    3: begin
      L.Concat(taicpu.op_const_reg(A_MOV,S_L,7,NR_EAX));
      L.Concat(taicpu.op_const_reg(A_MOV,S_B,1,NR_AH));
    end;
    4: begin
      L.Concat(taicpu.op_const_reg(A_MOV,S_L,7,NR_EAX));
      L.Concat(tai_label.Create(Target));
    end;
    5: begin
      L.Concat(taicpu.op_const_reg(A_MOV,S_L,7,NR_EAX));
      L.Concat(taicpu.op_reg(A_CALL,S_NO,NR_R11));
    end;
    6: begin
      L.Concat(taicpu.op_const_reg(A_MOV,S_L,7,NR_EAX));
      L.Concat(tai_marker.Create(mark_NoPropInfoStart));
    end;
    7: begin
      Ins:=taicpu.op_reg_reg(A_CMOVcc,S_L,NR_EDX,NR_EAX);
      Ins.SetCondition(C_E);
      L.Concat(Ins);
    end;
    8: L.Concat(taicpu.op_reg_reg(A_SHL,S_L,NR_CL,NR_EAX));
    9: begin
      L.Concat(taicpu.op_const_reg(A_MOV,S_L,7,NR_EAX));
      L.Concat(tai_regalloc.DeAlloc(NR_RAX,nil));
      L.Concat(tai_regalloc.Alloc(NR_RAX,nil));
    end;
  end;
  CopyIns:=taicpu.op_reg_reg(A_MOV,S_L,NR_EAX,NR_EDX);
  L.Concat(CopyIns);
  case AfterKind of
    1: L.Concat(taicpu.op_const_reg(A_MOV,S_B,2,NR_AL));
    2: L.Concat(taicpu.op_const_reg(A_MOV,S_Q,$100000007,NR_RAX));
    3: L.Concat(taicpu.op_reg(A_CALL,S_NO,NR_R11));
    4: L.Concat(tai_label.Create(Target));
    5: L.Concat(tai_marker.Create(mark_NoPropInfoStart));
    6: L.Concat(taicpu.op_const_reg(A_MOV,S_B,1,NR_DL));
    7: begin
      Ins:=taicpu.op_cond_sym(A_Jcc,C_E,S_NO,Target);
      Ins.is_jmp:=true;
      L.Concat(Ins);
    end;
  end;
  reference_reset(Ref,8,[]);
  Ref.base:=NR_RDI;
  Ref.index:=NR_RDX;
  Ref.scalefactor:=4;
  Reader:=taicpu.op_ref_reg(A_MOV,S_L,Ref,NR_R8D);
  L.Concat(Reader);
  SecondReader:=nil;
  If AfterKind=8 then begin
    L.Concat(taicpu.op_const_reg(A_MOV,S_B,2,NR_AL));
    SecondReader:=taicpu.op_ref_reg(A_MOV,S_L,Ref,NR_R9D);
    L.Concat(SecondReader);
  end;
  L.Concat(tai_regalloc.DeAlloc(NR_RDX,nil));
  L.Concat(taicpu.op_none(A_RET,S_NO));
  If AfterKind=7 then begin
    L.Concat(tai_label.Create(Target));
    L.Concat(taicpu.op_reg_reg(A_MOV,S_Q,NR_RDX,NR_R8));
    L.Concat(taicpu.op_none(A_RET,S_NO));
  end;
  O:=TProbe.Create(L);
  O.IncludeRegInUsedRegs(NR_RAX,O.UsedRegs);
  O.IncludeRegInUsedRegs(NR_RDX,O.UsedRegs);
  O.IncludeRegInUsedRegs(NR_RDI,O.UsedRegs);
  P:=CopyIns;
  Changed:=O.Run(P);
  Check((Reader.oper[0]^.ref^.index=NR_RAX)=Want,Name+' index');
  If Assigned(SecondReader) then
    Check(SecondReader.oper[0]^.ref^.index=NR_RDX,Name+' changed source stops later forwarding');
  WriteLn(Name,':changed=',Changed,':forwarded=',Reader.oper[0]^.ref^.index=NR_RAX);
  O.Free;
  L.Free;
  Symbols.Free;
end;
procedure GlobalForwardProbe(Kind: Integer; Want: Boolean);
var L:TAsmList; O:TProbe; P:tai; Reader:taicpu; Ref,Other:TReference;
    Symbols:TFPHashObjectList; Sym,OtherSym:TAsmSymbol; I:Integer;
begin
  L:=TAsmList.Create;
  Symbols:=TFPHashObjectList.Create(true);
  Sym:=TAsmSymbol.Create(Symbols,'global_a',AB_LOCAL,AT_DATA);
  OtherSym:=TAsmSymbol.Create(Symbols,'global_b',AB_LOCAL,AT_DATA);
  L.Concat(taicpu.op_const_reg(A_MOV,S_L,7,NR_EDX));
  If Kind=1 then L.Concat(taicpu.op_const_reg(A_MOV,S_Q,$100000007,NR_RDX));
  L.Concat(taicpu.op_reg_reg(A_MOV,S_L,NR_EDX,NR_R8D));
  reference_reset(Ref,4,[]);
  Ref.symbol:=Sym;
  Ref.base:=NR_RIP;
  L.Concat(taicpu.op_ref_reg(A_LEA,S_Q,Ref,NR_RSI));
  Ref.symbol:=nil;
  Ref.base:=NR_RSI;
  Ref.index:=NR_RDX;
  Ref.scalefactor:=4;
  P:=taicpu.op_reg_ref(A_MOV,S_L,NR_ECX,Ref);
  L.Concat(P);
  reference_reset(Other,4,[]);
  Other.symbol:=Sym;
  If Kind in [2,3] then Other.symbol:=OtherSym;
  Other.base:=NR_RIP;
  L.Concat(taicpu.op_ref_reg(A_LEA,S_Q,Other,NR_RDI));
  If Kind=3 then L.Concat(taicpu.op_ref_reg(A_LEA,S_Q,Other,NR_RSI));
  If Kind=4 then L.Concat(taicpu.op_const_reg(A_MOV,S_B,1,NR_R8L));
  If Kind=5 then L.Concat(taicpu.op_reg(A_CALL,S_NO,NR_R11));
  If Kind=6 then L.Concat(taicpu.op_reg_ref(A_MOV,S_L,NR_EAX,Ref));
  If Kind=7 then L.Concat(taicpu.op_const_reg(A_MOV,S_L,1,NR_ECX));
  If Kind=8 then For I:=1 to 18 do L.Concat(taicpu.op_none(A_NOP,S_NO));
  If Kind in [13,14] then begin
    Other.symbol:=OtherSym;
    If Kind=13 then Other.volatility:=[vol_read];
    L.Concat(taicpu.op_ref_reg(A_MOV,S_L,Other,NR_EAX));
  end;
  If Kind=15 then L.Concat(taicpu.op_none(A_MFENCE,S_NO));
  Ref.base:=NR_RDI;
  Ref.index:=NR_R8;
  If Kind=3 then begin Ref.base:=NR_RSI; Ref.index:=NR_RDX; end;
  If Kind=9 then Ref.offset:=4;
  If Kind=10 then Ref.scalefactor:=8;
  If Kind=11 then Ref.volatility:=[vol_read];
  If Kind=12 then Ref.segment:=NR_FS;
  Reader:=taicpu.op_ref_reg(A_MOV,S_L,Ref,NR_R10D);
  L.Concat(Reader);
  L.Concat(taicpu.op_none(A_RET,S_NO));
  O:=TProbe.Create(L);
  O.IncludeRegInUsedRegs(NR_RCX,O.UsedRegs);
O.IncludeRegInUsedRegs(NR_RDX,O.UsedRegs);
O.IncludeRegInUsedRegs(NR_R8,O.UsedRegs);
O.IncludeRegInUsedRegs(NR_RSI,O.UsedRegs);
O.IncludeRegInUsedRegs(NR_RDI,O.UsedRegs);
  O.Run(P);
  Check((Reader.oper[0]^.typ=top_reg)=Want,'global-forward '+IntToStr(Kind));
  O.Free;
  L.Free;
  Symbols.Free;
end;
procedure SymbolReuseProbe(Kind:Integer; Want:Boolean);
var L:TAsmList; O:TProbe; P:tai; Reader:taicpu; Ref:TReference;
    Symbols:TFPHashObjectList; Sym:TAsmSymbol; Target:TAsmLabel; I:Integer;
begin
  L:=TAsmList.Create;
  Symbols:=TFPHashObjectList.Create(true);
  Sym:=TAsmSymbol.Create(Symbols,'data',AB_LOCAL,AT_DATA);
  Target:=TAsmLabel.CreateLocal(Symbols,1,alt_jump);
  Target.IncRefs;
  reference_reset(Ref,8,[]);
  Ref.symbol:=Sym;
  Ref.base:=NR_RIP;
  If Kind=4 then Ref.volatility:=[vol_read];
  If Kind=5 then Ref.index:=NR_RDX;
  P:=taicpu.op_ref_reg(A_LEA,S_Q,Ref,NR_RSI);
  L.Concat(P);
  case Kind of
    1: L.Concat(taicpu.op_const_reg(A_MOV,S_L,1,NR_ESI));
    2: L.Concat(taicpu.op_reg(A_CALL,S_NO,NR_R11));
    3: L.Concat(tai_label.Create(Target));
    6: Inc(Ref.offset);
    7: For I:=1 to 8 do L.Concat(taicpu.op_none(A_NOP,S_NO));
    8: Exclude(current_settings.optimizerswitches,cs_opt_level3);
  end;
  Reader:=taicpu.op_ref_reg(A_LEA,S_Q,Ref,NR_RDI);
  L.Concat(Reader);
  L.Concat(taicpu.op_reg_reg(A_ADD,S_Q,NR_RDI,NR_RAX));
  L.Concat(taicpu.op_none(A_RET,S_NO));
  O:=TProbe.Create(L);
  O.IncludeRegInUsedRegs(NR_RSI,O.UsedRegs);
  O.IncludeRegInUsedRegs(NR_RDI,O.UsedRegs);
  O.RunLea(P);
  Check((Reader.opcode=A_MOV)=Want,'symbol-reuse '+IntToStr(Kind));
  Include(current_settings.optimizerswitches,cs_opt_level3);
  O.Free;
  L.Free;
  Symbols.Free;
end;
procedure DeadCopyProbe(Kind:Integer; Want:Boolean);
var L:TAsmList; O:TProbe; P,CopyIns,LabelIns,HeadIns:tai; Ref:TReference;
    Symbols:TFPHashObjectList; Target:TAsmLabel; I:Integer; StillThere:Boolean;
begin
  L:=TAsmList.Create;
  Symbols:=TFPHashObjectList.Create(true);
  Target:=TAsmLabel.CreateLocal(Symbols,1,alt_jump);
  Target.IncRefs;
  LabelIns:=tai_label.Create(Target);
  HeadIns:=nil;
  If Kind in [12,13] then begin
    HeadIns:=tai_label.Create(Target);
    L.Concat(HeadIns);
  end;
  CopyIns:=taicpu.op_reg_reg(A_MOV,S_L,NR_R9D,NR_EBX);
  taicpu(CopyIns).forwarded_memory_load:=Kind<>11;
  L.Concat(CopyIns);
  L.Concat(taicpu.op_none(A_NOP,S_NO));
  case Kind of
    1: L.Concat(taicpu.op_reg_reg(A_ADD,S_L,NR_EBX,NR_EAX));
    2,3,4: L.Concat(taicpu.op_cond_sym(A_Jcc,C_E,S_NO,Target));
    5: L.Concat(taicpu.op_reg(A_CALL,S_NO,NR_R11));
    6: begin
      L.Concat(taicpu.op_const_reg(A_MOV,S_B,1,NR_BL));
      L.Concat(taicpu.op_reg_reg(A_ADD,S_L,NR_EBX,NR_EAX));
    end;
    7: L.Concat(tai_marker.Create(mark_NoPropInfoStart));
    8: For I:=1 to 65 do L.Concat(taicpu.op_none(A_NOP,S_NO));
    9: Include(current_procinfo.flags,pi_uses_exceptions);
    10: begin
      reference_reset(Ref,4,[]);
      Ref.base:=NR_RBX;
      L.Concat(taicpu.op_ref_reg(A_MOV,S_L,Ref,NR_EAX));
    end;
    12,13: begin
      If Kind=13 then L.Concat(taicpu.op_reg_reg(A_ADD,S_L,NR_EBX,NR_EAX));
      L.Concat(taicpu.op_cond_sym(A_Jcc,C_E,S_NO,Target));
    end;
    14: begin
      L.Concat(taicpu.op_const_reg(A_MOV,S_B,1,NR_BH));
      L.Concat(taicpu.op_reg_reg(A_ADD,S_L,NR_EBX,NR_EAX));
    end;
    15: begin
      taicpu(CopyIns).loadreg(1,NR_EAX);
    end;
  end;
  If Kind=3 then L.Concat(taicpu.op_reg_reg(A_ADD,S_L,NR_EBX,NR_EAX));
  L.Concat(taicpu.op_reg(A_POP,S_Q,NR_RBX));
  L.Concat(taicpu.op_none(A_RET,S_NO));
  If Assigned(HeadIns) then LabelIns.Free else L.Concat(LabelIns);
  If Kind=2 then L.Concat(taicpu.op_reg_reg(A_ADD,S_L,NR_EBX,NR_EAX));
  L.Concat(taicpu.op_reg(A_POP,S_Q,NR_RBX));
  L.Concat(taicpu.op_none(A_RET,S_NO));
  O:=TProbe.Create(L);
  O.IncludeRegInUsedRegs(NR_RBX,O.UsedRegs);
  O.IncludeRegInUsedRegs(NR_R9,O.UsedRegs);
  O.LabelInfo^.LowLabel:=Target.labelnr;
  O.LabelInfo^.HighLabel:=Target.labelnr;
  O.LabelInfo^.LabelDif:=1;
  SetLength(O.LabelInfo^.LabelTable,1);
  If Assigned(HeadIns) then O.LabelInfo^.LabelTable[0].PaiObj:=HeadIns
  else O.LabelInfo^.LabelTable[0].PaiObj:=LabelIns;
  P:=CopyIns;
  O.RunCopy(P);
  StillThere:=False;
  P:=tai(L.First);
  while Assigned(P) do begin
    If P=CopyIns then StillThere:=True;
    P:=tai(P.Next);
  end;
  Check(StillThere<>Want,'forwarded-copy '+IntToStr(Kind));
  Exclude(current_procinfo.flags,pi_uses_exceptions);
  O.Free;
  L.Free;
  Symbols.Free;
end;
begin
  current_procinfo:=TProbeProc.Create(nil);
  current_settings.optimizerswitches:=[cs_opt_level3,cs_opt_peephole];
  Probe('known32',0,0,true);
  Probe('unknown64',1,0,false);
  Probe('unknown16',2,0,false);
  Probe('partial-before',3,0,false);
  Probe('label-before',4,0,false);
  Probe('call-before',5,0,false);
  Probe('opaque-before',6,0,false);
  Probe('conditional-before',7,0,false);
  Probe('shift-before',8,0,true);
  Probe('metadata-before',9,0,true);
  Probe('source-low-change',0,1,false);
  Probe('source-full-change',0,2,false);
  Probe('call-after',0,3,false);
  Probe('label-after',0,4,false);
  Probe('opaque-after',0,5,false);
  Probe('target-low-change',0,6,false);
  Probe('taken-use',0,7,false);
  Probe('two-read-source-change',0,8,true);
  HighByteProbe('extended-high-byte',NR_R8D,NR_AH,0);
  HighByteProbe('missing-high-byte',NR_ESI,NR_AH,0);
  HighByteProbe('legal-high-byte',NR_EBX,NR_BH,0);
  HighByteProbe('high-byte-address',NR_R8D,NR_AH,1);
  HighByteProbe('high-byte-other-operand',NR_ESI,NR_AL,2);
  SymbolProbe('absolute-index',0,2,true);
  SymbolProbe('absolute-noindex',1,2,true);
  SymbolProbe('rip-index',2,2,false);
  SymbolProbe('same-base-index',3,2,false);
  SymbolProbe('volatile',4,2,false);
  SymbolProbe('existing-symbol',5,2,false);
  SymbolProbe('segment',6,2,false);
  SymbolProbe('offset-overflow',7,2,false);
  SymbolProbe('budget-small-offset',8,3,true);
  SymbolProbe('budget-large-offset',9,8,true);
  SymbolProbe('budget-overrun',0,3,false);
  SymbolProbe('intervening-call',10,2,false);
  SymbolProbe('base-still-read',11,2,false);
  SymbolProbe('pic',12,2,false);
  SymbolProbe('min-source-offset',13,2,false);
  SymbolProbe('min-target-offset',14,2,false);
  SymbolProbe('negative-offset-boundary',15,2,true);
  SymbolProbe('positive-offset-boundary',16,2,true);
  GlobalForwardProbe(0,true);
  For I:=1 to 12 do GlobalForwardProbe(I,false);
  GlobalForwardProbe(13,false);
  GlobalForwardProbe(14,true);
  GlobalForwardProbe(15,false);
  SymbolReuseProbe(0,true);
  For I:=1 to 8 do SymbolReuseProbe(I,false);
  DeadCopyProbe(0,true);
  DeadCopyProbe(4,true);
  DeadCopyProbe(12,true);
  For I:=1 to 11 do If I<>4 then DeadCopyProbe(I,false);
  For I:=13 to 15 do DeadCopyProbe(I,false);
  current_procinfo.Free;
  If Failures<>0 then Halt(1);
  WriteLn('VALUE-FORWARD-IR:PASS');
end.
