{
    x86 pre-register-allocation element-address reuse

    Copyright (c) 2026 by the MoonBot Compiler development team

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.
}
unit aoptx86addr;

{$i fpcdefs.inc}
interface

uses
  aasmdata;

procedure x86reuseelementaddresses(asmlist : tasmlist);

implementation

uses
  cclasses,
  cgbase,cgutils,cgobj,
  cpubase,
  aasmtai,aasmcpu,
  aopt,aoptbase,
  aoptx86,aoptx86flow;

const
  minaddressuses = 3;

type
  tregstat = record
    usecount,
    defcount : longword;
  end;
  tregstatarray = array of tregstat;
  tregmarkarray = array of boolean;

  taddrkey = record
    ebb : longword;
    source : tregister;
    sourceversion : longword;
    move0size,
    move1size,
    andsize,
    move2size,
    shiftsize : topsize;
    andvalue,
    shiftvalue : int64;
  end;

  taddroccurrence = record
    chain : array[0..4] of taicpu;
    memoryinsn : taicpu;
    memoryop : byte;
    finalreg : tregister;
  end;

  taddrgroup = record
    key : taddrkey;
    occurrences : array of taddroccurrence;
  end;
  taddrgrouparray = array of taddrgroup;

  tbasekey = record
    ebb : longword;
    ref : treference;
  end;

  tbaseoccurrence = record
    lea,
    move : taicpu;
    memoryinsn : taicpu;
    memoryop : byte;
    finalreg : tregister;
  end;

  tbasegroup = record
    key : tbasekey;
    occurrences : array of tbaseoccurrence;
  end;
  tbasegrouparray = array of tbasegroup;


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


procedure ensurestat(var stats : tregstatarray; reg : tregister);
  var
    n : longword;
  begin
    if (reg=NR_NO) or (getregtype(reg)<>R_INTREGISTER) then
      exit;
    n:=getsupreg(reg);
    if n>=longword(length(stats)) then
      setlength(stats,n+64);
  end;


function factversion(const view : tx86insnflowview; reg : tregister;
  out version : longword) : boolean;
  var
    i : longint;
  begin
    for i:=0 to high(view.regs) do
      if samereg(view.regs[i].reg,reg) and
         (view.regs[i].access in [xra_use,xra_usedef]) then
        begin
          version:=view.regs[i].beforeversion;
          exit(true);
        end;
    version:=0;
    result:=false;
  end;


function previousinstruction(current : tai; out previous : taicpu) : boolean;
  var
    p : tai;
  begin
    result:=taoptbase.GetLastInstruction(current,p,[ait_label,ait_marker]);
    if result and (p.typ=ait_instruction) then
      previous:=taicpu(p)
    else
      begin
        previous:=nil;
        result:=false;
      end;
  end;


function registerisprivate(const stats : tregstatarray; reg : tregister;
  expecteduses,expecteddefs : longword) : boolean;
  var
    n : longword;
  begin
    n:=getsupreg(reg);
    result:=(getregtype(reg)=R_INTREGISTER) and
      (n>=first_int_imreg) and (n<longword(length(stats))) and
      (stats[n].usecount=expecteduses) and
      (stats[n].defcount=expecteddefs);
  end;


function flagsdeadafter(insn : taicpu; ebb : longword;
  facts : tx86flowfacts; decoder : tx86asmoptimizer) : boolean;
  var
    p : tai;
    view : tx86insnflowview;
    access : tx86regaccess;
  begin
    p:=insn;
    while taoptbase.GetNextInstruction(p,p,[ait_label,ait_marker]) do
      begin
        if (p.typ<>ait_instruction) or
           not facts.readfact(p,facts.generation,view) or
           (view.ebb<>ebb) then
          break;
        access:=x86regaccess(decoder,NR_DEFAULTFLAGS,taicpu(p));
        case access of
          xra_use,xra_usedef:
            exit(false);
          xra_def:
            exit(true);
          else
            ;
        end;
      end;
    result:=true;
  end;


