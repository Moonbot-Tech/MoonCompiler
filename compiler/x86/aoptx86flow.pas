{
    x86 instruction USE/DEF and linear reaching-definition facts

    Copyright (c) 2026 by the MoonBot Compiler development team

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.
}
unit aoptx86flow;

{$i fpcdefs.inc}

interface

uses
  cclasses,
  cgbase,
  cpubase,
  aasmtai,aasmdata,aasmcpu,
  aoptx86;

type
  tx86regaccess = (xra_none,xra_use,xra_def,xra_usedef);

  tx86regfact = record
    reg : tregister;
    access : tx86regaccess;
    beforeversion,
    afterversion : longword;
  end;

  tx86regfactarray = array of tx86regfact;

  tx86insnflowview = record
    ebb : longword;
    regs : tx86regfactarray;
  end;

  tx86flowsummary = record
    blocks,
    instructions,
    usecount,
    defcount,
    usedefcount,
    reachinguses : longword;
  end;

  { F3a deliberately starts as a read-only service.  It owns the one x86
    instruction decoder used by future reaching-definition, address-GVN and
    verifier consumers.  Build never mutates the assembler list. }
  tx86flowfacts = class
  private
    fasm : tasmlist;
    fdecoder : tx86asmoptimizer;
    ffacts,
    fversions : tfplist;
    febb : longword;
    fgeneration : longword;
    fsummary : tx86flowsummary;
    procedure clearfacts;
    procedure resetblock;
    function versionentry(reg : tregister) : pointer;
    function currentversion(reg : tregister) : longword;
    function nextversion(reg : tregister) : longword;
    procedure buildinstruction(insn : taicpu; fullimplicit : boolean);
  public
    constructor create(asmlist : tasmlist);
    destructor destroy; override;
    procedure invalidate;
    procedure build(fullimplicit : boolean);
    function readfact(insn : tai; expectedgeneration : longword;
      out view : tx86insnflowview) : boolean;
    property generation : longword read fgeneration;
    property summary : tx86flowsummary read fsummary;
  end;

function x86regaccess(decoder : tx86asmoptimizer; reg : tregister;
  insn : taicpu) : tx86regaccess;

procedure x86flowobserve(asmlist : tasmlist; const procname : ansistring);
procedure x86flowstaleprobe(asmlist : tasmlist);

implementation

uses
  aopt,
  verbose;

type
  tx86registerarray = array of tregister;

  tx86insnflowfact = class
  public
    instruction : tai;
    ebb : longword;
    regs : tx86regfactarray;
  end;

  pregversion = ^tregversion;
  tregversion = record
    reg : tregister;
    version : longword;
  end;


function normalizedreg(reg : tregister) : tregister; inline;
  begin
    if reg=NR_NO then
      result:=NR_NO
    else
      result:=newreg(getregtype(reg),getsupreg(reg),R_SUBWHOLE);
  end;


function samereg(a,b : tregister) : boolean; inline;
  begin
    result:=(a<>NR_NO) and (b<>NR_NO) and
      (getregtype(a)=getregtype(b)) and (getsupreg(a)=getsupreg(b));
  end;


function x86regaccess(decoder : tx86asmoptimizer; reg : tregister;
  insn : taicpu) : tx86regaccess;
  var
    reads,writes : boolean;
  begin
    reads:=tx86asmoptimizer.RegReadByInstruction(reg,insn);
    writes:=decoder.RegModifiedByInstruction(reg,insn);
    if reads then
      if writes then
        result:=xra_usedef
      else
        result:=xra_use
    else if writes then
      result:=xra_def
    else
      result:=xra_none;
  end;


constructor tx86flowfacts.create(asmlist : tasmlist);
  begin
    inherited create;
    fasm:=asmlist;
    ffacts:=tfplist.create;
    fversions:=tfplist.create;
    { Use the target-owned concrete optimizer class.  TX86AsmOptimizer itself
      intentionally leaves target hooks abstract. }
    fdecoder:=tx86asmoptimizer(casmoptimizer.create(asmlist));
  end;


