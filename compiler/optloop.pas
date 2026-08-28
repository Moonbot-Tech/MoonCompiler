{
    Loop optimization

    Copyright (c) 2005 by Florian Klaempfl

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
unit optloop;

{$i fpcdefs.inc}

{ $define DEBUG_OPTSTRENGTH}
{ $define DEBUG_OPTFORLOOP}

  interface

    uses
      node;

    function unroll_loop(node : tnode) : tnode;
    function OptimizeInductionVariables(node : tnode) : boolean;
    function optimize_record_writes(var n: tnode): boolean;
    function OptimizeForLoop(var node : tnode) : boolean;

  implementation

    uses
      cclasses,cutils,compinnr,cdynset,
      globtype,globals,constexp,
{$ifdef i386}
      cpuinfo,
{$endif i386}
      verbose,
      symbase,symconst,symdef,symsym,symtype,
      defutil,
      nutils,
      nadd,nbas,nflw,ncon,ninl,ncal,nld,nmem,ncnv,
      ncgmem,
      pass_1,
      optbase,optutils,
      procinfo;

    function number_unrolls(node : tnode) : cardinal;
      var
        nodeCount : cardinal;
      begin
        { calculate how often a loop shall be unrolled.

          The term (60*ord(node_count_weighted(node)<15)) is used to get small loops  unrolled more often as
          the counter management takes more time in this case. }
{$ifdef i386}
        { multiply by 2 for CPUs with a long pipeline }
        if current_settings.optimizecputype in [cpu_Pentium4] then
          begin
            { See the common branch below for an explanation. }
            nodeCount:=node_count_weighted(node,41);
            number_unrolls:=round((60+(60*ord(nodeCount<15)))/max(nodeCount,1))
          end
        else
{$endif i386}
          begin
            { If nodeCount >= 15, numerator will be 30,
              and the largest number (starting from 15) that makes sense as its denominator
              (the smallest number that gives number_unrolls = 1) is 21 = trunc(30/1.5+1),
              so there's no point in counting for more than 21 nodes.
              "Long pipeline" variant above is the same with numerator=60 and max denominator = 41. }
            nodeCount:=node_count_weighted(node,21);
            number_unrolls:=round((30+(60*ord(nodeCount<15)))/max(nodeCount,1));
          end;

        if number_unrolls=0 then
          number_unrolls:=1;
      end;

    type
      treplaceinfo = record
        node : tnode;
        value : Tconstexprint;
      end;
      preplaceinfo = ^treplaceinfo;

    function checkcontrollflowstatements(var n:tnode; arg: pointer): foreachnoderesult;
      begin
        if n.nodetype in [breakn,continuen,goton,labeln,exitn,raisen] then
          result:=fen_norecurse_true
        else
          result:=fen_false;
      end;


    function replaceloadnodes(var n: tnode; arg: pointer): foreachnoderesult;
      begin
        if n.isequal(preplaceinfo(arg)^.node) then
          begin
            if n.flags*[nf_modify,nf_write,nf_address_taken]<>[] then
              internalerror(2012090402);
            n.free;
            n:=cordconstnode.create(preplaceinfo(arg)^.value,preplaceinfo(arg)^.node.resultdef,false);
            do_firstpass(n);
          end;
        result:=fen_false;
      end;


    function unroll_loop(node : tnode) : tnode;
      var
        unrolls,i : cardinal;
        counts : qword;
        bigcounts : Tconstexprint;
        unrollstatement,newforstatement : tstatementnode;
        unrollblock : tblocknode;
        getridoffor : boolean;
        replaceinfo : treplaceinfo;
        hascontrollflowstatements : boolean;
      begin
        result:=nil;
        if (cs_opt_size in current_settings.optimizerswitches) then
          exit;
        if ErrorCount<>0 then
          exit;
        if not(node.nodetype in [forn]) then
          exit;
        { the unroller assumes a stride of one }
        if assigned(tfornode(node).loopstep) then
          exit;
        unrolls:=number_unrolls(tfornode(node).t2);
        if (unrolls>1) and
          ((tfornode(node).left.nodetype<>loadn) or
           { the address of the counter variable might be taken if it is passed by constref to a
             subroutine, so really check if it is not taken }
           ((tfornode(node).left.nodetype=loadn) and (tloadnode(tfornode(node).left).symtableentry is tabstractvarsym) and
            not(tabstractvarsym(tloadnode(tfornode(node).left).symtableentry).addr_taken) and
            not(tabstractvarsym(tloadnode(tfornode(node).left).symtableentry).different_scope))
           ) then
          begin
            { number of executions known? }
            if (tfornode(node).right.nodetype=ordconstn) and (tfornode(node).t1.nodetype=ordconstn) then
              begin
                if lnf_backward in tfornode(node).loopflags then
                  bigcounts:=tordconstnode(tfornode(node).right).value-tordconstnode(tfornode(node).t1).value+1
                else
                  bigcounts:=tordconstnode(tfornode(node).t1).value-tordconstnode(tfornode(node).right).value+1;
                { a full-range 64-bit loop does not fit the counter below }
                if (bigcounts<1) or (bigcounts>high(qword)) then
                  exit;
                counts:=bigcounts.uvalue;

                hascontrollflowstatements:=foreachnodestatic(tfornode(node).t2,@checkcontrollflowstatements,nil);

                { don't unroll more than we need,

                  multiply unroll by two here because we can get rid
                  of the counter variable completely and replace it by a constant
                  if unrolls=counts }
                if unrolls*2>=counts then
                  unrolls:=counts;

                { create block statement }
                unrollblock:=internalstatements(unrollstatement);

                { can we get rid completly of the for ? }
                getridoffor:=(unrolls=counts) and not(hascontrollflowstatements) and
                  { TP/Macpas allows assignments to the for-variables, so we cannot get rid of the for }
                  ([m_tp7,m_mac]*current_settings.modeswitches=[]);

                if getridoffor then
                  begin
                    replaceinfo.node:=tfornode(node).left;
                    replaceinfo.value:=tordconstnode(tfornode(node).right).value;
                  end
                else
                  { we consider currently unrolling not beneficial, if we cannot get rid of the for completely, this
                    might change if a more sophisticated heuristics is used (FK) }
                  exit;

                { let's unroll (and rock of course) }
                for i:=1 to unrolls do
                  begin
                    { create and insert copy of the statement block }
                    addstatement(unrollstatement,tfornode(node).t2.getcopy);

                    { set and insert entry label? }
                    if (counts mod unrolls<>0) and
                      ((counts mod unrolls)=unrolls-i) then
                      begin
                        tfornode(node).entrylabel:=clabelnode.create(cnothingnode.create,clabelsym.create('$optunrol'));
                        addstatement(unrollstatement,tfornode(node).entrylabel);
                      end;

                    if getridoffor then
                      begin
                        foreachnodestatic(tnode(unrollstatement),@replaceloadnodes,@replaceinfo);
                        if lnf_backward in tfornode(node).loopflags then
                          replaceinfo.value:=replaceinfo.value-1
                        else
                          replaceinfo.value:=replaceinfo.value+1;
                      end
                    else
                      begin
                        { for itself increases at the last iteration }
                        if i<unrolls then
                          begin
                            { insert incr/decrementation of counter var }
                            if lnf_backward in tfornode(node).loopflags then
                              addstatement(unrollstatement,
                                geninlinenode(in_dec_x,false,ccallparanode.create(tfornode(node).left.getcopy,nil)))
                            else
                              addstatement(unrollstatement,
                                geninlinenode(in_inc_x,false,ccallparanode.create(tfornode(node).left.getcopy,nil)));
                          end;
                       end;
                  end;
                { can we get rid of the for statement? }
                if getridoffor then
                  begin
                    { create block statement }
                    result:=internalstatements(newforstatement);
                    addstatement(newforstatement,unrollblock);
                    doinlinesimplify(result);
                  end;
              end
            else
              begin
                { unrolling is a little bit more tricky if we don't know the
                  loop count at compile time, but the solution is to use a jump table
                  which is indexed by "loop count mod unrolls" at run time and which
                  jumps then at the appropriate place inside the loop. Because
                  a module division is expensive, we can use only unroll counts dividable
                  by 2 }
                case unrolls of
                  1..2:
                    ;
                  3:
                    unrolls:=2;
                  4..7:
                    unrolls:=4;
                  { unrolls>4 already make no sense imo, but who knows (FK) }
                  8..15:
                    unrolls:=8;
                  16..31:
                    unrolls:=16;
                  32..63:
                    unrolls:=32;
                  64..$7fff:
                    unrolls:=64;
                  else
                    exit;
                end;
                { we don't handle this yet }
                exit;
              end;
            if not(assigned(result)) then
              begin
                tfornode(node).t2.free;
                tfornode(node).t2:=unrollblock;
              end;
          end;
      end;


    function checkcontinue(var n:tnode; arg: pointer): foreachnoderesult;
      begin
        if n.nodetype=continuen then
          result:=fen_norecurse_true
        else
          result:=fen_false;
      end;


    type
      pinvariantfieldcontext = ^tinvariantfieldcontext;
      tinvariantfieldcontext = record
        fieldnode : tsubscriptnode;
      end;

      pinvariantvectorcontext = ^tinvariantvectorcontext;
      tinvariantvectorcontext = record
        vectornode : tvecnode;
      end;

    function invalidatesinvariantfield(var n : tnode;arg : pointer) : foreachnoderesult;
      var
        fieldcontext : pinvariantfieldcontext;
      begin
        fieldcontext:=pinvariantfieldcontext(arg);
        result:=fen_false;
        case n.nodetype of
          calln,
          asmn:
            result:=fen_norecurse_true;
          derefn:
            if n.flags*[nf_write,nf_modify,nf_address_taken]<>[] then
              result:=fen_norecurse_true;
          addrn:
            if tunarynode(n).left.isequal(fieldcontext^.fieldnode) then
              result:=fen_norecurse_true;
          subscriptn:
            if (tsubscriptnode(n).vs=fieldcontext^.fieldnode.vs) and
              (n.flags*[nf_write,nf_modify,nf_address_taken]<>[]) then
              result:=fen_norecurse_true;
          else
            ;
        end;
      end;


    function invalidatesinvariantvector(var n : tnode;arg : pointer) : foreachnoderesult;
      var
        vectorcontext : pinvariantvectorcontext;
        addressednode : tnode;
      begin
        vectorcontext:=pinvariantvectorcontext(arg);
        result:=fen_false;
        case n.nodetype of
          calln,
          asmn:
            result:=fen_norecurse_true;
          derefn:
            if n.flags*[nf_write,nf_modify,nf_address_taken]<>[] then
              result:=fen_norecurse_true;
          addrn:
            begin
              addressednode:=tunarynode(n).left;
              if addressednode.isequal(vectorcontext^.vectornode.left) or
                ((addressednode.nodetype=vecn) and
                 tvecnode(addressednode).left.isequal(vectorcontext^.vectornode.left)) then
                result:=fen_norecurse_true;
            end;
          loadn:
            if (vectorcontext^.vectornode.left.nodetype=loadn) and
              (tloadnode(n).symtableentry=tloadnode(vectorcontext^.vectornode.left).symtableentry) and
              (n.flags*[nf_write,nf_modify,nf_address_taken]<>[]) then
              result:=fen_norecurse_true;
          vecn:
            if tvecnode(n).left.isequal(vectorcontext^.vectornode.left) and
              (n.flags*[nf_write,nf_modify,nf_address_taken]<>[]) then
              result:=fen_norecurse_true;
          else
            ;
        end;
      end;


    function invalidatesscalarthroughunknownmemory(var n : tnode;arg : pointer) : foreachnoderesult;
      begin
        result:=fen_false;
        case n.nodetype of
          calln,
          asmn:
            { The tree DFA records direct definitions, not the memory effects
              of an opaque call or assembler block. }
            result:=fen_norecurse_true;
          derefn:
            if n.flags*[nf_write,nf_modify,nf_address_taken]<>[] then
              { A pointer write may alias global storage. }
              result:=fen_norecurse_true;
          else
            ;
        end;
      end;


    function scalarloadisloopinvariant(loop : tfornode;expr : tloadnode) : boolean;
      var
        vs : tabstractvarsym;
      begin
        result:=false;
        if not(expr.symtableentry is tabstractvarsym) or
          (expr.flags*[nf_write,nf_modify,nf_address_taken]<>[]) or
          not assigned(loop.optinfo) or
          not assigned(loop.t2.optinfo) or
          not assigned(expr.optinfo) or
          expr.isequal(actualtargetnode(@loop.left)^) then
          exit;
        vs:=tabstractvarsym(expr.symtableentry);
        if vs.addr_taken or
          vs.different_scope or
          (vo_volatile in vs.varoptions) or
          DynSetIn(loop.t2.optinfo^.defsum,expr.optinfo^.index) then
          exit;
        case vs.typ of
          localvarsym:
            result:=not tabstractnormalvarsym(vs).is_captured and
              not tabstractnormalvarsym(vs).inparentfpstruct and
              (vs.varregable in [vr_intreg,vr_mmreg,vr_fpureg]);
          paravarsym:
            result:=(vs.varspez=vs_value) and
              not tabstractnormalvarsym(vs).is_captured and
              not tabstractnormalvarsym(vs).inparentfpstruct and
              (vs.varregable in [vr_intreg,vr_mmreg,vr_fpureg]);
          staticvarsym:
            result:=not(vo_is_thread_var in vs.varoptions) and
              not foreachnodestatic(pm_preprocess,loop.t2,
                @invalidatesscalarthroughunknownmemory,nil);
          else
            ;
        end;
      end;


    function is_loop_invariant(loop : tnode;expr : tnode) : boolean;
      var
        fieldcontext : tinvariantfieldcontext;
        vectorcontext : tinvariantvectorcontext;
      begin
        result:=is_constnode(expr);
        case expr.nodetype of
          loadn:
            result:=(pi_dfaavailable in current_procinfo.flags) and
              scalarloadisloopinvariant(tfornode(loop),tloadnode(expr));
          vecn:
            begin
              vectorcontext.vectornode:=tvecnode(expr);
              result:=((tvecnode(expr).left.nodetype=loadn) or is_loop_invariant(loop,tvecnode(expr).left)) and
                (expr.flags*[nf_write,nf_modify,nf_address_taken]=[]) and
                is_loop_invariant(loop,tvecnode(expr).right) and
                not(foreachnodestatic(pm_preprocess,tfornode(loop).t2,
                  @invalidatesinvariantvector,@vectorcontext));
            end;
          typeconvn:
            result:=is_loop_invariant(loop,ttypeconvnode(expr).left);
          subscriptn:
            begin
              fieldcontext.fieldnode:=tsubscriptnode(expr);
              result:=not(vo_volatile in tsubscriptnode(expr).vs.varoptions) and
                (expr.flags*[nf_write,nf_modify,nf_address_taken]=[]) and
                is_loop_invariant(loop,tsubscriptnode(expr).left) and
                not(foreachnodestatic(pm_preprocess,tfornode(loop).t2,
                  @invalidatesinvariantfield,@fieldcontext));
            end;
          addn,subn:
            result:=is_loop_invariant(loop,taddnode(expr).left) and is_loop_invariant(loop,taddnode(expr).right);
          else
            ;
        end;
      end;


    type
      pcounterusecontext = ^tcounterusecontext;
      tcounterusecontext = record
        counter : tnode;
        totalreads,
        indexreads : longint;
      end;

    function countcounterreads(var n : tnode;arg : pointer) : foreachnoderesult;
      var
        usecontext : pcounterusecontext;
        indexnode : tnode;
      begin
        result:=fen_false;
        usecontext:=pcounterusecontext(arg);
        case n.nodetype of
          loadn:
            if n.isequal(usecontext^.counter) and
              (n.flags*[nf_write,nf_modify]=[]) then
              inc(usecontext^.totalreads);
          vecn:
            begin
              indexnode:=tvecnode(n).right;
              if indexnode.nodetype=typeconvn then
                indexnode:=ttypeconvnode(indexnode).left;
              if (tvecnode(n).left.nodetype=loadn) and
                (not(is_special_array(tvecnode(n).left.resultdef)) or
                 is_dynamic_array(tvecnode(n).left.resultdef)) and
                not(is_packed_array(tvecnode(n).left.resultdef)) and
                indexnode.isequal(usecontext^.counter) and
                (indexnode.flags*[nf_write,nf_modify]=[]) then
                inc(usecontext^.indexreads);
            end;
          else
            ;
        end;
      end;


    { true when every read of the loop counter inside the body is the index
      of a direct array access: pointer bumping then retires the counter's
      per-iteration use instead of adding a second live induction variable
      whose load address depends on the previous iteration }
    function counter_dies_with_indexing(loop : tfornode) : boolean;
      var
        usecontext : tcounterusecontext;
      begin
        usecontext.counter:=loop.left;
        usecontext.totalreads:=0;
        usecontext.indexreads:=0;
        foreachnodestatic(pm_postprocess,loop.t2,@countcounterreads,@usecontext);
        result:=usecontext.totalreads=usecontext.indexreads;
      end;


    function findearlyexit(var n : tnode;arg : pointer) : foreachnoderesult;
      begin
        if n.nodetype in [breakn,exitn,goton] then
          result:=fen_norecurse_true
        else
          result:=fen_false;
      end;


    { a loop that always runs to completion amortizes a second induction
      variable over every element - Delphi keeps the bumped pointer next to
      a live counter in exactly this shape.  Loops with early exits keep
      the stricter dead-counter rule: a break after a few iterations never
      repays the extra per-iteration increment }
    function loop_runs_to_completion(loop : tfornode) : boolean;
      begin
        result:=not foreachnodestatic(pm_postprocess,loop.t2,@findearlyexit,nil);
      end;


    function invalidatesimplicitarraybase(var n : tnode;arg : pointer) : foreachnoderesult;
      begin
        result:=fen_false;
        case n.nodetype of
          calln:
            { A non-address-taken local that is not captured cannot be
              reached by a call.  Globals, parameters and captured locals
              retain the conservative barrier. }
            if (tsym(arg).typ<>localvarsym) or
              tlocalvarsym(tsym(arg)).is_captured then
              result:=fen_norecurse_true;
          asmn:
            result:=fen_norecurse_true;
          derefn:
            { a pointer store can hit a variable whose address escaped in the
              caller (var parameters) }
            if n.flags*[nf_write,nf_modify,nf_address_taken]<>[] then
              result:=fen_norecurse_true;
          loadn:
            if (tloadnode(n).symtableentry=tsym(arg)) and
              (n.flags*[nf_write,nf_modify]<>[]) then
              result:=fen_norecurse_true;
          else
            ;
        end;
      end;


    { a dynamic array or dynamic string base is a pointer VALUE loaded from
      the variable:
      bumping a cached copy across iterations is only legal while nothing in
      the body can replace that pointer.  Element writes are fine for dynamic
      arrays, since they are not copy-on-write; string element writes already
      stay outside this read-only strength-reduction path. }
    function implicit_array_base_is_loop_invariant(loop : tfornode;base : tnode) : boolean;
      begin
        result:=false;
        if (base.nodetype<>loadn) or
          not(tloadnode(base).symtableentry.typ in [localvarsym,paravarsym,staticvarsym]) then
          exit;
        if tabstractvarsym(tloadnode(base).symtableentry).addr_taken then
          exit;
        if (tloadnode(base).symtableentry.typ=staticvarsym) and
          (vo_is_thread_var in tstaticvarsym(tloadnode(base).symtableentry).varoptions) then
          exit;
        result:=not foreachnodestatic(pm_preprocess,loop.t2,@invalidatesimplicitarraybase,
          tloadnode(base).symtableentry);
      end;


    { The four axes of the pointer-bump decision for a counter-indexed
      vector access, split out so the next repair changes one axis instead
      of growing the historical single-expression gate (that shape produced
      the mutable-string-base wrong-code and the local-dynarray profit
      regression, audit journal 5 B1). }

    { the counter variable is the vector index, read plainly - directly or
      through the usual array-access type cast }
    function counter_indexes_vector(loop : tfornode;n : tvecnode) : boolean;
      begin
        result:=(n.right.isequal(loop.left) or
                 ((n.right.nodetype=typeconvn) and
                  ttypeconvnode(n.right).left.isequal(loop.left))) and
                (n.right.flags*[nf_write,nf_modify]=[]);
      end;


    { arrays the maintained pointer understands: normal or dynamic, not
      packed; the replacement is a raw address cursor and cannot preserve a
      source-level range/overflow check at each element access }
    function vector_admits_pointer_bump(loop : tfornode;n : tvecnode) : boolean;
      begin
        result:=(not(is_special_array(n.left.resultdef)) or
                 is_dynamic_array(n.left.resultdef)) and
                not(is_packed_array(n.left.resultdef)) and
                (([cs_check_overflow,cs_check_range]*n.localswitches)=[]) and
                { direct array access, or a loop-invariant expression }
                ((n.left.nodetype=loadn) or
                 is_loop_invariant(loop,n.right));
      end;


    { an implicit array pointer (dynamic array, dynamic string) is a base
      VALUE loaded from the variable - bumping a cached copy is only legal
      while nothing in the body can replace that value }
    function vector_base_is_stable(loop : tfornode;n : tvecnode) : boolean;
      begin
        result:=not(is_implicit_array_pointer(n.left.resultdef)) or
                implicit_array_base_is_loop_invariant(loop,n.left);
      end;


    { removing the multiplication is only worth a maintained pointer if the
      scaled access is not already a simple shift ... }
    function pointer_bump_profitable(loop : tfornode;n : tvecnode) : boolean;
{$if not (defined(cpu16bitalu) or defined(cpu8bitalu))}
      var
        dummy : longint;
{$endif}
      begin
{$if defined(cpu16bitalu) or defined(cpu8bitalu)}
        result:=true;
{$else}
        result:=not(ispowerof2(tcgvecnode(n).get_mul_size,dummy))
          { power-of-two elements wider than the maximum hardware scale
            factor pay an explicit shift+add on every element access,
            exactly like a multiplication }
          or (tcgvecnode(n).get_mul_size>8)
{$ifdef cpu64bitaddr}
          { ... unless the base is a global symbol: 64-bit targets cannot
            encode a RIP/PC-relative base together with an index register,
            so scaled access rematerializes the base address inside the loop
            on every element access.  A dynamic array is even costlier - its
            base is a pointer value that scaled access RELOADS from the
            variable on every element, and the 64-bit address needs the
            32-bit index sign-extended each time.  Only profitable when the
            counter's body reads all become the bumped pointer - a counter
            that stays live would make the pointer a second induction
            variable with a loop-carried load address }
          or ((n.left.nodetype=loadn) and
              (is_implicit_array_pointer(n.left.resultdef) or
               ((tloadnode(n.left).symtableentry.typ=staticvarsym) and
                not(vo_is_thread_var in tstaticvarsym(tloadnode(n.left).symtableentry).varoptions))) and
              (counter_dies_with_indexing(loop) or
               loop_runs_to_completion(loop)))
{$endif cpu64bitaddr}
          ;
{$endif}
      end;


    type
      toptimizeinductionvariablescontext = object
        currforloop : tfornode;
        initcode,
        calccode,
        deletecode : tblocknode;
        initcodestatements,
        calccodestatements,
        deletecodestatements: tstatementnode;
        ninductions : sizeint;
        inductions : array of record
          temp : ttempcreatenode;
          expr : tnode;
        end;
        changedforloop,
        containsnestedforloop,
        docalcatend : boolean;
        function findpreviousstrengthreduction(var n: tnode): boolean;
        procedure addinduction(temp : ttempcreatenode; expr : tnode);
        function dostrengthreductiontest(var n: tnode): foreachnoderesult;
        procedure optimizeinductionvariablessingleforloop(var n: tnode);
      end;


    function toptimizeinductionvariablescontext.findpreviousstrengthreduction(var n: tnode): boolean;
      var
        i : longint;
        hp : tnode;
      begin
        result:=false;
        for i:=0 to ninductions-1 do
          begin
            { do we already maintain one expression? }
            if inductions[i].expr.isequal(n) then
              begin
                case n.nodetype of
                  muln:
                    hp:=ctemprefnode.create(inductions[i].temp);
                  vecn:
                    hp:=ctypeconvnode.create_internal(cderefnode.create(ctemprefnode.create(inductions[i].temp)),n.resultdef);
                  else
                    internalerror(200809211);
                end;
                n.free;
                n:=hp;
                exit(true);
              end;
          end;
      end;


    procedure toptimizeinductionvariablescontext.addinduction(temp : ttempcreatenode; expr : tnode);
      begin
        if not assigned(initcode) then
          begin
            initcode:=internalstatements(initcodestatements);
            calccode:=internalstatements(calccodestatements);
            deletecode:=internalstatements(deletecodestatements);
            docalcatend:=not(assigned(currforloop.entrylabel)) and
              not(foreachnodestatic(currforloop.t2,@checkcontinue,nil));
          end;
        if ninductions>=length(inductions) then
          SetLength(inductions,4+ninductions+ninductions shr 1);
        inductions[ninductions].temp:=temp;
        inductions[ninductions].expr:=expr;
        inc(ninductions);
      end;


    { checks if the strength of n can be reduced, currforloop is the tforloop being considered }
    function toptimizeinductionvariablescontext.dostrengthreductiontest(var n: tnode): foreachnoderesult;
      var
        tempnode,startvaltemp : ttempcreatenode;
        nn : tnode;
        nt : tnodetype;
        nflags : tnodeflags;
      begin
        result:=fen_false;
        nflags:=n.flags;
        case n.nodetype of
          forn:
            { inform for loop search routine, that it needs to search more deeply }
            containsnestedforloop:=true;
          muln:
            begin
              if (taddnode(n).right.nodetype=loadn) and
                taddnode(n).right.isequal(currforloop.left) and
                { plain read of the loop variable? }
                not(nf_write in taddnode(n).right.flags) and
                not(nf_modify in taddnode(n).right.flags) and
                is_loop_invariant(currforloop,taddnode(n).left) then
                taddnode(n).swapleftright;

              if (taddnode(n).left.nodetype=loadn) and
                taddnode(n).left.isequal(currforloop.left) and
                { plain read of the loop variable? }
                not(nf_write in taddnode(n).left.flags) and
                not(nf_modify in taddnode(n).left.flags) and
                is_loop_invariant(currforloop,taddnode(n).right) then
                begin
                  changedforloop:=true;
                  { did we use the same expression before already? }
                  if not(findpreviousstrengthreduction(n)) then
                    begin
{$ifdef DEBUG_OPTSTRENGTH}
                      writeln('**********************************************************************************');
                      writeln(parser_current_file, ': Found expression for strength reduction (MUL): ');
                      printnode(output,n);
                      writeln('**********************************************************************************');
{$endif DEBUG_OPTSTRENGTH}
                      tempnode:=ctempcreatenode.create(n.resultdef,n.resultdef.size,tt_persistent,
                        tstoreddef(n.resultdef).is_intregable or tstoreddef(n.resultdef).is_fpuregable);
                      addinduction(tempnode,n);

                      if lnf_backward in currforloop.loopflags then
                        addstatement(calccodestatements,
                          geninlinenode(in_dec_x,false,
                          ccallparanode.create(ctemprefnode.create(tempnode),ccallparanode.create(taddnode(n).right.getcopy,nil))))
                      else
                        addstatement(calccodestatements,
                          geninlinenode(in_inc_x,false,
                          ccallparanode.create(ctemprefnode.create(tempnode),ccallparanode.create(taddnode(n).right.getcopy,nil))));

                      addstatement(initcodestatements,tempnode);
                      nn:=currforloop.right.getcopy;
                      { If the calculation is not performed at the end
                        it is needed to adjust the starting value }
                      if not docalcatend then
                        begin
                          if lnf_backward in currforloop.loopflags then
                            nt:=addn
                          else
                            nt:=subn;
                          nn:=caddnode.create_internal(nt,nn,
                             cordconstnode.create(1,nn.resultdef,false));
                        end;
                      addstatement(initcodestatements,cassignmentnode.create(ctemprefnode.create(tempnode),
                          caddnode.create(muln,nn,
                            taddnode(n).right.getcopy)
                          )
                        );

                      { finally replace the node by a temp. ref }
                      n:=ctemprefnode.create(tempnode);

                      { ... and add a temp. release node }
                      addstatement(deletecodestatements,ctempdeletenode.create(tempnode));
                    end;
                  { set types }
                  do_firstpass(n);
                  result:=fen_norecurse_false;
                end;
            end;
          vecn:
            begin
              { Hoist an address whose base is fixed and whose index is proven
                invariant in this loop.  Keep checks in place: moving a range
                error before a loop that executes zero times would change the
                program. }
              if is_normal_array(tvecnode(n).left.resultdef) and
                not(is_packed_array(tvecnode(n).left.resultdef)) and
                not(is_managed_type(n.resultdef)) and
                (tvecnode(n).left.nodetype=loadn) and
                (([cs_check_overflow,cs_check_range]*n.localswitches)=[]) and
                is_loop_invariant(currforloop,tvecnode(n).right) then
                begin
                  changedforloop:=true;
                  if not(findpreviousstrengthreduction(n)) then
                    begin
                      tempnode:=ctempcreatenode.create(voidpointertype,voidpointertype.size,tt_persistent,true);
                      addinduction(tempnode,n);
                      addstatement(initcodestatements,tempnode);
                      addstatement(initcodestatements,cassignmentnode.create(
                        ctemprefnode.create(tempnode),
                        { This is the address of the element storage, also for
                          procvar elements.  A source-level @ProcVar may mean
                          the stored code address instead. }
                        caddrnode.create_internal(cvecnode.create(
                          tvecnode(n).left.getcopy,
                          tvecnode(n).right.getcopy))));
                      n:=ctypeconvnode.create_internal(
                        cderefnode.create(ctemprefnode.create(tempnode)),n.resultdef);
                      addstatement(deletecodestatements,ctempdeletenode.create(tempnode));
                    end;
                  if nflags*[nf_write,nf_modify]<>[] then
                    begin
                      if (n.nodetype<>typeconvn) or (ttypeconvnode(n).left.nodetype<>derefn) then
                        internalerror(2026081601);
                      ttypeconvnode(n).left.flags:=ttypeconvnode(n).left.flags+nflags*[nf_write,nf_modify];
                    end;
                  do_firstpass(n);
                  result:=fen_norecurse_false;
                end
              { is the index the counter variable? }
              else if counter_indexes_vector(currforloop,tvecnode(n)) and
                vector_admits_pointer_bump(currforloop,tvecnode(n)) and
                vector_base_is_stable(currforloop,tvecnode(n)) and
                pointer_bump_profitable(currforloop,tvecnode(n)) then
                begin
                  changedforloop:=true;
                  { did we use the same expression before already? }
                  if not(findpreviousstrengthreduction(n)) then
                    begin
{$ifdef DEBUG_OPTSTRENGTH}
                      writeln('**********************************************************************************');
                      writeln(parser_current_file,': Found expression for strength reduction (VEC): ');
                      printnode(output,n);
                      writeln('**********************************************************************************');
{$endif DEBUG_OPTSTRENGTH}
                      tempnode:=ctempcreatenode.create(voidpointertype,voidpointertype.size,tt_persistent,true);
                      addinduction(tempnode,n);

                      if lnf_backward in currforloop.loopflags then
                        addstatement(calccodestatements,
                          cinlinenode.createintern(in_dec_x,false,
                          ccallparanode.create(ctemprefnode.create(tempnode),ccallparanode.create(
                          cordconstnode.create(tcgvecnode(n).get_mul_size,sizeuinttype,false),nil))))
                      else
                        addstatement(calccodestatements,
                          cinlinenode.createintern(in_inc_x,false,
                          ccallparanode.create(ctemprefnode.create(tempnode),ccallparanode.create(
                          cordconstnode.create(tcgvecnode(n).get_mul_size,sizeuinttype,false),nil))));

                      addstatement(initcodestatements,tempnode);

                      startvaltemp:=maybereplacewithtemp(currforloop.right,initcode,initcodestatements,currforloop.right.resultdef.size,true);
                      { The maintained pointer is an address cursor, not a
                        source-level element access.  A guarded loop may start
                        before or after the array's declared slice and only
                        dereference once the source guard admits the index.
                        Use an explicitly signed address delta and do not
                        narrow it to the source array's enum/subrange. }
                      nn:=cvecnode.create(tvecnode(n).left.getcopy,
                        ctypeconvnode.create_internal(
                          currforloop.right.getcopy,ptrsinttype));
                      include(tvecnode(nn).vecnodeflags,vnf_internal_address_index);
                      { Request the storage address explicitly: normal Pascal
                        @ProcVar denotes the stored code address in modes where
                        procedure variables have special @ semantics. }
                      nn:=caddrnode.create_internal(nn);
                      { If the calculation is not performed at the end
                        it is needed to adjust the starting value }
                      if not docalcatend then
                        begin
                          if lnf_backward in currforloop.loopflags then
                            nt:=addn
                          else
                            nt:=subn;
                          nn:=caddnode.create_internal(nt,
                             ctypeconvnode.create_internal(nn,voidpointertype),
                             cordconstnode.create(tcgvecnode(n).get_mul_size,sizeuinttype,false));
                        end;
                      addstatement(initcodestatements,cassignmentnode.create(ctemprefnode.create(tempnode),nn));

                      { finally replace the node by a temp. ref }
                      n:=ctypeconvnode.create_internal(cderefnode.create(ctemprefnode.create(tempnode)),n.resultdef);

                      { ... and add a temp. release node }
                      if startvaltemp<>nil then
                        addstatement(deletecodestatements,ctempdeletenode.create(startvaltemp));
                      addstatement(deletecodestatements,ctempdeletenode.create(tempnode));
                    end;
                  { Copy the nf_write,nf_modify flags to the new deref node of the temp.
                    Otherwise assignments to vector elements will be removed. }
                  if nflags*[nf_write,nf_modify]<>[] then
                    begin
                      if (n.nodetype<>typeconvn) or (ttypeconvnode(n).left.nodetype<>derefn) then
                        internalerror(2021091501);
                      ttypeconvnode(n).left.flags:=ttypeconvnode(n).left.flags+nflags*[nf_write,nf_modify];
                    end;
                  { set types }
                  do_firstpass(n);
                  result:=fen_norecurse_false;
                end;
            end;
          else
            ;
        end;
      end;


    function dostrengthreductiontest_callback(var n: tnode; arg: pointer): foreachnoderesult;
      begin
        result:=toptimizeinductionvariablescontext(arg^).dostrengthreductiontest(n);
      end;


    procedure toptimizeinductionvariablescontext.optimizeinductionvariablessingleforloop(var n: tnode);
      var
        loopcode : tblocknode;
        loopcodestatements,
        newcodestatements : tstatementnode;
        newfor,oldn : tnode;
      begin
        { do we have DFA available? }
        if pi_dfaavailable in current_procinfo.flags then
          begin
            CalcDefSum(tfornode(n).t2);
          end;
        currforloop:=tfornode(n);
        initcode:=nil;
        calccode:=nil;
        deletecode:=nil;
        initcodestatements:=nil;
        calccodestatements:=nil;
        deletecodestatements:=nil;
        ninductions:=0;
        docalcatend:=false;
        { find all expressions being candidates for strength reduction
          and replace them }
        foreachnodestatic(pm_postprocess,n,@dostrengthreductiontest_callback,@self);

        { clue everything together }
        if assigned(initcode) then
          begin
            do_firstpass(tnode(initcode));
            do_firstpass(tnode(calccode));
            do_firstpass(tnode(deletecode));
            { create a new for node, the old one will be released by the compiler }
            oldn:=n;
            newfor:=cfornode.create(tfornode(oldn).left,tfornode(oldn).right,tfornode(oldn).t1,tfornode(oldn).t2,lnf_backward in tfornode(oldn).loopflags);
            tfornode(oldn).left:=nil;
            tfornode(oldn).right:=nil;
            tfornode(oldn).t1:=nil;
            tfornode(oldn).t2:=nil;

            loopcode:=internalstatements(loopcodestatements);
            if not docalcatend then
              addstatement(loopcodestatements,calccode);
            addstatement(loopcodestatements,tfornode(newfor).t2);
            if docalcatend then
              addstatement(loopcodestatements,calccode);
            tfornode(newfor).t2:=loopcode;
            do_firstpass(newfor);

            n:=internalstatements(newcodestatements);
            oldn.Free;
            oldn := nil;
            addstatement(newcodestatements,initcode);
            addstatement(newcodestatements,newfor);
            addstatement(newcodestatements,deletecode);
          end;
      end;


    function optimizeinductionvariablessingleforloop_static(var n: tnode; arg: pointer): foreachnoderesult;
      var
        ctx : ^toptimizeinductionvariablescontext absolute arg;
      begin
        Result:=fen_false;
        if n.nodetype<>forn then
          exit;
        { induction deltas and the rebuilt for node assume the default step
          of 1: calccode increments by one element/multiplicand per iteration
          and cfornode.create below does not carry loopstep. A step loop keeps
          its own lowering; plain loops nested inside it are still found by
          the continued traversal }
        if assigned(tfornode(n).loopstep) then
          exit;
        ctx^.containsnestedforloop:=false;
        ctx^.optimizeinductionvariablessingleforloop(n);
        { can we avoid further searching? }
        if not(ctx^.containsnestedforloop) then
          Result:=fen_norecurse_false;
      end;


    function OptimizeInductionVariables(node : tnode) : boolean;
      var
        ctx : toptimizeinductionvariablescontext;
      begin
        Result:=false;
        if not(pi_dfaavailable in current_procinfo.flags) then
          exit;
        ctx.changedforloop:=false;
        foreachnodestatic(pm_postprocess,node,@optimizeinductionvariablessingleforloop_static,@ctx);
        Result:=ctx.changedforloop;
      end;


    function recorddirectaccess(var n: tnode; arg: pointer): foreachnoderesult;
      begin
        result:=fen_false;
        case n.nodetype of
          subscriptn:
            if (TSubscriptNode(n).left.nodetype=loadn) and
              (TLoadNode(TSubscriptNode(n).left).symtableentry=TSymEntry(arg)) then
              { It's fine if the record is loaded to access a single field }
              result:=fen_norecurse_false;
          loadn:
            if (TLoadNode(n).symtableentry=TSymEntry(arg)) then
              result:=fen_norecurse_true;
          else
            ;
        end;
      end;


    type
      TFieldTempPair = class(TLinkedListItem)
        BaseSymbol: TAbstractVarSym;
        Field: TFieldVarSym;
        TempCreate: TTempCreateNode;
        InitialRead: Boolean;
        FieldRead: Boolean;
        FieldWritten: Boolean;
        { the field is handed to a call by reference, so the callee holds
          the address of the original storage and the field cannot live in
          a temp across that call }
        AddressEscapes: Boolean;
        Score: LongInt;
        FirstDepth: Integer;
      end;

      PRecordData = ^TRecordData;
      TRecordData = record
        BaseSymbol: TAbstractVarSym;
        Fields: TLinkedList;
        Depth: Integer;
      end;

    function recordloopfindrefs(var n: tnode; arg: pointer): foreachnoderesult; forward;

    { marks the field whose address a by-reference actual hands to the
      callee.  Only the designator itself counts: index and other
      subexpressions are evaluated into values before the call, so a field
      appearing in them keeps its promoted temp. }
    procedure recordloopmarkescapes(n: tnode; arg: pointer);
      var
        ThisTemp: TFieldTempPair;
      begin
        while Assigned(n) do
          case n.nodetype of
            typeconvn:
              { only a conversion that keeps the same storage passes the
                address of the field along; one that builds a new value
                (Single field into a constref Double, say) hands over the
                address of that temporary instead, and the field stays
                promotable }
              if TTypeConvNode(n).retains_value_location then
                n:=TTypeConvNode(n).left
              else
                Break;
            vecn:
              n:=TVecNode(n).left;
            subscriptn:
              begin
                if (TSubscriptNode(n).left.nodetype=loadn) and
                  (TLoadNode(TSubscriptNode(n).left).symtableentry=PRecordData(arg)^.BaseSymbol) then
                  begin
                    ThisTemp:=TFieldTempPair(PRecordData(arg)^.Fields.First);
                    while Assigned(ThisTemp) do
                      begin
                        if (ThisTemp.BaseSymbol=PRecordData(arg)^.BaseSymbol) and
                          (ThisTemp.Field=TSubscriptNode(n).vs) then
                          begin
                            ThisTemp.AddressEscapes:=True;
                            Break;
                          end;
                        ThisTemp:=TFieldTempPair(ThisTemp.Next);
                      end;
                  end;
                n:=TSubscriptNode(n).left;
              end;
            else
              Break;
          end;
      end;

    { Needed as we can't reference recordloopfindrefs directly within itself }
    function recordloopfindrefs_recursive(var n: tnode; arg: pointer): foreachnoderesult;
      begin
        result:=recordloopfindrefs(n, arg);
      end;

    function recordloopfindrefs(var n: tnode; arg: pointer): foreachnoderesult;
      var
        ThisTemp: TFieldTempPair;
      begin
        case n.nodetype of
          subscriptn:
            if (TSubscriptNode(n).left.nodetype=loadn) and
              (TLoadNode(TSubscriptNode(n).left).symtableentry=PRecordData(arg)^.BaseSymbol) and
              { Needs to be a basic type }
              not is_string(TSubscriptNode(n).vs.vardef) and
              not is_object(TSubscriptNode(n).vs.vardef) and
              not is_managed_type(TSubscriptNode(n).vs.vardef) and
              (
                (
                  tstoreddef(TSubscriptNode(n).vs.vardef).is_intregable and
                  (TSubscriptNode(n).vs.vardef.size<=sizeof(aint))
                ) or
                tstoreddef(TSubscriptNode(n).vs.vardef).is_fpuregable or
                (
                  is_vector(tstoreddef(TSubscriptNode(n).vs.vardef)) and
                  fits_in_mm_register(tstoreddef(TSubscriptNode(n).vs.vardef))
                )
              ) then
              begin
                { See if we've defined this field already }
                ThisTemp:=TFieldTempPair(PRecordData(arg)^.Fields.First);
                while Assigned(ThisTemp) do
                  begin
                    if (ThisTemp.BaseSymbol=PRecordData(arg)^.BaseSymbol) and
                      (ThisTemp.Field=TSubscriptNode(n).vs) then
                      Break;
                    ThisTemp:=TFieldTempPair(ThisTemp.Next);
                  end;

                if not Assigned(ThisTemp) then
                  begin
                    ThisTemp:=TFieldTempPair.Create;
                    ThisTemp.BaseSymbol:=PRecordData(arg)^.BaseSymbol;
                    ThisTemp.Field:=TSubscriptNode(n).vs;
                    ThisTemp.TempCreate:=CTempCreateNode.Create(TSubscriptNode(n).vs.vardef,TSubscriptNode(n).vs.vardef.size,tt_persistent,True);
                    ThisTemp.InitialRead:=(nf_modify in TLoadNode(TSubscriptNode(n).left).flags) or not (nf_write in TLoadNode(TSubscriptNode(n).left).flags);
                    ThisTemp.FieldWritten:=False;
                    ThisTemp.AddressEscapes:=False;
                    ThisTemp.Score:=0;
                    ThisTemp.FirstDepth:=PRecordData(arg)^.Depth;
                    if not Assigned(PRecordData(arg)^.Fields.Last) then
                      PRecordData(arg)^.Fields.Insert(ThisTemp)
                    else
                      PRecordData(arg)^.Fields.InsertAfter(ThisTemp,PRecordData(arg)^.Fields.Last);
                  end;

                { A write is worth 1.5 times as much as a read under the scoring system }
                if TLoadNode(TSubscriptNode(n).left).flags*[nf_write,nf_modify]<>[] then
                  begin
                    ThisTemp.FieldWritten:=True;
                    Inc(ThisTemp.Score,3);
                    if nf_modify in TLoadNode(TSubscriptNode(n).left).flags then
                      begin
                        ThisTemp.FieldRead:=True;
                        Inc(ThisTemp.Score,2);
                      end;
                  end
                else
                  begin
                    ThisTemp.FieldRead:=True;
                    Inc(ThisTemp.Score,2);
                  end;

                result:=fen_true;
                Exit;
              end;
          callparan:
            { any by-reference actual hands the callee the address of the
              original field.  var/out let it store a new value at once;
              constref only reads, but the callee may keep the pointer and
              write through it later - and that cannot be ruled out here:
              the addr_taken flag of a formal describes the statically
              selected routine, while a virtual override that keeps the
              address is picked at run time.  Promoting the field would
              hand out the address of a throwaway temp and lose every such
              write (tconstrefvirt) }
            if assigned(tcallparanode(n).parasym) and
              (tcallparanode(n).parasym.varspez in [vs_var,vs_out,vs_constref]) then
              recordloopmarkescapes(tcallparanode(n).left, arg);
          else
            if n.InheritsFrom(TLoopNode) then
              begin
                if foreachnodestatic(pm_postprocess, TLoopNode(n).left, @recordloopfindrefs_recursive, arg) then
                  result:=fen_true;

                { Writes inside loops may not get executed, so we need to read an initial value to be safe,
                  hence the incrementation of Depth prior to analysing the right and t1 nodes }
                Inc(PRecordData(arg)^.Depth);
                if foreachnodestatic(pm_postprocess, TLoopNode(n).right, @recordloopfindrefs_recursive, arg) then
                  result:=fen_true;
                if foreachnodestatic(pm_postprocess, TLoopNode(n).t1, @recordloopfindrefs_recursive, arg) then
                  result:=fen_true;

                Dec(PRecordData(arg)^.Depth);
              end;
        end;
        result:=fen_false;
      end;


    function recordloopreplacerefs(var n: tnode; arg: pointer): foreachnoderesult;
      var
        ThisTemp: TFieldTempPair;
        NewNode: TNode;
      begin
        case n.nodetype of
          subscriptn:
            if (TSubscriptNode(n).left.nodetype=loadn) and
              (TLoadNode(TSubscriptNode(n).left).symtableentry.typ in [localvarsym, paravarsym]) then
              begin
                { See if this field has been defined }
                ThisTemp:=TFieldTempPair(PRecordData(arg)^.Fields.First);
                while Assigned(ThisTemp) do
                  begin
                    if (ThisTemp.BaseSymbol=TLoadNode(TSubscriptNode(n).left).symtableentry) and
                      (ThisTemp.Field=TSubscriptNode(n).vs) then
                      Break;
                    ThisTemp:=TFieldTempPair(ThisTemp.Next);
                  end;

                if not Assigned(ThisTemp) then
                  begin
                    { The field should not be replaced }
                    result:=fen_norecurse_false;
                    Exit;
                  end;

                { Now actually replace the node }
                NewNode:=CTempRefNode.Create(ThisTemp.TempCreate);
                NewNode.fileinfo:=n.fileinfo;
                NewNode.flags:=NewNode.flags+(TLoadNode(TSubscriptNode(n).left).flags*[nf_write,nf_modify]);
                n.Free;
                n:=NewNode;
                n.pass_typecheck;
                result:=fen_true;
                Exit;
              end;
          else
            ;
        end;
        result:=fen_false;
      end;


    { Estimate a per-platform register limit to prevent too much register pressure. }
    const
{$if defined(i386) or defined(i8086)}
      RECORD_TEMP_LIMIT = 3;
{$elseif defined(aarch64) or defined(riscv64)}
      RECORD_TEMP_LIMIT = 15;
{$else}
      RECORD_TEMP_LIMIT = 7;
{$endif}

    function discount_temprefs(var n:tnode; arg: pointer): foreachnoderesult;
      begin
        if n.nodetype=temprefn then
          begin
            Dec(PInteger(arg)^);
            result:=fen_norecurse_true;
          end
        else
          result:=fen_false;
      end;


    function _optimize_record_writes(var n:tnode; arg: pointer): foreachnoderesult;
      var
        X, Y, SymCount: Integer;
        MinScore: LongInt;
        CurrentSym: TSym;
        RecordData: TRecordData;
        AbortRecord: Boolean;
        NewBlock: TBlockNode;
        NewWrapper: TStatementNode;
        ThisTemp, NextTemp: TFieldTempPair;
        NewCopy, NewNode: TNode;
        record_limit: Integer;
      begin
        result:=fen_false;
        record_limit:=RECORD_TEMP_LIMIT;

        { Record promotion }
        if (n.nodetype=whilerepeatn) and
          not (nf_internal in n.flags) then
          begin
            if foreachnodestatic(pm_postprocess,n,@discount_temprefs,@record_limit) and
              (record_limit<=0) then
              { Likely no free registers }
              Exit;

            RecordData.Fields:=nil;
            { Check to see if local record-types can have individual fields
              promoted to registers }
            if current_procinfo.procdef.localst.symtabletype = localsymtable then
              begin
                RecordData.Fields:=TLinkedList.Create;
                SymCount:=current_procinfo.procdef.localst.SymList.Count-1;
                for X:=0 to SymCount do
                  begin
                    CurrentSym:=TSym(current_procinfo.procdef.localst.SymList[X]);
                    if (CurrentSym.typ=localvarsym) and
                      { Don't optimise records whose address has been taken,
                        since there may be some multithreaded access going on }
                      (TAbstractVarSym(CurrentSym).varsymaccess*[vsa_addr_taken,vsa_different_scope]=[]) then
                      begin

                        if is_record(TAbstractVarSym(CurrentSym).vardef) then
                          begin
                            { TODO: Support unions in a limited fashion later }
                            if TRecordDef(TAbstractVarSym(CurrentSym).vardef).isunion then
                              Continue;

                            { Ignore records with only a single field, but
                              note they may be regable }
                            if (TRecordDef(TAbstractVarSym(CurrentSym).vardef).symtable.SymList.Count <= 1) then
                              begin
                                Dec(record_limit);
                                Continue;
                              end;

                            AbortRecord:=False;
                            { Make sure an absolute variable doesn't alias to it }
                            for Y:=0 to SymCount do
                              if (X<>Y) and
                                (TSym(current_procinfo.procdef.localst.SymList[X]).typ=absolutevarsym) and
                                (TAbsoluteVarSym(current_procinfo.procdef.localst.SymList[X]).abstyp=tovar) and
                                (TAbsoluteVarSym(current_procinfo.procdef.localst.SymList[X]).ref.firstsym^.sltype=sl_load) and
                                (TAbsoluteVarSym(current_procinfo.procdef.localst.SymList[X]).ref.firstsym^.sym=CurrentSym) then
                                begin
                                  { Don't take any chances }
                                  AbortRecord:=True;
                                  Break;
                                end;

                            if AbortRecord then
                              Continue;

                            { Check to see that the symbol isn't directly accessed as one }
                            if foreachnodestatic(pm_postprocess, n, @recorddirectaccess, CurrentSym) then
                              Continue;

                            RecordData.BaseSymbol:=TAbstractVarSym(CurrentSym);
                            RecordData.Depth:=0;

                            foreachnodestatic(pm_postprocess, n, @recordloopfindrefs, @RecordData);
                          end
                        else if
                          (
                            tstoreddef(TAbstractVarSym(CurrentSym).vardef).is_intregable and
                            (TAbstractVarSym(CurrentSym).vardef.size<=sizeof(aint))
                          ) or
                          tstoreddef(TAbstractVarSym(CurrentSym).vardef).is_fpuregable or
                          (
                            is_vector(tstoreddef(TAbstractVarSym(CurrentSym).vardef)) and
                            fits_in_mm_register(tstoreddef(TAbstractVarSym(CurrentSym).vardef))
                          ) then
                          begin
                            if foreachnodestatic(pm_postprocess, n, @recorddirectaccess, CurrentSym) then
                              { This simple type is likely to become a register, so reduce the limit }
                              Dec(record_limit);
                          end;
                      end;
                  end;

                { Fields whose address escapes into a call cannot be promoted }
                ThisTemp:=TFieldTempPair(RecordData.Fields.First);
                while Assigned(ThisTemp) do
                  begin
                    NextTemp:=TFieldTempPair(ThisTemp.Next);
                    if ThisTemp.AddressEscapes then
                      begin
                        ThisTemp.TempCreate.Free;
                        RecordData.Fields.Remove(ThisTemp);
                      end;
                    ThisTemp:=NextTemp;
                  end;

                if (RecordData.Fields.Count > 0) and
                  { If record_limit has gone negative, it may be that there are
                    too many potential regable variables that aren't records,
                    and in extreme cases the count may still be negative even
                    if all of the non-record variables are discounted }
                  (RecordData.Fields.Count + record_limit > 0) then
                  begin
                    { If we have too many record fields to potentially optimise,
                      start excluding ones that give a low return }
                    while (RecordData.Fields.Count > record_limit) do
                      begin
                        MinScore:=$7FFFFFFF;
                        NextTemp:=nil;

                        ThisTemp:=TFieldTempPair(RecordData.Fields.First);
                        while Assigned(ThisTemp) do
                          begin
                            if (ThisTemp.Score<MinScore) then
                              begin
                                NextTemp:=ThisTemp;
                                MinScore:=ThisTemp.Score;
                              end;

                            ThisTemp:=TFieldTempPair(ThisTemp.Next);
                          end;

                        if not Assigned(NextTemp) then
                          { No more temps }
                          Break;

                        TFieldTempPair(NextTemp).TempCreate.Free;
                        RecordData.Fields.Remove(NextTemp);
                      end;

                    { Now that inefficient ones have been removed, replace the subscript nodes }
                    if (RecordData.Fields.Count > 0) and
                      foreachnodestatic(pm_postprocess, n, @recordloopreplacerefs, @RecordData) then
                      begin
                        { Since the loop has had temprefs inserted, put
                          the relevant tempcreates and tempdeletes before
                          and after it. }
                        NewBlock:=internalstatements(NewWrapper);
                        ThisTemp:=TFieldTempPair(RecordData.Fields.First);
                        while Assigned(ThisTemp) do
                          begin
                            ThisTemp.TempCreate.fileinfo:=n.fileinfo;
                            addstatement(NewWrapper, ThisTemp.TempCreate);
                            if ThisTemp.InitialRead or (ThisTemp.FirstDepth<>0) then
                              begin
                                NewNode:=cassignmentnode.create_internal( { Suppress uninitialized value warning }
                                  ctemprefnode.create(
                                    ThisTemp.TempCreate
                                  ),
                                  csubscriptnode.create(
                                    ThisTemp.Field,
                                    cloadnode.create(ThisTemp.BaseSymbol,current_procinfo.procdef.localst)
                                  )
                                );
                                NewNode.fileinfo:=n.fileinfo;
                                addstatement(NewWrapper,NewNode);
                              end;
                            ThisTemp:=TFieldTempPair(ThisTemp.Next);
                          end;

                        { If NewCopy is assigned, then it contains a block
                          created during a previous iteration of this
                          function's for-loop, which includes the original
                          loop node, so insert that instead }
                        NewCopy:=n.getcopy();
                        node_reset_flags(NewCopy,[],[tnf_pass1_done]);
                        Include(NewCopy.flags, nf_internal); { Prevents this simplification pass from happening again }
                        addstatement(NewWrapper, NewCopy);

                        ThisTemp:=TFieldTempPair(RecordData.Fields.Last);
                        while Assigned(ThisTemp) do
                          begin
                            if ThisTemp.FieldWritten then
                              begin
                                { Write the value back to the record }

                                NewNode:=cassignmentnode.create(
                                  csubscriptnode.create(
                                    ThisTemp.Field,
                                    cloadnode.create(ThisTemp.BaseSymbol,current_procinfo.procdef.localst)
                                  ),
                                  ctemprefnode.create(
                                    ThisTemp.TempCreate
                                  )
                                );
                                NewNode.pass_typecheck;
                                NewNode.fileinfo:=n.fileinfo;
                                addstatement(NewWrapper, NewNode);
                              end
                            else
                              { Might produce a more efficient temp }
                              ThisTemp.TempCreate.tempflags:=ThisTemp.TempCreate.tempflags+[ti_const];

                            NewNode:=CTempDeleteNode.create(ThisTemp.TempCreate);
                            NewNode.fileinfo:=n.fileinfo;
                            addstatement(NewWrapper, NewNode);
                            ThisTemp:=TFieldTempPair(ThisTemp.Previous);
                          end;

                        n.Free;
                        n:=NewBlock;
                        n.pass_typecheck;
                        Result:=fen_true;

                        { Keep track of the old block in case more than one
                          local record appears in the loop }
                      end;
                  end;
              end;

            RecordData.Fields.Free;
          end;
      end;

    function optimize_record_writes(var n: tnode): boolean;
      begin
        Result:=foreachnodestatic(pm_preprocess,n,@_optimize_record_writes,nil);
      end;


    type
      toptimizeforloopcontext = object
        changedforloop : boolean;
      end;

    function OptimizeForLoop_iterforloops(var n: tnode; arg: pointer): foreachnoderesult;

      { The reverted loop runs "to - from + 1" times, and that count is
        computed and stored in the counter's own type.  It must be provably
        representable there: a wrapped count runs the wrong number of times
        (a full-range loop became empty, an empty loop with a runtime bound
        became almost-full-range).  A constant "from" of exactly 1 is safe
        for any runtime "to" - the count equals "to" itself; anything else
        needs both bounds constant and the count checked in the wide domain. }
      function reverted_count_representable(f: tfornode): boolean;
        var
          fromval,physmin,physmax: Tconstexprint;
        begin
          fromval:=get_ordinal_value(f.right);
          if fromval=1 then
            exit(true);
          if not is_constnode(f.t1) then
            exit(false);
          get_physical_ord_range(f.left.resultdef,physmin,physmax);
          result:=
            (get_ordinal_value(f.t1)>=fromval-1) and
            (get_ordinal_value(f.t1)-fromval+1<=physmax);
        end;

      begin
        Result:=fen_false;
        if (n.nodetype=forn) and
          not(lnf_backward in tfornode(n).loopflags) and
          not(assigned(tfornode(n).loopstep)) and
          (lnf_dont_mind_loopvar_on_exit in tfornode(n).loopflags) and
          is_constintnode(tfornode(n).right) and
          reverted_count_representable(tfornode(n)) and
          (([cs_check_overflow,cs_check_range]*n.localswitches)=[]) and
          (([cs_check_overflow,cs_check_range]*tfornode(n).left.localswitches)=[]) and
          ((tfornode(n).left.nodetype=loadn) and (tloadnode(tfornode(n).left).symtableentry is tabstractvarsym) and
            not(tabstractvarsym(tloadnode(tfornode(n).left).symtableentry).addr_taken) and
            not(tabstractvarsym(tloadnode(tfornode(n).left).symtableentry).different_scope)) then
          begin
            { do we have DFA available? }
            if pi_dfaavailable in current_procinfo.flags then
              begin
                CalcUseSum(tfornode(n).t2);
                CalcDefSum(tfornode(n).t2);
              end
            else
              Internalerror(2017122801);
            if not(assigned(tfornode(n).left.optinfo)) then
              exit;
            if not(DynSetIn(tfornode(n).t2.optinfo^.usesum,tfornode(n).left.optinfo^.index)) and
              not(DynSetIn(tfornode(n).t2.optinfo^.defsum,tfornode(n).left.optinfo^.index))  then
              begin
                { convert the loop from i:=a to b into i:=b-a+1 to 1 as this simplifies the
                  abort condition }
{$ifdef DEBUG_OPTFORLOOP}
                writeln('**********************************************************************************');
                writeln('Found loop for reverting: ');
                printnode(output,n);
                writeln('**********************************************************************************');
{$endif DEBUG_OPTFORLOOP}
                include(tfornode(n).loopflags,lnf_backward);
                tfornode(n).right:=ctypeconvnode.create_internal(
                  caddnode.create_internal(addn,caddnode.create_internal(subn,
                    tfornode(n).t1,tfornode(n).right),
                    cordconstnode.create(1,tfornode(n).left.resultdef,false)),
                  tfornode(n).left.resultdef);
                tfornode(n).t1:=cordconstnode.create(1,tfornode(n).left.resultdef,false);
                include(tfornode(n).loopflags,lnf_counter_not_used);
                exclude(n.transientflags,tnf_pass1_done);
                do_firstpass(n);
{$ifdef DEBUG_OPTFORLOOP}
                writeln('Loop reverted: ');
                printnode(output,n);
                writeln('**********************************************************************************');
{$endif DEBUG_OPTFORLOOP}
                toptimizeforloopcontext(arg^).changedforloop:=true;
              end;
          end;
      end;


    function OptimizeForLoop(var node : tnode) : boolean;
      var
        ctx : toptimizeforloopcontext;
      begin
        ctx.changedforloop:=false;
        if pi_dfaavailable in current_procinfo.flags then
          foreachnodestatic(pm_postprocess,node,@OptimizeForLoop_iterforloops,@ctx);
        Result:=ctx.changedforloop;
      end;

end.