function lastdefinitionbefore(insn : taicpu; reg : tregister;
  ebb : longword; facts : tx86flowfacts; decoder : tx86asmoptimizer;
  out definition : taicpu) : boolean;
  var
    p : tai;
    view : tx86insnflowview;
    access : tx86regaccess;
  begin
    p:=insn;
    while taoptbase.GetLastInstruction(p,p,[ait_label,ait_marker]) do
      begin
        if (p.typ<>ait_instruction) or
           not facts.readfact(p,facts.generation,view) or
           (view.ebb<>ebb) then
          break;
        access:=x86regaccess(decoder,reg,taicpu(p));
        if access in [xra_def,xra_usedef] then
          begin
            definition:=taicpu(p);
            exit(true);
          end;
        if access=xra_use then
          break;
      end;
    definition:=nil;
    result:=false;
  end;


function extractoccurrence(memoryinsn : taicpu; memoryop : byte;
  const stats : tregstatarray; facts : tx86flowfacts;
  decoder : tx86asmoptimizer; out key : taddrkey;
  out occurrence : taddroccurrence) : boolean;
  var
    p0,p1,p2,p3,p4 : taicpu;
    r1,r2,r3,source : tregister;
    view : tx86insnflowview;
  begin
    result:=false;
    r3:=memoryinsn.oper[memoryop]^.ref^.index;
    if r3=NR_NO then
      exit;
    if not facts.readfact(memoryinsn,facts.generation,view) then
      exit;
    if not lastdefinitionbefore(memoryinsn,r3,view.ebb,facts,decoder,p4) then
      exit;
    if
       (p4.opcode<>A_SHL) or (p4.ops<>2) or
       (p4.oper[0]^.typ<>top_const) or (p4.oper[1]^.typ<>top_reg) or
       not samereg(p4.oper[1]^.reg,r3) then
      exit;
    if not previousinstruction(p4,p3) or
       (p3.opcode<>A_MOV) or (p3.ops<>2) or
       (p3.oper[0]^.typ<>top_reg) or (p3.oper[1]^.typ<>top_reg) or
       not samereg(p3.oper[1]^.reg,r3) then
      exit;
    r2:=p3.oper[0]^.reg;
    if not previousinstruction(p3,p2) or
       (p2.opcode<>A_AND) or (p2.ops<>2) or
       (p2.oper[0]^.typ<>top_const) or (p2.oper[1]^.typ<>top_reg) or
       not samereg(p2.oper[1]^.reg,r2) then
      exit;
    if not previousinstruction(p2,p1) or
       (p1.opcode<>A_MOV) or (p1.ops<>2) or
       (p1.oper[0]^.typ<>top_reg) or (p1.oper[1]^.typ<>top_reg) or
       not samereg(p1.oper[1]^.reg,r2) then
      exit;
    r1:=p1.oper[0]^.reg;
    if not previousinstruction(p1,p0) or
       (p0.opcode<>A_MOV) or (p0.ops<>2) or
       (p0.oper[0]^.typ<>top_reg) or (p0.oper[1]^.typ<>top_reg) or
       not samereg(p0.oper[1]^.reg,r1) then
      exit;
    source:=p0.oper[0]^.reg;

    if not registerisprivate(stats,r1,1,1) or
       not registerisprivate(stats,r2,2,2) or
       not registerisprivate(stats,r3,2,2) then
      exit;
    if not facts.readfact(p0,facts.generation,view) or
       not factversion(view,source,key.sourceversion) then
      exit;
    key.ebb:=view.ebb;
    if not flagsdeadafter(p4,key.ebb,facts,decoder) then
      exit;

    key.source:=normalizedreg(source);
    key.move0size:=p0.opsize;
    key.move1size:=p1.opsize;
    key.andsize:=p2.opsize;
    key.move2size:=p3.opsize;
    key.shiftsize:=p4.opsize;
    key.andvalue:=p2.oper[0]^.val;
    key.shiftvalue:=p4.oper[0]^.val;
    occurrence.chain[0]:=p0;
    occurrence.chain[1]:=p1;
    occurrence.chain[2]:=p2;
    occurrence.chain[3]:=p3;
    occurrence.chain[4]:=p4;
    occurrence.memoryinsn:=memoryinsn;
    occurrence.memoryop:=memoryop;
    occurrence.finalreg:=r3;
    result:=true;
  end;