destructor tx86flowfacts.destroy;
  begin
    clearfacts;
    ffacts.free;
    fversions.free;
    fdecoder.free;
    inherited destroy;
  end;


procedure tx86flowfacts.clearfacts;
  var
    i : longint;
  begin
    for i:=0 to ffacts.count-1 do
      tx86insnflowfact(ffacts[i]).free;
    ffacts.clear;
    for i:=0 to fversions.count-1 do
      dispose(pregversion(fversions[i]));
    fversions.clear;
  end;


procedure tx86flowfacts.invalidate;
  begin
    clearfacts;
    inc(fgeneration);
    if fgeneration=0 then
      inc(fgeneration);
  end;


procedure tx86flowfacts.resetblock;
  var
    i : longint;
  begin
    for i:=0 to fversions.count-1 do
      dispose(pregversion(fversions[i]));
    fversions.clear;
    inc(febb);
  end;


function tx86flowfacts.versionentry(reg : tregister) : pointer;
  var
    i : longint;
    key : tregister;
    entry : pregversion;
  begin
    key:=normalizedreg(reg);
    for i:=0 to fversions.count-1 do
      begin
        entry:=pregversion(fversions[i]);
        if samereg(entry^.reg,key) then
          exit(entry);
      end;
    new(entry);
    entry^.reg:=key;
    entry^.version:=0;
    fversions.add(entry);
    result:=entry;
  end;


function tx86flowfacts.currentversion(reg : tregister) : longword;
  begin
    result:=pregversion(versionentry(reg))^.version;
  end;


function tx86flowfacts.nextversion(reg : tregister) : longword;
  var
    entry : pregversion;
  begin
    entry:=pregversion(versionentry(reg));
    inc(entry^.version);
    result:=entry^.version;
  end;


procedure addreg(var regs : tx86registerarray; var count : longint;
  reg : tregister);
  var
    i : longint;
  begin
    if reg=NR_NO then
      exit;
    reg:=normalizedreg(reg);
    for i:=0 to count-1 do
      if samereg(regs[i],reg) then
        exit;
    if count>=length(regs) then
      if count=0 then
        setlength(regs,32)
      else
        setlength(regs,count*2);
    regs[count]:=reg;
    inc(count);
  end;


procedure tx86flowfacts.buildinstruction(insn : taicpu;
  fullimplicit : boolean);
  var
    candidates : tx86registerarray;
    count,i,opidx,n : longint;
    ri : tregisterindex;
    fact : tx86insnflowfact;
    access : tx86regaccess;
  begin
    count:=0;
    for opidx:=0 to insn.ops-1 do
      case insn.oper[opidx]^.typ of
        top_reg:
          addreg(candidates,count,insn.oper[opidx]^.reg);
        top_ref:
          begin
            addreg(candidates,count,insn.oper[opidx]^.ref^.segment);
            addreg(candidates,count,insn.oper[opidx]^.ref^.base);
            addreg(candidates,count,insn.oper[opidx]^.ref^.index);
          end;
        else
          ;
      end;
    { Flags are an implicit operand of ordinary integer instructions. }
    addreg(candidates,count,NR_DEFAULTFLAGS);
    if fullimplicit then
      for ri:=low(tregisterindex) to high(tregisterindex) do
        addreg(candidates,count,regnumber_table[ri]);

    fact:=tx86insnflowfact.create;
    fact.instruction:=insn;
    fact.ebb:=febb;
    setlength(fact.regs,count);
    n:=0;
    for i:=0 to count-1 do
      begin
        access:=x86regaccess(fdecoder,candidates[i],insn);
        if access=xra_none then
          continue;
        fact.regs[n].reg:=candidates[i];
        fact.regs[n].access:=access;
        fact.regs[n].beforeversion:=currentversion(candidates[i]);
        if (access in [xra_use,xra_usedef]) and
           (fact.regs[n].beforeversion<>0) then
          inc(fsummary.reachinguses);
        if access in [xra_def,xra_usedef] then
          fact.regs[n].afterversion:=nextversion(candidates[i])
        else
          fact.regs[n].afterversion:=fact.regs[n].beforeversion;
        case access of
          xra_use:
            inc(fsummary.usecount);
          xra_def:
            inc(fsummary.defcount);
          xra_usedef:
            inc(fsummary.usedefcount);
          else
            ;
        end;
        inc(n);
      end;
    setlength(fact.regs,n);
    ffacts.add(fact);
    inc(fsummary.instructions);
  end;