function samekey(const a,b : taddrkey) : boolean;
  begin
    result:=(a.ebb=b.ebb) and samereg(a.source,b.source) and
      (a.sourceversion=b.sourceversion) and
      (a.move0size=b.move0size) and (a.move1size=b.move1size) and
      (a.andsize=b.andsize) and (a.move2size=b.move2size) and
      (a.shiftsize=b.shiftsize) and (a.andvalue=b.andvalue) and
      (a.shiftvalue=b.shiftvalue);
  end;


procedure addoccurrence(var groups : taddrgrouparray; const key : taddrkey;
  const occurrence : taddroccurrence);
  var
    i,n : longint;
  begin
    for i:=0 to high(groups) do
      if samekey(groups[i].key,key) then
        begin
          n:=length(groups[i].occurrences);
          setlength(groups[i].occurrences,n+1);
          groups[i].occurrences[n]:=occurrence;
          exit;
        end;
    n:=length(groups);
    setlength(groups,n+1);
    groups[n].key:=key;
    setlength(groups[n].occurrences,1);
    groups[n].occurrences[0]:=occurrence;
  end;


function extractbaseoccurrence(memoryinsn : taicpu; memoryop : byte;
  const stats : tregstatarray; facts : tx86flowfacts;
  decoder : tx86asmoptimizer; out key : tbasekey;
  out occurrence : tbaseoccurrence) : boolean;
  var
    definition,lea,move : taicpu;
    source,finalreg : tregister;
    view : tx86insnflowview;
  begin
    result:=false;
    finalreg:=memoryinsn.oper[memoryop]^.ref^.base;
    if (finalreg=NR_NO) or
       not facts.readfact(memoryinsn,facts.generation,view) or
       not lastdefinitionbefore(memoryinsn,finalreg,view.ebb,facts,decoder,
         definition) then
      exit;
    move:=nil;
    if definition.opcode=A_LEA then
      begin
        lea:=definition;
        source:=finalreg;
        if not registerisprivate(stats,finalreg,1,1) then
          exit;
      end
    else if (definition.opcode=A_MOV) and (definition.ops=2) and
            (definition.oper[0]^.typ=top_reg) and
            (definition.oper[1]^.typ=top_reg) and
            samereg(definition.oper[1]^.reg,finalreg) then
      begin
        move:=definition;
        source:=move.oper[0]^.reg;
        if not lastdefinitionbefore(move,source,view.ebb,facts,decoder,lea) or
           not registerisprivate(stats,source,1,1) or
           not registerisprivate(stats,finalreg,1,1) then
          exit;
      end
    else
      exit;
    if
       (lea.opcode<>A_LEA) or (lea.ops<>2) or
       (lea.oper[0]^.typ<>top_ref) or (lea.oper[1]^.typ<>top_reg) or
       not samereg(lea.oper[1]^.reg,source) then
      exit;
    { v1 deliberately admits only a process-stable RIP-relative symbol.
      Heap/frame/TLS bases need their own versioned address identity. }
{$ifdef x86_64}
    if (lea.oper[0]^.ref^.symbol=nil) or
       (lea.oper[0]^.ref^.base<>NR_RIP) or
       (lea.oper[0]^.ref^.index<>NR_NO) or
       (lea.oper[0]^.ref^.segment<>NR_NO) or
       (lea.oper[0]^.ref^.volatility<>[]) then
      exit;
{$else x86_64}
    exit;
{$endif x86_64}
    key.ebb:=view.ebb;
    key.ref:=lea.oper[0]^.ref^;
    occurrence.lea:=lea;
    occurrence.move:=move;
    occurrence.memoryinsn:=memoryinsn;
    occurrence.memoryop:=memoryop;
    occurrence.finalreg:=finalreg;
    result:=true;
  end;


function samebasekey(const a,b : tbasekey) : boolean;
  begin
    result:=(a.ebb=b.ebb) and refsequal(a.ref,b.ref);
  end;


procedure addbaseoccurrence(var groups : tbasegrouparray;
  const key : tbasekey; const occurrence : tbaseoccurrence);
  var
    i,n : longint;
  begin
    for i:=0 to high(groups) do
      if samebasekey(groups[i].key,key) then
        begin
          n:=length(groups[i].occurrences);
          setlength(groups[i].occurrences,n+1);
          groups[i].occurrences[n]:=occurrence;
          exit;
        end;
    n:=length(groups);
    setlength(groups,n+1);
    groups[n].key:=key;
    setlength(groups[n].occurrences,1);
    groups[n].occurrences[0]:=occurrence;
  end;


procedure markreg(var marked : tregmarkarray; reg : tregister);
  var
    n : longword;
  begin
    if (reg=NR_NO) or (getregtype(reg)<>R_INTREGISTER) then
      exit;
    n:=getsupreg(reg);
    if n<first_int_imreg then
      exit;
    if n>=longword(length(marked)) then
      setlength(marked,n+64);
    marked[n]:=true;
  end;


procedure markinstructionregs(var marked : tregmarkarray; insn : taicpu;
  facts : tx86flowfacts);
  var
    i : longint;
    view : tx86insnflowview;
  begin
    if facts.readfact(insn,facts.generation,view) then
      for i:=0 to high(view.regs) do
        markreg(marked,view.regs[i].reg);
  end;


procedure collectaffectedregs(var marked : tregmarkarray;
  const groups : taddrgrouparray; const basegroups : tbasegrouparray;
  facts : tx86flowfacts);
  var
    i,j,k : longint;
  begin
    for i:=0 to high(groups) do
      if length(groups[i].occurrences)>=minaddressuses then
        begin
          markreg(marked,groups[i].occurrences[0].finalreg);
          for j:=1 to high(groups[i].occurrences) do
            for k:=0 to 4 do
              markinstructionregs(marked,
                groups[i].occurrences[j].chain[k],facts);
        end;
    for i:=0 to high(basegroups) do
      if length(basegroups[i].occurrences)>=minaddressuses then
        begin
          markreg(marked,basegroups[i].occurrences[0].finalreg);
          for j:=1 to high(basegroups[i].occurrences) do
            begin
              markinstructionregs(marked,
                basegroups[i].occurrences[j].lea,facts);
              if assigned(basegroups[i].occurrences[j].move) then
                markinstructionregs(marked,
                  basegroups[i].occurrences[j].move,facts);
            end;
        end;
  end;


procedure rebuildliveranges(asmlist : tasmlist; const marked : tregmarkarray;
  facts : tx86flowfacts);
  var
    i : longint;
    n : longword;
    p : tai;
    view : tx86insnflowview;
  begin
    if length(marked)<=first_int_imreg then
      exit;
    { Code generation has already recorded live-range endpoints.  Some of
      those endpoints are the private instructions removed by this pass, so
      rebuild exactly the affected ranges before register allocation. }
    for n:=first_int_imreg to high(marked) do
      if marked[n] then
        begin
          cg.rg[R_INTREGISTER].live_start[n]:=nil;
          cg.rg[R_INTREGISTER].live_end[n]:=nil;
        end;
    p:=tai(asmlist.first);
    while assigned(p) do
      begin
        if (p.typ=ait_instruction) and
           facts.readfact(p,facts.generation,view) then
          for i:=0 to high(view.regs) do
            if (getregtype(view.regs[i].reg)=R_INTREGISTER) then
              begin
                n:=getsupreg(view.regs[i].reg);
                if (n<longword(length(marked))) and marked[n] then
                  begin
                    if not assigned(cg.rg[R_INTREGISTER].live_start[n]) then
                      cg.rg[R_INTREGISTER].live_start[n]:=p;
                    cg.rg[R_INTREGISTER].live_end[n]:=p;
                  end;
              end;
        p:=tai(p.next);
      end;
  end;


procedure removechain(asmlist : tasmlist; const occurrence : taddroccurrence);
  var
    i : longint;
  begin
    for i:=0 to 4 do
      begin
        asmlist.remove(occurrence.chain[i]);
        occurrence.chain[i].free;
      end;
  end;