procedure tx86flowfacts.build(fullimplicit : boolean);
  var
    p : tai;
    endsblock,
    newblock : boolean;
  begin
    invalidate;
    fillchar(fsummary,sizeof(fsummary),0);
    febb:=0;
    newblock:=true;
    p:=tai(fasm.first);
    while assigned(p) do
      begin
        if (p.typ=ait_label) or
           ((p.typ=ait_marker) and
            (tai_marker(p).kind in [mark_AsmBlockStart,mark_AsmBlockEnd])) then
          newblock:=true;
        endsblock:=false;
        if p.typ=ait_instruction then
          begin
            if newblock then
              begin
                resetblock;
                inc(fsummary.blocks);
                newblock:=false;
              end;
            buildinstruction(taicpu(p),fullimplicit);
            { Calls stay in the same EBB.  The current target decoder marks an
              opaque call as an all-register USE/DEF barrier. }
            endsblock:=
              (is_calljmp(taicpu(p).opcode) and
               (taicpu(p).opcode<>A_CALL)) or
              (taicpu(p).opcode=A_RET);
          end;
        if endsblock then
          newblock:=true;
        p:=tai(p.next);
      end;
  end;


function tx86flowfacts.readfact(insn : tai;
  expectedgeneration : longword; out view : tx86insnflowview) : boolean;
  var
    i : longint;
  begin
    if expectedgeneration<>fgeneration then
      begin
        writeln(stderr,'stale x86 machine facts: expected generation ',
          expectedgeneration,' but current generation is ',fgeneration);
        internalerror(2026082901);
      end;
    for i:=0 to ffacts.count-1 do
      if tx86insnflowfact(ffacts[i]).instruction=insn then
        begin
          view.ebb:=tx86insnflowfact(ffacts[i]).ebb;
          view.regs:=tx86insnflowfact(ffacts[i]).regs;
          exit(true);
        end;
    view.ebb:=0;
    setlength(view.regs,0);
    result:=false;
  end;


procedure x86flowobserve(asmlist : tasmlist; const procname : ansistring);
  var
    facts : tx86flowfacts;
    s : tx86flowsummary;
  begin
    facts:=tx86flowfacts.create(asmlist);
    try
      facts.build(true);
      s:=facts.summary;
      writeln(stderr,'m-facts-summary: proc=',procname,
        ' blocks=',s.blocks,
        ' insns=',s.instructions,
        ' use=',s.usecount,
        ' def=',s.defcount,
        ' usedef=',s.usedefcount,
        ' reaching=',s.reachinguses);
    finally
      facts.free;
    end;
  end;


procedure x86flowstaleprobe(asmlist : tasmlist);
  var
    facts : tx86flowfacts;
    p : tai;
    oldgeneration : longword;
    view : tx86insnflowview;
  begin
    p:=tai(asmlist.first);
    while assigned(p) and (p.typ<>ait_instruction) do
      p:=tai(p.next);
    if not assigned(p) then
      exit;
    facts:=tx86flowfacts.create(asmlist);
    try
      facts.build(false);
      oldgeneration:=facts.generation;
      facts.invalidate;
      { This call must terminate compilation through the generation guard. }
      facts.readfact(p,oldgeneration,view);
      internalerror(2026082902);
    finally
      facts.free;
    end;
  end;

end.