procedure removebasechain(asmlist : tasmlist;
  const occurrence : tbaseoccurrence);
  begin
    asmlist.remove(occurrence.lea);
    occurrence.lea.free;
    if assigned(occurrence.move) then
      begin
        asmlist.remove(occurrence.move);
        occurrence.move.free;
      end;
  end;


procedure applygroups(asmlist : tasmlist; const groups : taddrgrouparray);
  var
    i,j : longint;
    keepreg : tregister;
    ref : preference;
  begin
    for i:=0 to high(groups) do
      if length(groups[i].occurrences)>=minaddressuses then
        begin
          keepreg:=groups[i].occurrences[0].finalreg;
          for j:=1 to high(groups[i].occurrences) do
            begin
              ref:=groups[i].occurrences[j].memoryinsn.oper[
                groups[i].occurrences[j].memoryop]^.ref;
              ref^.index:=keepreg;
              removechain(asmlist,groups[i].occurrences[j]);
            end;
        end;
  end;


procedure applybasegroups(asmlist : tasmlist; const groups : tbasegrouparray);
  var
    i,j : longint;
    keepreg : tregister;
    ref : preference;
  begin
    for i:=0 to high(groups) do
      if length(groups[i].occurrences)>=minaddressuses then
        begin
          keepreg:=groups[i].occurrences[0].finalreg;
          for j:=1 to high(groups[i].occurrences) do
            begin
              ref:=groups[i].occurrences[j].memoryinsn.oper[
                groups[i].occurrences[j].memoryop]^.ref;
              ref^.base:=keepreg;
              removebasechain(asmlist,groups[i].occurrences[j]);
            end;
        end;
  end;


procedure x86reuseelementaddresses(asmlist : tasmlist);
  var
    facts : tx86flowfacts;
    decoder : tx86asmoptimizer;
    stats : tregstatarray;
    groups : taddrgrouparray;
    basegroups : tbasegrouparray;
    marked : tregmarkarray;
    p : tai;
    insn : taicpu;
    view : tx86insnflowview;
    key : taddrkey;
    basekey : tbasekey;
    occurrence : taddroccurrence;
    baseoccurrence : tbaseoccurrence;
    i,j : longint;
  begin
    facts:=tx86flowfacts.create(asmlist);
    decoder:=tx86asmoptimizer(casmoptimizer.create(asmlist));
    try
      facts.build(false);
      p:=tai(asmlist.first);
      while assigned(p) do
        begin
          if (p.typ=ait_instruction) and
             facts.readfact(p,facts.generation,view) then
            for i:=0 to high(view.regs) do
              if getregtype(view.regs[i].reg)=R_INTREGISTER then
                begin
                  ensurestat(stats,view.regs[i].reg);
                  j:=getsupreg(view.regs[i].reg);
                  if view.regs[i].access in [xra_use,xra_usedef] then
                    inc(stats[j].usecount);
                  if view.regs[i].access in [xra_def,xra_usedef] then
                    inc(stats[j].defcount);
                end;
          p:=tai(p.next);
        end;

      p:=tai(asmlist.first);
      while assigned(p) do
        begin
          if p.typ=ait_instruction then
            begin
              insn:=taicpu(p);
              for i:=0 to insn.ops-1 do
                if insn.oper[i]^.typ=top_ref then
                  begin
                    if extractoccurrence(insn,i,stats,facts,decoder,key,occurrence) then
                      addoccurrence(groups,key,occurrence);
                    if extractbaseoccurrence(insn,i,stats,facts,decoder,
                        basekey,baseoccurrence) then
                      addbaseoccurrence(basegroups,basekey,baseoccurrence);
                  end;
            end;
          p:=tai(p.next);
        end;
      collectaffectedregs(marked,groups,basegroups,facts);
      facts.invalidate;
      applygroups(asmlist,groups);
      applybasegroups(asmlist,basegroups);
      facts.build(false);
      rebuildliveranges(asmlist,marked,facts);
      facts.invalidate;
    finally
      decoder.free;
      facts.free;
    end;
  end;

end.
