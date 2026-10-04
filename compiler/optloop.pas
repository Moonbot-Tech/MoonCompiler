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
{ $define DEBUG_OPTLICM}

  interface

    uses
      node,
      procinfo;

    function unroll_loop(node : tnode) : tnode;
    procedure finish_loop_unrolling(var node : tnode);
    function OptimizeInductionVariables(node : tnode) : boolean;
    function optimize_record_writes(var n: tnode): boolean;
    function OptimizeForLoop(var node : tnode) : boolean;
    function OptimizeLoopInvariants(var node : tnode) : boolean;
    function OptimizeLoopVectorBases(var node : tnode) : boolean;
    { reads from the trees of pi and of the routines nested in it, which are
      as parsed, what each routine does to the routines around it }
    procedure collect_nested_access(pi : tprocinfo);

  implementation

    uses
      cclasses,cutils,compinnr,cdynset,
      globtype,globals,constexp,
{$ifdef i386}
      cpuinfo,
{$endif i386}
      verbose,
      symbase,symconst,symdef,symsym,symtable,symtype,
      defcmp,
      defutil,
      nutils,
      nadd,nbas,nflw,ncon,ninl,ncal,nld,nmem,ncnv,nset,
      ncgmem,
      pass_1,
      optbase,optutils,
      psub,
      opteffect;

    { Full unrolling used to run while each statement was parsed and
      typechecked.  At that point an enclosing source-level defer has not yet
      been lowered to its try/finally and later handlers may not even have
      been parsed, so the optimizer cannot know which counter states are
      observable on an exceptional edge.  Every eligible for is now merely
      marked by pass_typecheck and this pass makes the decision from the
      complete typed routine tree. }


    type
      plooplist = ^tlooplist;
      tlooplist = record
        loops : tfplist;
      end;

      tlivenesscacheentry = record
        node : tnode;
        context : sizeint;
        known,
        values : qword;
      end;
      tlivenesscacheentries = array of tlivenesscacheentry;
      tlabellivenessentry = record
        node : tlabelnode;
        context : sizeint;
        live : boolean;
      end;
      tlabellivenessentries = array of tlabellivenessentry;
      tlivenesscontextentry = record
        finalizer : tnode;
        continuation : byte;
      end;
      tlivenesscontextentries = array of tlivenesscontextentry;
      plivenesscache = ^tlivenesscache;
      tlivenesscache = record
        entries : tlivenesscacheentries;
        count : sizeint;
        labels : tlabellivenessentries;
        contexts : tlivenesscontextentries;
        labels_changed : boolean;
      end;
      tflowcontinuations = record
        normal,
        exceptional,
        procedure_exit,
        loop_break,
        loop_continue,
        { A call may enter an outer label through an explicitly enabled
          non-local goto.  Keep this separate from exceptional flow: checked
          arithmetic and other traps cannot take that edge. }
        nonlocal_goto : boolean;
        { Identity of the current duplicated-finalizer invocation.  It is not
          a liveness bit and therefore is deliberately absent from
          continuation_key. }
        label_context : sizeint;
        { The source for whose counter this one-bit solve is running.  These
          fields do not change liveness itself; they attach an already proven
          live abrupt edge to the exact loop whose counter must remain in its
          source state. }
        observed_loop : tfornode;
        observed_loop_labels : tfplist;
        break_exits_observed_loop : boolean;
      end;

    function collect_liveness_label(var n : tnode;
      arg : pointer) : foreachnoderesult;
      var
        cache : plivenesscache;
        index : sizeint;
      begin
        result:=fen_false;
        if n.nodetype<>labeln then
          exit;
        cache:=plivenesscache(arg);
        index:=length(cache^.labels);
        setlength(cache^.labels,index+1);
        cache^.labels[index].node:=tlabelnode(n);
        cache^.labels[index].context:=0;
        cache^.labels[index].live:=false;
      end;


    function liveness_label_index(cache : plivenesscache;
      labelnode : tlabelnode; context : sizeint; create : boolean) : sizeint;
      var
        index : sizeint;
      begin
        for result:=0 to high(cache^.labels) do
          if (cache^.labels[result].node=labelnode) and
             (cache^.labels[result].context=context) then
            exit;
        if create then
          begin
            index:=length(cache^.labels);
            setlength(cache^.labels,index+1);
            cache^.labels[index].node:=labelnode;
            cache^.labels[index].context:=context;
            cache^.labels[index].live:=false;
            exit(index);
          end;
        result:=-1;
      end;


    function continuation_key(const continuations : tflowcontinuations) : byte; inline;
      begin
        result:=ord(continuations.normal) or
          (ord(continuations.exceptional) shl 1) or
          (ord(continuations.procedure_exit) shl 2) or
          (ord(continuations.loop_break) shl 3) or
          (ord(continuations.loop_continue) shl 4) or
          (ord(continuations.nonlocal_goto) shl 5);
      end;


    function finalizer_liveness_context(cache : plivenesscache;
      finalizer : tnode; continuation : byte) : sizeint;
      var
        i : sizeint;
      begin
        { One finalizer AST is executed for normal, exceptional and abrupt
          completion.  Its internal labels therefore need one fixed point per
          incoming continuation.  The pair below is the complete semantic
          key for this one-bit query; including the caller context would only
          duplicate equivalent nested-finalizer problems exponentially. }
        for i:=0 to high(cache^.contexts) do
          if (cache^.contexts[i].finalizer=finalizer) and
             (cache^.contexts[i].continuation=continuation) then
            exit(i+1);
        i:=length(cache^.contexts);
        setlength(cache^.contexts,i+1);
        cache^.contexts[i].finalizer:=finalizer;
        cache^.contexts[i].continuation:=continuation;
        result:=i+1;
      end;


    procedure publish_label_liveness(cache : plivenesscache;
      labelnode : tlabelnode; context : sizeint; live : boolean);
      var
        index : sizeint;
      begin
        if not live then
          exit;
        index:=liveness_label_index(cache,labelnode,context,true);
        if (index>=0) and not cache^.labels[index].live then
          begin
            cache^.labels[index].live:=true;
            cache^.labels_changed:=true;
          end;
      end;


    function resolved_goto_target(n : tgotonode) : tlabelnode;
      begin
        result:=n.labelnode;
        if not assigned(result) and assigned(n.labelsym) and
           assigned(n.labelsym.code) and
           (tnode(n.labelsym.code).nodetype=labeln) then
          result:=tlabelnode(n.labelsym.code);
      end;

    function liveness_cache_slot(const cache : tlivenesscache;
      n : tnode; context : sizeint) : sizeint; inline;
      var
        hash : ptruint;
      begin
        hash:=(ptruint(n) shr 4) xor (ptruint(n) shr 13) xor
          (ptruint(context)*ptruint($9e3779b1));
        result:=hash and high(cache.entries);
        while assigned(cache.entries[result].node) and
              ((cache.entries[result].node<>n) or
               (cache.entries[result].context<>context)) do
          result:=(result+1) and high(cache.entries);
      end;


    procedure liveness_cache_grow(var cache : tlivenesscache);
      var
        oldentries : tlivenesscacheentries;
        i,
        slot : sizeint;
      begin
        oldentries:=cache.entries;
        cache.entries:=nil;
        if length(oldentries)=0 then
          setlength(cache.entries,64)
        else
          setlength(cache.entries,length(oldentries)*2);
        cache.count:=0;
        for i:=0 to high(oldentries) do
          if assigned(oldentries[i].node) then
            begin
              slot:=liveness_cache_slot(cache,oldentries[i].node,
                oldentries[i].context);
              cache.entries[slot]:=oldentries[i];
              inc(cache.count);
            end;
      end;


    function liveness_cache_lookup(cache : plivenesscache; n : tnode;
      const continuations : tflowcontinuations; out value : boolean) : boolean;
      var
        slot : sizeint;
        mask : qword;
      begin
        result:=false;
        if length(cache^.entries)=0 then
          exit;
        slot:=liveness_cache_slot(cache^,n,continuations.label_context);
        if (cache^.entries[slot].node<>n) or
           (cache^.entries[slot].context<>continuations.label_context) then
          exit;
        mask:=qword(1) shl continuation_key(continuations);
        if cache^.entries[slot].known and mask=0 then
          exit;
        value:=cache^.entries[slot].values and mask<>0;
        result:=true;
      end;


    procedure liveness_cache_store(cache : plivenesscache; n : tnode;
      const continuations : tflowcontinuations; value : boolean);
      var
        slot : sizeint;
        mask : qword;
      begin
        if (length(cache^.entries)=0) or
           (cache^.count*4>=length(cache^.entries)*3) then
          liveness_cache_grow(cache^);
        slot:=liveness_cache_slot(cache^,n,continuations.label_context);
        if not assigned(cache^.entries[slot].node) then
          begin
            cache^.entries[slot].node:=n;
            cache^.entries[slot].context:=continuations.label_context;
            inc(cache^.count);
          end;
        mask:=qword(1) shl continuation_key(continuations);
        cache^.entries[slot].known:=cache^.entries[slot].known or mask;
        if value then
          cache^.entries[slot].values:=cache^.entries[slot].values or mask
        else
          cache^.entries[slot].values:=cache^.entries[slot].values and not mask;
      end;

    function collect_local_for_loop(var n : tnode;
      arg : pointer) : foreachnoderesult;
      begin
        result:=fen_false;
        { Counter observability is a property of the source loop, not of the
          optimization which happens to consume it.  In particular, loop
          reversal also rewrites the counter when LOOPUNROLL is disabled. }
        if n.nodetype=forn then
          plooplist(arg)^.loops.add(n);
      end;


    function find_loop_observer_analysis_source(var n : tnode;
      arg : pointer) : foreachnoderesult;
      begin
        if (n.nodetype=forn) and
           (tnf_loop_observer_analysis_source in n.transientflags) then
          result:=fen_norecurse_true
        else
          result:=fen_false;
      end;


    function exact_for_counter_sym(n : tfornode) : tabstractvarsym;
      var
        counter : tnode;
      begin
        { Use the compiler-wide lvalue identity rule.  In particular, an
          implicit function Result may be wrapped in a location-preserving
          conversion even though it is the exact same counter storage. }
        counter:=actualtargetnode(@n.left)^;
        if (counter.nodetype=loadn) and
           (tloadnode(counter).symtableentry is tabstractvarsym) then
          result:=tabstractvarsym(tloadnode(counter).symtableentry)
        else
          result:=nil;
      end;


    function effect_may_trap(n : tnode) : boolean;
      var
        effect : teffect;
      begin
        effect_init(effect);
        try
          tree_effect(n,effect);
          result:=ie_trap in effect.ieffects;
        finally
          effect_done(effect);
        end;
      end;


    function find_call_node(var n : tnode; arg : pointer) : foreachnoderesult;
      begin
        if n.nodetype=calln then
          result:=fen_norecurse_true
        else
          result:=fen_false;
      end;


    function tree_has_call(n : tnode) : boolean;
      begin
        result:=assigned(n) and
          foreachnodestatic(n,@find_call_node,nil);
      end;


    function proc_summary_reaches_target(pd : tprocdef;
      target : tlabelsym; visited : tfplist) : boolean;
      var
        i : longint;
        callee : tprocdef;
      begin
        { Missing summaries, virtual/procvar dispatch and calls into an opaque
          body remain conservative.  Only a complete finite call graph may
          prove that one particular non-local continuation is unreachable. }
        if not assigned(pd) or not pd.nonlocal_goto_summary_complete or
           pd.nonlocal_goto_has_opaque_transfer then
          exit(true);
        if assigned(pd.nonlocal_goto_targets) and
           (pd.nonlocal_goto_targets.indexof(target)>=0) then
          exit(true);
        if visited.indexof(pd)>=0 then
          exit(false);
        visited.add(pd);
        if assigned(pd.nonlocal_goto_callees) then
          for i:=0 to pd.nonlocal_goto_callees.count-1 do
            begin
              callee:=tprocdef(pd.nonlocal_goto_callees[i]);
              if proc_summary_reaches_target(callee,target,visited) then
                exit(true);
            end;
        result:=false;
      end;


    function call_reaches_nonlocal_target(call : tcallnode;
      target : tlabelsym) : boolean;
      var
        pd : tprocdef;
        visited : tfplist;
      begin
        if not assigned(call.procdefinition) or
           (call.procdefinition.typ<>procdef) then
          exit(true);
        pd:=tprocdef(call.procdefinition);
        if ((po_virtualmethod in pd.procoptions) and
            not(cnf_inherited in call.callnodeflags)) or
           (po_abstractmethod in pd.procoptions) then
          exit(true);
        { Lexical ownership is not enough to subtract a target here: an
          opaque callback can jump into an older recursive activation of the
          same procdef.  Exactness comes from the reachable target graph, not
          from equating a procdef with one runtime frame. }
        visited:=tfplist.create;
        try
          result:=proc_summary_reaches_target(pd,target,visited);
        finally
          visited.free;
        end;
      end;


    function call_reaches_live_nonlocal_entry(call : tcallnode;
      cache : plivenesscache) : boolean;
      var
        i : sizeint;
        labelsym : tlabelsym;
      begin
        for i:=0 to high(cache^.labels) do
          if cache^.labels[i].live and
             assigned(cache^.labels[i].node.labsym) and
             cache^.labels[i].node.labsym.has_nonlocal_entry then
            begin
              labelsym:=cache^.labels[i].node.labsym;
              if call_reaches_nonlocal_target(call,labelsym) then
                exit(true);
            end;
        result:=false;
      end;


    type
      pnonlocalcallsearch = ^tnonlocalcallsearch;
      tnonlocalcallsearch = record
        cache : plivenesscache;
      end;

    function node_may_transfer_via_runtime(n : tnode) : boolean;
      var
        effect : teffect;
      begin
        effect_init(effect);
        try
          node_effect(n,effect);
          result:=ie_trap in effect.ieffects;
        finally
          effect_done(effect);
        end;
      end;


    type
      poptloopeffect = ^teffect;

    procedure reset_effect_scratch(effect : poptloopeffect); inline;
      begin
        effect^.rclasses:=[];
        effect^.wclasses:=[];
        effect^.ieffects:=[];
        if assigned(effect^.rsyms) then
          effect^.rsyms.clear;
        if assigned(effect^.wsyms) then
          effect^.wsyms.clear;
        effect^.runbounded:=false;
        effect^.wunbounded:=false;
        effect^.hastemps:=false;
      end;


    function find_opaque_runtime_transfer(var n : tnode;
      arg : pointer) : foreachnoderesult;
      begin
        { Direct calls are represented by exact/opaque callee edges.  Their
          arguments are still walked because evaluating an argument may call
          a hidden helper or a user runtime hook before control reaches the
          callee. }
        if n.nodetype=calln then
          result:=fen_false
        else if effect_node_proven_trap_free_norecurse(n) then
          result:=fen_false
        else
          begin
            { This routine-wide summary used to allocate and destroy the
              effect model's exact-symbol lists for every visited node.  One
              reusable shallow query has identical semantics and keeps the
              mandatory summary pass linear without per-node heap traffic. }
            reset_effect_scratch(poptloopeffect(arg));
            node_effect(n,poptloopeffect(arg)^);
            if ie_trap in poptloopeffect(arg)^.ieffects then
              result:=fen_norecurse_true
            else
              result:=fen_false;
          end;
      end;


    function tree_has_opaque_runtime_transfer(n : tnode) : boolean;
      var
        effect : teffect;
      begin
        effect_init(effect);
        try
          result:=foreachnodestatic(n,@find_opaque_runtime_transfer,@effect);
        finally
          effect_done(effect);
        end;
      end;


    function find_operation_reaching_live_nonlocal_entry(var n : tnode;
      arg : pointer) : foreachnoderesult;
      begin
        if ((n.nodetype=calln) and
            call_reaches_live_nonlocal_entry(tcallnode(n),
              pnonlocalcallsearch(arg)^.cache)) or
           ((n.nodetype<>calln) and node_may_transfer_via_runtime(n)) then
          result:=fen_norecurse_true
        else
          result:=fen_false;
      end;


    function tree_has_operation_reaching_live_nonlocal_entry(n : tnode;
      cache : plivenesscache) : boolean;
      var
        search : tnonlocalcallsearch;
      begin
        search.cache:=cache;
        result:=assigned(n) and foreachnodestatic(n,
          @find_operation_reaching_live_nonlocal_entry,@search);
      end;


    function operation_live_in(n : tnode; sym : tabstractvarsym;
      normal_live : boolean; const continuations : tflowcontinuations;
      cache : plivenesscache) : boolean;
      begin
        { Every evaluated operation has the same three possible successors:
          its ordinary continuation, exception unwinding, and a runtime/user
          callback which can enter a live outer label.  Keep that transfer in
          one place so conditions, bounds, return expressions and hidden
          helpers cannot silently acquire different liveness semantics. }
        result:=effect_local_live_in(n,sym,normal_live);
        if continuations.exceptional and effect_may_trap(n) then
          result:=true;
        if continuations.nonlocal_goto and
           tree_has_operation_reaching_live_nonlocal_entry(n,cache) then
          result:=true;
      end;


    function structural_abrupt_observer_live(n : tnode;
      const continuations : tflowcontinuations) : boolean;
      begin
        { Some source control nodes lower their own runtime checks in addition
          to evaluating child expressions.  Their hook/callback edge must use
          the same abrupt continuations as an ordinary expression; processing
          the children alone is insufficient (notably for the positive-step
          gate of a for loop). }
        result:=node_may_transfer_via_runtime(n) and
          (continuations.exceptional or continuations.nonlocal_goto);
      end;


    function analyze_loop_exception_liveness(n : tnode;
      sym : tabstractvarsym;
      const continuations : tflowcontinuations;
      cache : plivenesscache) : boolean; forward;

    function loop_has_local_abrupt_exit(loop : tfornode) : boolean; forward;

    function collect_loop_label(var n : tnode;
      arg : pointer) : foreachnoderesult; forward;


    procedure mark_observed_loop_abrupt(
      const continuations : tflowcontinuations; live : boolean); inline;
      begin
        if live and assigned(continuations.observed_loop) then
          include(continuations.observed_loop.transientflags,
            tnf_loopvar_observable_on_abrupt_exit);
      end;


    function analyze_exception_handlers(n : tnode;
      sym : tabstractvarsym;
      const continuations : tflowcontinuations; unmatched_live : boolean;
      cache : plivenesscache) : boolean;
      var
        body_live,
        next_live : boolean;
      begin
        if not assigned(n) then
          begin
            result:=unmatched_live;
            exit;
          end;
        if n.nodetype<>onn then
          begin
            { Generated trees should use an on chain here.  Treat any other
              node as another dispatch alternative instead of inventing
              sequential execution between mutually exclusive handlers. }
            result:=analyze_loop_exception_liveness(n,sym,
              continuations,cache) or unmatched_live;
            exit;
          end;
        body_live:=analyze_loop_exception_liveness(tbinarynode(n).right,
          sym,continuations,cache);
        next_live:=analyze_exception_handlers(tbinarynode(n).left,
          sym,continuations,unmatched_live,cache);
        result:=body_live or next_live;
      end;


    function analyze_loop_exception_liveness(n : tnode;
      sym : tabstractvarsym;
      const continuations : tflowcontinuations;
      cache : plivenesscache) : boolean;
      var
        statement : tstatementnode;
        labelnode : tlabelnode;
        labelindex : sizeint;
        branch_live,
        loop_live,
        old_loop_live,
        condition_live,
        latch_live,
        postinit_live,
        other_live,
        handler_live,
        finalizer_live,
        exit_finalizer_live,
        break_finalizer_live,
        continue_finalizer_live : boolean;
        nested_continuations,
        finalizer_continuations : tflowcontinuations;
        counter_sym : tabstractvarsym;
        may_skip : boolean;
        loop_labels : tfplist;
        i : longint;
      begin
        result:=continuations.normal;
        if not assigned(n) then
          exit;
        if liveness_cache_lookup(cache,n,continuations,result) then
          exit;
        case n.nodetype of
          blockn:
            result:=analyze_loop_exception_liveness(tblocknode(n).left,
              sym,continuations,cache);
          statementn:
            begin
              { A statement list is singly linked in source order.  Recurse
                into the tail first so the current statement receives the
                exact liveness of its continuation. }
              statement:=tstatementnode(n);
              result:=analyze_loop_exception_liveness(statement.right,
                sym,continuations,cache);
              nested_continuations:=continuations;
              nested_continuations.normal:=result;
              result:=analyze_loop_exception_liveness(statement.left,sym,
                nested_continuations,cache);
            end;
          ifn:
            begin
              branch_live:=analyze_loop_exception_liveness(tifnode(n).right,
                sym,continuations,cache);
              if assigned(tifnode(n).t1) then
                begin
                  other_live:=analyze_loop_exception_liveness(tifnode(n).t1,
                    sym,continuations,cache);
                  branch_live:=branch_live or other_live;
                end
              else
                branch_live:=branch_live or continuations.normal;
              result:=operation_live_in(tifnode(n).left,sym,branch_live,
                continuations,cache);
            end;
          casen:
            begin
              branch_live:=analyze_loop_exception_liveness(
                tcasenode(n).elseblock,sym,continuations,cache);
              if not assigned(tcasenode(n).elseblock) then
                branch_live:=continuations.normal;
              for i:=0 to tcasenode(n).blocks.count-1 do
                begin
                  other_live:=analyze_loop_exception_liveness(
                    pcaseblock(tcasenode(n).blocks[i])^.statement,
                    sym,continuations,cache);
                  branch_live:=branch_live or other_live;
                end;
              result:=operation_live_in(tcasenode(n).left,sym,branch_live,
                continuations,cache);
            end;
          tryexceptn:
            begin
              { A default block is a catch-all.  Without one, only an
                unmatched exception continues to the enclosing handler. }
              if assigned(ttryexceptnode(n).t1) then
                other_live:=analyze_loop_exception_liveness(
                  ttryexceptnode(n).t1,sym,continuations,cache)
              else
                other_live:=continuations.exceptional;
              { Typed on-handlers are dispatch alternatives, not a sequence:
                a matched body continues after the try/except while a miss
                advances to the next handler/default. }
              handler_live:=analyze_exception_handlers(
                ttryexceptnode(n).right,sym,continuations,
                other_live,cache);
              nested_continuations:=continuations;
              nested_continuations.exceptional:=handler_live;
              result:=analyze_loop_exception_liveness(ttryexceptnode(n).left,
                sym,nested_continuations,cache);
            end;
          tryfinallyn:
            begin
              { A finalizer runs while unwinding every kind of control flow.
                Its normal successor is the original continuation for that
                reason, while a new exception/exit/break/continue raised by
                the finalizer uses the corresponding enclosing continuation. }
              finalizer_continuations:=continuations;
              finalizer_continuations.label_context:=
                finalizer_liveness_context(cache,ttryfinallynode(n).right,
                  continuation_key(finalizer_continuations));
              finalizer_live:=analyze_loop_exception_liveness(
                ttryfinallynode(n).right,sym,
                finalizer_continuations,cache);
              finalizer_continuations.normal:=continuations.exceptional;
              finalizer_continuations.label_context:=
                finalizer_liveness_context(cache,ttryfinallynode(n).right,
                  continuation_key(finalizer_continuations));
              other_live:=analyze_loop_exception_liveness(
                ttryfinallynode(n).right,sym,
                finalizer_continuations,cache);
              finalizer_continuations.normal:=continuations.procedure_exit;
              finalizer_continuations.label_context:=
                finalizer_liveness_context(cache,ttryfinallynode(n).right,
                  continuation_key(finalizer_continuations));
              exit_finalizer_live:=analyze_loop_exception_liveness(
                ttryfinallynode(n).right,sym,
                finalizer_continuations,cache);
              finalizer_continuations.normal:=continuations.loop_break;
              finalizer_continuations.label_context:=
                finalizer_liveness_context(cache,ttryfinallynode(n).right,
                  continuation_key(finalizer_continuations));
              break_finalizer_live:=analyze_loop_exception_liveness(
                ttryfinallynode(n).right,sym,
                finalizer_continuations,cache);
              finalizer_continuations.normal:=continuations.loop_continue;
              finalizer_continuations.label_context:=
                finalizer_liveness_context(cache,ttryfinallynode(n).right,
                  continuation_key(finalizer_continuations));
              continue_finalizer_live:=analyze_loop_exception_liveness(
                ttryfinallynode(n).right,sym,
                finalizer_continuations,cache);
              nested_continuations:=continuations;
              nested_continuations.normal:=finalizer_live;
              nested_continuations.exceptional:=other_live;
              nested_continuations.procedure_exit:=exit_finalizer_live;
              nested_continuations.loop_break:=break_finalizer_live;
              nested_continuations.loop_continue:=continue_finalizer_live;
              result:=analyze_loop_exception_liveness(ttryfinallynode(n).left,
                sym,nested_continuations,cache);
            end;
          onn:
            begin
              { Normally handled by the enclosing try/except so dispatch
                alternatives can be joined.  Keep standalone/generated on
                nodes conservative, including an unmatched outer edge. }
              result:=analyze_exception_handlers(n,sym,continuations,
                continuations.exceptional,cache);
            end;
          forn:
            begin
              { Solve the body/backedge equation instead of pretending every
                loop backedge observes the local.  The scalar lattice has two
                values, so this converges after at most one false-to-true
                transition (label equations may request another outer pass). }
              counter_sym:=exact_for_counter_sym(tfornode(n));
              loop_live:=false;
              loop_labels:=nil;
              if counter_sym=sym then
                begin
                  loop_labels:=tfplist.create;
                  foreachnodestatic(tfornode(n).t2,@collect_loop_label,
                    loop_labels);
                end;
              try
                repeat
                  old_loop_live:=loop_live;
                  latch_live:=continuations.normal or loop_live or
                    (counter_sym=sym);
                  nested_continuations:=continuations;
                  nested_continuations.normal:=latch_live;
                  nested_continuations.loop_break:=continuations.normal;
                  nested_continuations.loop_continue:=latch_live;
                  if counter_sym=sym then
                    begin
                      nested_continuations.observed_loop:=tfornode(n);
                      nested_continuations.observed_loop_labels:=loop_labels;
                      nested_continuations.break_exits_observed_loop:=true;
                    end
                  else if assigned(continuations.observed_loop) then
                    { A break in this nested loop does not leave the observed
                      outer loop.  Goto and procedure exit are still tracked. }
                    nested_continuations.break_exits_observed_loop:=false;
                  branch_live:=analyze_loop_exception_liveness(tfornode(n).t2,
                    sym,nested_continuations,cache);
                  loop_live:=loop_live or branch_live;
                until loop_live=old_loop_live;
              finally
                loop_labels.free;
              end;
              { One solve is shared by every loop which uses this exact
                counter symbol; liveness depends on the declaration, not on
                the identity of one loop node. }
              if (counter_sym=sym) and continuations.normal then
                include(n.transientflags,
                  tnf_loopvar_observable_on_normal_exit);
              if (counter_sym=sym) and continuations.exceptional and
                 (effect_may_trap(tfornode(n).t2) or
                  node_may_transfer_via_runtime(n)) then
                include(n.transientflags,
                  tnf_loopvar_observable_on_abrupt_exit);
              if (counter_sym=sym) and continuations.nonlocal_goto and
                 (tree_has_operation_reaching_live_nonlocal_entry(
                    tfornode(n).t2,cache) or
                  node_may_transfer_via_runtime(n)) then
                include(n.transientflags,
                  tnf_loopvar_observable_on_abrupt_exit);
              { Transfer from the body entry back across the evaluate-once
                bounds and counter initialization.  A step loop always writes
                the counter before its initial range gate.  An ordinary loop
                with runtime bounds may skip that write, so its after-loop
                continuation remains live on the empty path. }
              if assigned(counter_sym) then
                begin
                  if counter_sym=sym then
                    begin
                      if assigned(tfornode(n).loopstep) then
                        may_skip:=false
                      else if is_constnode(tfornode(n).right) and
                              is_constnode(tfornode(n).t1) then
                        if lnf_backward in tfornode(n).loopflags then
                          may_skip:=get_ordinal_value(tfornode(n).right)<
                            get_ordinal_value(tfornode(n).t1)
                        else
                          may_skip:=get_ordinal_value(tfornode(n).right)>
                            get_ordinal_value(tfornode(n).t1)
                      else
                        may_skip:=true;
                      postinit_live:=may_skip and continuations.normal;
                    end
                  else
                    postinit_live:=loop_live or continuations.normal;

                  result:=operation_live_in(tfornode(n).right,sym,
                    postinit_live,continuations,cache);
                  result:=operation_live_in(tfornode(n).t1,sym,result,
                    continuations,cache);
                  if assigned(tfornode(n).loopstep) then
                    begin
                      result:=operation_live_in(tfornode(n).loopstep,sym,
                        result,continuations,cache);
                    end;
                  if structural_abrupt_observer_live(n,continuations) then
                    result:=true;
                end
              else
                { Complex TP-style lvalues have address computations which
                  this exact-local analysis cannot represent. }
                result:=operation_live_in(n,sym,
                  loop_live or continuations.normal,continuations,cache);
            end;
          whilerepeatn:
            begin
              loop_live:=false;
              repeat
                old_loop_live:=loop_live;

                { The condition chooses between another iteration and the
                  ordinary after-loop continuation. }
                nested_continuations:=continuations;
                nested_continuations.normal:=loop_live or
                  continuations.normal;
                condition_live:=analyze_loop_exception_liveness(
                  twhilerepeatnode(n).left,sym,
                  nested_continuations,cache);

                { Generated step loops put their latch in t1.  A source-level
                  continue reaches it before the condition. }
                nested_continuations:=continuations;
                nested_continuations.normal:=condition_live;
                nested_continuations.loop_break:=continuations.normal;
                nested_continuations.loop_continue:=condition_live;
                latch_live:=analyze_loop_exception_liveness(
                  twhilerepeatnode(n).t1,sym,
                  nested_continuations,cache);

                nested_continuations.normal:=latch_live;
                nested_continuations.loop_continue:=latch_live;
                if assigned(continuations.observed_loop) then
                  { A break is owned by the nearest loop independently of its
                    syntax.  This while/repeat is nested in the observed for,
                    so its break remains inside that for. }
                  nested_continuations.break_exits_observed_loop:=false;
                branch_live:=analyze_loop_exception_liveness(
                  twhilerepeatnode(n).right,sym,
                  nested_continuations,cache);
                loop_live:=loop_live or branch_live;
              until loop_live=old_loop_live;

              if lnf_testatbegin in twhilerepeatnode(n).loopflags then
                { Code generation enters a test-at-begin loop at lcont.  A
                  generated latch in t1 executes there before the condition,
                  so its transfer is part of the entry state as well. }
                result:=latch_live
              else
                result:=loop_live;
            end;
          labeln:
            begin
              result:=effect_local_live_in(n,sym,continuations.normal);
              publish_label_liveness(cache,tlabelnode(n),
                continuations.label_context,result);
            end;
          goton:
            begin
              { Same-frame gotos form ordinary data-flow edges even inside an
                exception handler.  Solve their label equations to a least
                fixed point; unresolved/cross-frame targets stay conservative. }
              labelnode:=resolved_goto_target(tgotonode(n));
              if assigned(labelnode) and
                 (tgotonode(n).exceptionblock=labelnode.exceptionblock) then
                begin
                  labelindex:=liveness_label_index(cache,labelnode,
                    continuations.label_context,true);
                  result:=cache^.labels[labelindex].live;
                end
              else
                result:=true;
              if assigned(continuations.observed_loop) and
                 (not assigned(labelnode) or
                  not assigned(continuations.observed_loop_labels) or
                  (continuations.observed_loop_labels.indexof(labelnode)<0)) then
                mark_observed_loop_abrupt(continuations,result);
            end;
          exitn:
            begin
              result:=continuations.procedure_exit;
              if assigned(texitnode(n).left) then
                begin
                  result:=operation_live_in(texitnode(n).left,sym,result,
                    continuations,cache);
                end;
              mark_observed_loop_abrupt(continuations,result);
            end;
          breakn:
            begin
              result:=continuations.loop_break;
              if continuations.break_exits_observed_loop then
                mark_observed_loop_abrupt(continuations,result);
            end;
          continuen:
            result:=continuations.loop_continue;
          calln:
            result:=operation_live_in(n,sym,continuations.normal,
              continuations,cache);
          else
            result:=operation_live_in(n,sym,continuations.normal,
              continuations,cache);
        end;
        liveness_cache_store(cache,n,continuations,result);
      end;


    function live_nonlocal_entry(cache : plivenesscache) : boolean;
      var
        i : sizeint;
      begin
        result:=false;
        for i:=0 to high(cache^.labels) do
          if cache^.labels[i].live and
             assigned(cache^.labels[i].node.labsym) and
             cache^.labels[i].node.labsym.has_nonlocal_entry then
            exit(true);
      end;


    function find_nonlocal_loop_entry(var n : tnode;
      arg : pointer) : foreachnoderesult;
      begin
        if (n.nodetype=labeln) and assigned(tlabelnode(n).labsym) and
           tlabelnode(n).labsym.has_nonlocal_entry then
          result:=fen_norecurse_true
        else
          result:=fen_false;
      end;


    function find_eh_node(var n : tnode;
      arg : pointer) : foreachnoderesult;
      begin
        if n.nodetype in [tryexceptn,tryfinallyn] then
          result:=fen_norecurse_true
        else
          result:=fen_false;
      end;


    function loop_contains_eh(loop : tfornode) : boolean;
      begin
        { A handler/finalizer inside the loop can observe this counter only
          for operations in that loop subtree. }
        result:=assigned(loop.t2) and
          foreachnodestatic(loop.t2,@find_eh_node,nil);
      end;


    type
      plocalabruptsearch = ^tlocalabruptsearch;
      tlocalabruptsearch = record
        labels : tfplist;
      end;

    function collect_loop_label(var n : tnode;
      arg : pointer) : foreachnoderesult;
      begin
        if n.nodetype=labeln then
          tfplist(arg).add(n);
        result:=fen_false;
      end;


    function find_loop_break(var n : tnode;
      arg : pointer) : foreachnoderesult;
      begin
        if n.nodetype=breakn then
          result:=fen_norecurse_true
        else if n.nodetype in [forn,whilerepeatn] then
          { A break owned by a nested loop does not leave the outer loop. }
          result:=fen_norecurse_false
        else
          result:=fen_false;
      end;


    function find_procedure_exit(var n : tnode;
      arg : pointer) : foreachnoderesult;
      begin
        if n.nodetype=exitn then
          result:=fen_norecurse_true
        else
          result:=fen_false;
      end;


    function find_escaping_loop_goto(var n : tnode;
      arg : pointer) : foreachnoderesult;
      var
        target : tlabelnode;
      begin
        if n.nodetype<>goton then
          exit(fen_false);
        target:=resolved_goto_target(tgotonode(n));
        if not assigned(target) or
           (plocalabruptsearch(arg)^.labels.indexof(target)<0) then
          result:=fen_norecurse_true
        else
          result:=fen_false;
      end;


    function loop_has_local_abrupt_exit(loop : tfornode) : boolean;
      var
        search : tlocalabruptsearch;
      begin
        if not assigned(loop.t2) then
          exit(false);
        if foreachnodestatic(loop.t2,@find_loop_break,nil) then
          exit(true);
        if foreachnodestatic(loop.t2,@find_procedure_exit,nil) then
          exit(true);
        search.labels:=tfplist.create;
        try
          foreachnodestatic(loop.t2,@collect_loop_label,search.labels);
          result:=foreachnodestatic(loop.t2,@find_escaping_loop_goto,@search);
        finally
          search.labels.free;
        end;
      end;


    type
      pehloopcollector = ^tehloopcollector;
      tehloopcollector = record
        loops : tfplist;
      end;

    function compare_node_pointers(item1,item2 : pointer) : longint;
      begin
        if ptruint(item1)<ptruint(item2) then
          result:=-1
        else if ptruint(item1)>ptruint(item2) then
          result:=1
        else
          result:=0;
      end;


    procedure sort_unique_nodes(list : tfplist);
      var
        i : longint;
      begin
        list.sort(@compare_node_pointers);
        for i:=list.count-1 downto 1 do
          if list[i]=list[i-1] then
            list.delete(i);
      end;


    function sorted_nodes_contains(list : tfplist; item : pointer) : boolean;
      var
        low,
        high,
        middle : longint;
      begin
        low:=0;
        high:=list.count-1;
        while low<=high do
          begin
            middle:=low+(high-low) div 2;
            if list[middle]=item then
              exit(true)
            else if ptruint(list[middle])<ptruint(item) then
              low:=middle+1
            else
              high:=middle-1;
          end;
        result:=false;
      end;

    function collect_eh_protected_loops(var n : tnode;
      arg : pointer) : foreachnoderesult;
      var
        protected_tree : tnode;
        found : tlooplist;
      begin
        result:=fen_false;
        case n.nodetype of
          tryexceptn:
            protected_tree:=ttryexceptnode(n).left;
          tryfinallyn:
            protected_tree:=ttryfinallynode(n).left;
          else
            exit;
        end;
        { Only the protected child has this EH continuation.  A completed
          try before a loop, or a loop in its handler/finalizer, cannot jump
          backwards into that already expired contour. }
        found.loops:=pehloopcollector(arg)^.loops;
        foreachnodestatic(pm_postprocess,protected_tree,
          @collect_local_for_loop,@found);
      end;


    function loop_needs_normal_exit_analysis(loop : tfornode) : boolean;
      begin
        { Normal-exit liveness is consumed only when delayed full unrolling
          considers removing the source loop.  The language/DFA and internal
          lifetime contracts make that query irrelevant for all other loops. }
        result:=(tnf_delay_loop_unroll in loop.transientflags) and
          not(lnf_dont_mind_loopvar_on_exit in loop.loopflags) and
          not(tnf_internal_counter_lifetime in loop.transientflags);
      end;


    procedure mark_exceptional_loop_observers(node : tnode);
      var
        found : tlooplist;
        analysis_syms : tfplist;
        eh_loops : tehloopcollector;
        i : longint;
        loop : tfornode;
        sym : tabstractvarsym;
        cache : tlivenesscache;
        continuations : tflowcontinuations;
        nonlocal_live,
        new_nonlocal_live,
        has_nonlocal_entry : boolean;
      begin
        found.loops:=tfplist.create;
        analysis_syms:=tfplist.create;
        eh_loops.loops:=tfplist.create;
        try
          foreachnodestatic(pm_postprocess,node,
            @collect_local_for_loop,@found);
          { These flags describe one exact control-flow context.  A typed
            loop can arrive here by moving/copying a previously analysed
            tree, so no result from its old owner may seed this solve. }
          for i:=0 to found.loops.count-1 do
            begin
              exclude(tfornode(found.loops[i]).transientflags,
                tnf_loopvar_observable_on_normal_exit);
              exclude(tfornode(found.loops[i]).transientflags,
                tnf_loopvar_observable_on_abrupt_exit);
            end;
          has_nonlocal_entry:=foreachnodestatic(node,
            @find_nonlocal_loop_entry,nil);
          foreachnodestatic(node,@collect_eh_protected_loops,@eh_loops);
          sort_unique_nodes(eh_loops.loops);
          { First select exact declarations which have a semantic consumer.
            This linear prepass is also essential for block-scoped `for var`:
            every loop owns a distinct symbol, but in an observer-free routine
            none of them requires a whole-routine fixed point. }
          for i:=0 to found.loops.count-1 do
            begin
              loop:=tfornode(found.loops[i]);
              sym:=exact_for_counter_sym(loop);
              if not assigned(sym) then
                continue;
              if (has_nonlocal_entry or
                  sorted_nodes_contains(eh_loops.loops,loop) or
                  loop_contains_eh(loop) or
                  loop_has_local_abrupt_exit(loop) or
                  loop_needs_normal_exit_analysis(loop)) and
                 (analysis_syms.indexof(sym)<0) then
                analysis_syms.add(sym);
            end;
          for i:=0 to analysis_syms.count-1 do
            begin
              sym:=tabstractvarsym(analysis_syms[i]);
              cache.entries:=nil;
              cache.count:=0;
              cache.labels:=nil;
              cache.contexts:=nil;
              fillchar(continuations,sizeof(continuations),0);
              nonlocal_live:=false;
              foreachnodestatic(pm_postprocess,node,
                @collect_liveness_label,@cache);
              try
                repeat
                  cache.entries:=nil;
                  cache.count:=0;
                  cache.labels_changed:=false;
                  continuations.nonlocal_goto:=nonlocal_live;
                  analyze_loop_exception_liveness(node,sym,
                    continuations,@cache);
                  new_nonlocal_live:=live_nonlocal_entry(@cache);
                  if new_nonlocal_live and not nonlocal_live then
                    begin
                      nonlocal_live:=true;
                      cache.labels_changed:=true;
                    end;
                until not cache.labels_changed;
              finally
                cache.entries:=nil;
                cache.labels:=nil;
                  cache.contexts:=nil;
              end;
            end;
        finally
          eh_loops.loops.free;
          analysis_syms.free;
          found.loops.free;
        end;
      end;


    function finish_delayed_loop(var n : tnode;
      arg : pointer) : foreachnoderesult;
      var
        oldnode,newnode : tnode;
      begin
        result:=fen_false;
        if (n.nodetype<>forn) or
           not(tnf_delay_loop_unroll in n.transientflags) then
          exit;
        exclude(n.transientflags,tnf_delay_loop_unroll);
        newnode:=unroll_loop(n);
        if not assigned(newnode) then
          exit;
        oldnode:=n;
        n:=newnode;
        typecheckpass(n);
        oldnode.free;
        result:=fen_norecurse_false;
      end;


    procedure finish_loop_unrolling(var node : tnode);
      var
        pending_loops : boolean;
      begin
        if not assigned(node) then
          exit;
        { Complete the routine summary with implicit runtime transfers which
          are not call nodes yet (managed helpers, checked conversions, ...).
          ErrorProc and MM hooks make those real user-callback edges. }
        if assigned(current_procinfo) then
          begin
            pending_loops:=current_procinfo.has_pending_loop_observer_analysis;
            if not current_procinfo.loop_observer_analysis_initialized then
              begin
                { A generated routine may take ownership of an already typed
                  tree (async lowering is the canonical case), so it never
                  executes tfornode.pass_typecheck in the new procinfo.  Scan
                  once at that ownership boundary; ordinary reentrant passes
                  remain O(1). }
                if not pending_loops then
                  pending_loops:=foreachnodestatic(node,
                    @find_loop_observer_analysis_source,nil);
                current_procinfo.loop_observer_analysis_initialized:=true;
              end;
          end
        else
          { Compiler-created trees outside a routine have no demand bit. }
          pending_loops:=true;
        if assigned(current_procinfo) and
           assigned(current_procinfo.procdef) and
           not current_procinfo.procdef.nonlocal_goto_summary_complete then
          begin
            if tree_has_opaque_runtime_transfer(node) then
              current_procinfo.procdef.nonlocal_goto_has_opaque_transfer:=true;
            { Imported/opaque definitions deliberately keep this false and
              are never treated as proof that a call cannot escape. }
            current_procinfo.procdef.nonlocal_goto_summary_complete:=true;
          end;
        if not pending_loops then
          exit;
        repeat
          if assigned(current_procinfo) then
            current_procinfo.has_pending_loop_observer_analysis:=false;
          mark_exceptional_loop_observers(node);
          { Despite the historical names, pm_preprocess visits children first.
            Bottom-up rewriting ensures delayed loops copied inside another
            unrolled body are completed in the same pass. }
          foreachnodestatic(pm_preprocess,node,@finish_delayed_loop,nil);
        until not assigned(current_procinfo) or
          not current_procinfo.has_pending_loop_observer_analysis;
      end;


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
        materializecounter : boolean;
        replaceinfo : treplaceinfo;
        unrolledbody : tnode;
        hascontrollflowstatements : boolean;
      begin
        result:=nil;
        if ErrorCount<>0 then
          exit;
        if not(node.nodetype in [forn]) then
          exit;
        { the unroller assumes a stride of one }
        if assigned(tfornode(node).loopstep) then
          exit;
        unrolls:=number_unrolls(tfornode(node).t2);
        if (unrolls>1) and node_is_private_routine_storage(tfornode(node).left) then
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
                  { Removing the for node also removes its final counter state.
                    The DFA/parser contract, rather than the language mode
                    alone, decides whether that state is dead. }
                  ((lnf_dont_mind_loopvar_on_exit in
                      tfornode(node).loopflags) or
                   (tnf_internal_counter_lifetime in
                      node.transientflags) or
                   not(tnf_loopvar_observable_on_normal_exit in
                      node.transientflags));

                if getridoffor then
                  begin
                    replaceinfo.node:=tfornode(node).left;
                    replaceinfo.value:=tordconstnode(tfornode(node).right).value;
                  end
                else
                  { we consider currently unrolling not beneficial, if we cannot get rid of the for completely, this
                    might change if a more sophisticated heuristics is used (FK) }
                  exit;

                materializecounter:=tnf_loopvar_observable_on_abrupt_exit in
                  node.transientflags;

                { let's unroll (and rock of course) }
                for i:=1 to unrolls do
                  begin
                    { Replace reads only in this body copy.  When an enclosing
                      handler can observe the counter, keep the source loop's
                      store immediately before every iteration.  This retains
                      the exact exceptional state without retaining the loop
                      branch itself. }
                    unrolledbody:=tfornode(node).t2.getcopy;
                    foreachnodestatic(unrolledbody,@replaceloadnodes,@replaceinfo);
                    if materializecounter then
                      addstatement(unrollstatement,cassignmentnode.create_internal(
                        tfornode(node).left.getcopy,
                        cordconstnode.create(replaceinfo.value,
                          tfornode(node).left.resultdef,false)));
                    addstatement(unrollstatement,unrolledbody);

                    { set and insert entry label? }
                    if (counts mod unrolls<>0) and
                      ((counts mod unrolls)=unrolls-i) then
                      begin
                        tfornode(node).entrylabel:=clabelnode.create(cnothingnode.create,clabelsym.create('$optunrol'));
                        addstatement(unrollstatement,tfornode(node).entrylabel);
                      end;

                    if getridoffor then
                      begin
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


    function staticscalarunchanged(loop : tfornode;expr : tloadnode) : boolean;
      var
        candidateeffect,
        loopeffect : teffect;
      begin
        effect_init(candidateeffect);
        effect_init(loopeffect);
        try
          { AUTOINLINE may replace an opaque call by a direct write after DFA
            summaries were built.  The shared effect model observes the final
            tree and is therefore the authority for both forms. }
          tree_effect(expr,candidateeffect);
          tree_effect(loop.t2,loopeffect);
          result:=not effects_conflict(candidateeffect,loopeffect);
        finally
          effect_done(loopeffect);
          effect_done(candidateeffect);
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
              staticscalarunchanged(loop,expr);
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
      tloopinvariantinitkind = (liik_invalid,liik_unconditional,liik_guarded);

    { Classify where an invariant may be evaluated.  A pure invariant may be
      seeded before the loop.  A read that can only trap is still movable, but
      only behind the loop-entry gate.  Writes, synchronization and managed
      lifetime effects are never strength-reduction seeds. }
    function loop_invariant_init_kind(loop,expr : tnode) : tloopinvariantinitkind;
      var
        e : teffect;
      begin
        result:=liik_invalid;
        if not is_loop_invariant(loop,expr) then
          exit;
        effect_init(e);
        try
          tree_effect(expr,e);
          if (e.wclasses<>[]) or
            (e.ieffects-[ie_trap]<>[]) then
            exit;
          if (e.ieffects=[]) or
            not(lnf_testatbegin in tfornode(loop).loopflags) then
            result:=liik_unconditional
          else if not has_conditional_nodes(tfornode(loop).t2) and
            not has_node_of_type(tfornode(loop).t2,
              [casen,tryfinallyn,onn,exitn,breakn,continuen,goton,labeln]) then
            result:=liik_guarded;
        finally
          effect_done(e);
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
              if (tvecnode(n).left.nodetype in [loadn,subscriptn]) and
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


    { What a call can do to a local of a routine.

      A local whose address is not taken changes during a call only if code
      runs which names it: code of a routine nested in the routine whose
      local it is, on the frame of the same activation.  Such a routine is
      entered by its name, from the routines which see it, or by its address,
      from anywhere.  An anonymous function names what it has captured, and
      a captured local is not asked about here; it calls no nested routine,
      the parser refuses that.

      What a routine writes, which routines of a nesting level it calls and
      which it knows by address is read from its tree as parsed
      (collect_nested_access).  The tree is gone when the routines compiled
      behind it ask, and what the compiler makes of a tree does no more than
      the tree as parsed.  An outlined finally body comes to life while its
      routine is compiled and is read then; it names the locals as its
      routine does. }
    type
      tnestedaccess = class
        { locals and parameters of the routines around, written }
        written,
        { routines of a nesting level, called by name }
        called,
        { routines of a nesting level, known by address }
        addressed : tfplist;
        { the tree does not tell what the routine does }
        opaque : boolean;
        constructor create;
        destructor destroy;override;
      end;

      pnestedaccessread = ^tnestedaccessread;
      tnestedaccessread = record
        routine : tprocdef;
        access : tnestedaccess;
      end;

      tcallreach = (
        { no routine writes the local }
        cr_none,
        { the call of a routine which writes it, or calls one which does }
        cr_nested,
        { any call }
        cr_any);

      pimplicitbasecontext = ^timplicitbasecontext;
      timplicitbasecontext = record
        sym : tsym;
        reach : tcallreach;
        { the routines that reach a write of sym }
        writers : tfplist;
      end;


    constructor tnestedaccess.create;
      begin
        written:=tfplist.create;
        called:=tfplist.create;
        addressed:=tfplist.create;
        opaque:=false;
      end;


    destructor tnestedaccess.destroy;
      begin
        written.free;
        written:=nil;
        called.free;
        called:=nil;
        addressed.free;
        addressed:=nil;
        inherited destroy;
      end;


    function is_nested_level_routine(def : tdef) : boolean;
      begin
        result:=assigned(def) and
          (def.typ=procdef) and
          (tprocdef(def).parast.symtablelevel>normal_function_level);
      end;


    procedure add_once(list : tfplist;item : pointer);
      begin
        if list.indexof(item)<0 then
          list.add(item);
      end;


    function read_nested_access(var n : tnode;arg : pointer) : foreachnoderesult;
      var
        base : tnode;
        sym : tsym;
        i : longint;
      begin
        result:=fen_false;
        case n.nodetype of
          loadn:
            begin
              sym:=tloadnode(n).symtableentry;
              case sym.typ of
                localvarsym,
                paravarsym:
                  if (n.flags*[nf_write,nf_modify,nf_address_taken]<>[]) and
                     (sym.owner.defowner<>pnestedaccessread(arg)^.routine) then
                    add_once(pnestedaccessread(arg)^.access.written,sym);
                procsym:
                  if assigned(tloadnode(n).procdef) then
                    begin
                      if is_nested_level_routine(tloadnode(n).procdef) then
                        add_once(pnestedaccessread(arg)^.access.addressed,
                          tloadnode(n).procdef);
                    end
                  else
                    for i:=0 to tprocsym(sym).procdeflist.count-1 do
                      if is_nested_level_routine(tdef(tprocsym(sym).procdeflist[i])) then
                        add_once(pnestedaccessread(arg)^.access.addressed,
                          tprocsym(sym).procdeflist[i]);
                else
                  ;
              end;
            end;
          vecn:
            { a write of an element makes a string unique: a new value of
              the variable }
            if vnf_callunique in tvecnode(n).vecnodeflags then
              begin
                base:=actualtargetnode(@tvecnode(n).left)^;
                if (base.nodetype=loadn) and
                   (tloadnode(base).symtableentry.typ in [localvarsym,paravarsym]) and
                   (tloadnode(base).symtableentry.owner.defowner<>
                      pnestedaccessread(arg)^.routine) then
                  add_once(pnestedaccessread(arg)^.access.written,
                    tloadnode(base).symtableentry);
              end;
          calln:
            if is_nested_level_routine(tcallnode(n).procdefinition) then
              add_once(pnestedaccessread(arg)^.access.called,
                tcallnode(n).procdefinition);
          asmn:
            pnestedaccessread(arg)^.access.opaque:=true;
          else
            ;
        end;
      end;


    procedure read_routine(pi : tcgprocinfo);
      var
        reading : tnestedaccessread;
      begin
        if assigned(pi.nested_access) or
           not assigned(pi.code) then
          exit;
        reading.routine:=pi.procdef;
        reading.access:=tnestedaccess.create;
        pi.nested_access:=reading.access;
        foreachnodestatic(pi.code,@read_nested_access,@reading);
      end;


    procedure collect_nested_access(pi : tprocinfo);
      var
        hpi : tprocinfo;
      begin
        read_routine(tcgprocinfo(pi));
        hpi:=pi.get_first_nestedproc;
        while assigned(hpi) do
          begin
            collect_nested_access(hpi);
            hpi:=tprocinfo(hpi.next);
          end;
      end;


    function nested_access_of(pi : tprocinfo) : tnestedaccess;
      begin
        if not assigned(tcgprocinfo(pi).nested_access) and
           (pi.procdef.proctypeoption=potype_exceptfilter) then
          read_routine(tcgprocinfo(pi));
        result:=tnestedaccess(tcgprocinfo(pi).nested_access);
      end;


    procedure collect_nested_routines(pi : tprocinfo;list : tfplist);
      var
        hpi : tprocinfo;
      begin
        hpi:=pi.get_first_nestedproc;
        while assigned(hpi) do
          begin
            list.add(hpi);
            collect_nested_routines(hpi,list);
            hpi:=tprocinfo(hpi.next);
          end;
      end;


    function knows_writer_by_address(access : tnestedaccess;writers : tfplist) : boolean;
      var
        i : longint;
      begin
        result:=true;
        for i:=0 to access.addressed.count-1 do
          if writers.indexof(access.addressed[i])>=0 then
            exit;
        result:=false;
      end;


    procedure init_implicit_base_context(out context : timplicitbasecontext;sym : tsym);
      var
        owner,
        member : tprocinfo;
        family : tfplist;
        access : tnestedaccess;
        i,j : longint;
        grown : boolean;
      begin
        context.sym:=sym;
        context.reach:=cr_any;
        context.writers:=nil;
        { Globals, parameters and captured locals retain the conservative
          barrier. }
        if (sym.typ<>localvarsym) or
           tlocalvarsym(sym).is_captured then
          exit;
        { the routine whose local it is: this one or one around it }
        owner:=current_procinfo;
        while assigned(owner) and
              (owner.procdef<>sym.owner.defowner) do
          owner:=owner.parent;
        if not assigned(owner) then
          exit;
        if not owner.has_nestedprocs then
          begin
            context.reach:=cr_none;
            exit;
          end;
        family:=tfplist.create;
        context.writers:=tfplist.create;
        try
          collect_nested_routines(owner,family);
          { the routines which write the local themselves ... }
          for i:=0 to family.count-1 do
            begin
              member:=tprocinfo(family[i]);
              access:=nested_access_of(member);
              if assigned(access) then
                begin
                  if access.opaque then
                    exit;
                  if access.written.indexof(sym)>=0 then
                    context.writers.add(member.procdef);
                end
              { An outlined finally body which is compiled already belongs
                to a routine around this one and runs when that one is left.
                Of another routine not read nothing is known. }
              else if member.procdef.proctypeoption<>potype_exceptfilter then
                exit;
            end;
          if context.writers.count=0 then
            begin
              context.reach:=cr_none;
              exit;
            end;
          { ... and the ones which call them }
          repeat
            grown:=false;
            for i:=0 to family.count-1 do
              begin
                member:=tprocinfo(family[i]);
                access:=nested_access_of(member);
                if assigned(access) and
                   (context.writers.indexof(member.procdef)<0) then
                  for j:=0 to access.called.count-1 do
                    if context.writers.indexof(access.called[j])>=0 then
                      begin
                        context.writers.add(member.procdef);
                        grown:=true;
                        break;
                      end;
              end;
          until not grown;
          { one of them known by its address is entered by any call; only
            the owner and the routines nested in it see its name }
          access:=nested_access_of(owner);
          if not assigned(access) or
             knows_writer_by_address(access,context.writers) then
            exit;
          for i:=0 to family.count-1 do
            begin
              access:=nested_access_of(tprocinfo(family[i]));
              if assigned(access) and
                 knows_writer_by_address(access,context.writers) then
                exit;
            end;
          context.reach:=cr_nested;
        finally
          family.free;
        end;
      end;


    procedure done_implicit_base_context(var context : timplicitbasecontext);
      begin
        context.writers.free;
        context.writers:=nil;
      end;


    function invalidatesimplicitarraybase(var n : tnode;arg : pointer) : foreachnoderesult;
      begin
        result:=fen_false;
        case n.nodetype of
          calln:
            case pimplicitbasecontext(arg)^.reach of
              cr_any:
                result:=fen_norecurse_true;
              cr_nested:
                if (tcallnode(n).procdefinition.typ=procdef) and
                   (pimplicitbasecontext(arg)^.writers.indexof(
                      tcallnode(n).procdefinition)>=0) then
                  result:=fen_norecurse_true;
              cr_none:
                ;
            end;
          asmn:
            result:=fen_norecurse_true;
          derefn:
            { a pointer store can hit a variable whose address escaped in the
              caller (var parameters) }
            if n.flags*[nf_write,nf_modify,nf_address_taken]<>[] then
              result:=fen_norecurse_true;
          loadn:
            if (tloadnode(n).symtableentry=pimplicitbasecontext(arg)^.sym) and
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
      var
        context : timplicitbasecontext;
      begin
        result:=false;
        if (base.nodetype<>loadn) or
          not(tloadnode(base).symtableentry.typ in [localvarsym,paravarsym]) then
          exit;
        if (tloadnode(base).symtableentry.typ=paravarsym) and
           not(tparavarsym(tloadnode(base).symtableentry).varspez in
             [vs_value,vs_const]) then
          exit;
        if tabstractvarsym(tloadnode(base).symtableentry).addr_taken or
          (vo_volatile in
           tabstractvarsym(tloadnode(base).symtableentry).varoptions) then
          exit;
        init_implicit_base_context(context,tloadnode(base).symtableentry);
        try
          result:=not foreachnodestatic(pm_preprocess,loop.t2,
            @invalidatesimplicitarraybase,@context);
        finally
          done_implicit_base_context(context);
        end;
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


    function strip_value_preserving_ordinal_conversion(n : tnode) : tnode;
      begin
        result:=n;
        while (result.nodetype=typeconvn) and
          is_ordinal(result.resultdef) and
          is_ordinal(ttypeconvnode(result).left.resultdef) and
          ((ttypeconvnode(result).convtype=tc_equal) or
           ((ttypeconvnode(result).convtype=tc_int_2_int) and
            not(nf_explicit in result.flags) and
            is_in_limit(ttypeconvnode(result).left.resultdef,
              result.resultdef))) do
          result:=ttypeconvnode(result).left;
      end;


    function strip_internal_rangecheck_conversion(n : tnode) : tnode;
      begin
        result:=n;
        while (result.nodetype=typeconvn) and
          is_ordinal(result.resultdef) and
          is_ordinal(ttypeconvnode(result).left.resultdef) and
          (ttypeconvnode(result).convtype in [tc_equal,tc_int_2_int]) do
          result:=ttypeconvnode(result).left;
      end;


    function bound_is_array_low(bound,base : tnode) : boolean;
      var
        value : TConstExprInt;
      begin
        result:=false;
        bound:=strip_value_preserving_ordinal_conversion(bound);
        if not is_constintnode(bound) then
          exit;
        value:=get_ordinal_value(bound);
        if is_special_array(base.resultdef) then
          result:=value=0
        else
          result:=value=tarraydef(base.resultdef).lowrange;
      end;


    function bound_is_array_high(bound,base : tnode) : boolean;
      var
        highsym : tabstractvarsym;
      begin
        result:=false;
        bound:=strip_value_preserving_ordinal_conversion(bound);
        if is_dynamic_array(base.resultdef) then
          begin
            result:=(bound.nodetype=inlinen) and
              (tinlinenode(bound).inlinenumber=in_high_x) and
              tinlinenode(bound).left.isequal(base);
            exit;
          end;
        if is_open_array(base.resultdef) then
          begin
            if (base.nodetype<>loadn) or
              (tloadnode(base).symtableentry.typ<>paravarsym) or
              (bound.nodetype<>loadn) then
              exit;
            highsym:=get_high_value_sym(
              tparavarsym(tloadnode(base).symtableentry));
            result:=assigned(highsym) and
              (tloadnode(bound).symtableentry=highsym);
            exit;
          end;
        result:=is_constintnode(bound) and
          (get_ordinal_value(bound)=tarraydef(base.resultdef).highrange);
      end;


    { A full-range for loop proves the access independently of the runtime
      range-check switch.  The separate base-stability test remains mandatory:
      High(A) is captured at loop entry, so replacing A in the body would make
      this proof stale even though the induction variable itself is bounded. }
    function vector_range_is_loop_proven(loop : tfornode;n : tvecnode) : boolean;
      begin
        result:=false;
        if assigned(loop.loopstep) or
          not counter_indexes_vector(loop,n) then
          exit;
        if lnf_backward in loop.loopflags then
          result:=bound_is_array_high(loop.right,n.left) and
            bound_is_array_low(loop.t1,n.left)
        else
          result:=bound_is_array_low(loop.right,n.left) and
            bound_is_array_high(loop.t1,n.left);
      end;


    { arrays the maintained pointer understands: normal or dynamic, not
      packed.  A raw address cursor may replace checked indexing only when the
      enclosing full-range loop itself proves every executed index. }
    function vector_admits_pointer_bump(loop : tfornode;n : tvecnode) : boolean;
      begin
        result:=(not(is_special_array(n.left.resultdef)) or
                 is_dynamic_array(n.left.resultdef) or
                 is_open_array(n.left.resultdef)) and
                not(is_packed_array(n.left.resultdef)) and
                ((([cs_check_overflow,cs_check_range]*n.localswitches)=[]) or
                 vector_range_is_loop_proven(loop,n)) and
                { direct array access, an array which is a field, or a
                  loop-invariant expression }
                ((n.left.nodetype in [loadn,subscriptn]) or
                 is_loop_invariant(loop,n.right));
      end;


    function invalidatesobjectholder(var n : tnode;arg : pointer) : foreachnoderesult;
      begin
        result:=fen_false;
        case n.nodetype of
          calln:
            case pimplicitbasecontext(arg)^.reach of
              cr_any:
                result:=fen_norecurse_true;
              cr_nested:
                if (tcallnode(n).procdefinition.typ=procdef) and
                   (pimplicitbasecontext(arg)^.writers.indexof(
                      tcallnode(n).procdefinition)>=0) then
                  result:=fen_norecurse_true;
              cr_none:
                ;
            end;
          asmn:
            result:=fen_norecurse_true;
          loadn:
            if (tloadnode(n).symtableentry=pimplicitbasecontext(arg)^.sym) and
              (n.flags*[nf_write,nf_modify,nf_address_taken]<>[]) then
              result:=fen_norecurse_true;
          else
            ;
        end;
      end;


    { Self, a local or a value parameter which holds an object keeps its
      value through the loop: its address is taken nowhere, so no pointer
      writes it, and the body does not assign it.  What a call does to a
      local is asked as for an array which is a local. }
    function object_holder_is_loop_invariant(loop : tfornode;holder : tnode) : boolean;
      var
        context : timplicitbasecontext;
        sym : tabstractvarsym;
      begin
        result:=false;
        if (holder.nodetype<>loadn) or
           not is_class(holder.resultdef) or
           not(tloadnode(holder).symtableentry.typ in [localvarsym,paravarsym]) then
          exit;
        sym:=tabstractvarsym(tloadnode(holder).symtableentry);
        if ((sym.typ=paravarsym) and (sym.varspez<>vs_value)) or
           sym.addr_taken or
           (vo_volatile in sym.varoptions) or
           tabstractnormalvarsym(sym).is_captured or
           tabstractnormalvarsym(sym).inparentfpstruct then
          exit;
        init_implicit_base_context(context,sym);
        try
          result:=not foreachnodestatic(pm_preprocess,loop.t2,
            @invalidatesobjectholder,@context);
        finally
          done_implicit_base_context(context);
        end;
      end;


    { The array is a field.  The object it is a field of is held by Self, a
      local or a value parameter which keeps its value through the loop; the
      question needs no data flow analysis, so a routine with a try block is
      answered as well.  An array which lies in the object has its address
      with that; a dynamic array is a pointer VALUE read from the field, and
      nothing in the body may replace it: the body calls nothing, runs no
      managed helper, and what it writes are locals and elements of dynamic
      arrays - the effect model keeps these apart from the fields of an
      object. }
    function field_vector_base_is_stable(loop : tfornode;base : tsubscriptnode;bodyquiet : boolean) : boolean;
      begin
        result:=false;
        if (vo_volatile in base.vs.varoptions) or
           (base.flags*[nf_write,nf_modify,nf_address_taken]<>[]) or
           not object_holder_is_loop_invariant(loop,base.left) then
          exit;
        if not is_implicit_array_pointer(base.resultdef) then
          exit(true);
        result:=bodyquiet;
      end;


    { The body calls nothing, runs no managed helper, and what it writes are
      locals and elements of dynamic arrays.  Asked of the body as it is
      before any access became a temp: to the effect model an access which
      walks a pointer is a store through a pointer, and it would hide the
      answer from the accesses behind it. }
    function field_loop_body_is_quiet(loop : tfornode) : boolean;
      var
        e : teffect;
      begin
        effect_init(e);
        try
          tree_effect(loop.t2,e);
          result:=(e.ieffects*[ie_sync,ie_managed]=[]) and
            not e.wunbounded and
            (e.wclasses*[ac_escaped,ac_global,ac_threadvar,ac_parentframe]=[]);
        finally
          effect_done(e);
        end;
      end;


    function is_field_vector(n : tnode) : boolean;
      begin
        result:=(n.nodetype=vecn) and
          (tvecnode(n).left.nodetype=subscriptn) and
          is_implicit_array_pointer(tvecnode(n).left.resultdef);
      end;


    function has_field_vector(var n : tnode;arg : pointer) : foreachnoderesult;
      begin
        if is_field_vector(n) then
          result:=fen_norecurse_true
        else
          result:=fen_false;
      end;


    function evaluated_first_in_body(body,target : tnode) : boolean; forward;

    function other_access_may_trap(var n : tnode;arg : pointer) : foreachnoderesult;
      var
        e : teffect;
      begin
        { An equal access can only raise the same exception as target. }
        if (n.nodetype=vecn) and n.isequal(tnode(arg)) then
          exit(fen_norecurse_false);
        effect_init(e);
        try
          node_effect(n,e);
          if ie_trap in e.ieffects then
            result:=fen_norecurse_true
          else
            result:=fen_false;
        finally
          effect_done(e);
        end;
      end;

    function other_access_traps(root,target : tnode) : boolean;
      begin
        result:=foreachnodestatic(pm_postprocess,root,@other_access_may_trap,pointer(target));
      end;

    { Is target evaluated whenever root is, before any sibling which may
      trap?  The parts of a statement which depend on a value - the branches
      of an if and of a case, the second operand of a short-circuit and/or,
      the body of a loop - are not. }
    function evaluated_with(root,target : tnode) : boolean;
      begin
        result:=false;
        if not assigned(root) then
          exit;
        if root=target then
          exit(true);
        case root.nodetype of
          ifn,
          casen:
            result:=evaluated_with(tunarynode(root).left,target);
          andn,
          orn:
            begin
              result:=evaluated_with(tbinarynode(root).left,target);
              if result then
                result:=not other_access_traps(tbinarynode(root).right,target);
              if not result and
                 not(is_boolean(root.resultdef) and
                     doshortbooleval(root)) then
                result:=evaluated_with(tbinarynode(root).right,target) and
                  not other_access_traps(tbinarynode(root).left,target);
            end;
          whilerepeatn,
          forn,
          tryexceptn,
          tryfinallyn,
          onn,
          raisen,
          calln,
          asmn,
          labeln,
          goton,
          statementn:
            ;
          blockn:
            { the body of an inlined routine: its statements in their order }
            result:=evaluated_first_in_body(root,target);
          else
            begin
              if root is ttertiarynode then
                begin
                  if evaluated_with(ttertiarynode(root).third,target) then
                    result:=not other_access_traps(tbinarynode(root).left,target) and
                      not other_access_traps(tbinarynode(root).right,target)
                  else if evaluated_with(tbinarynode(root).right,target) then
                    result:=not other_access_traps(tbinarynode(root).left,target) and
                      not other_access_traps(ttertiarynode(root).third,target)
                  else if evaluated_with(tbinarynode(root).left,target) then
                    result:=not other_access_traps(tbinarynode(root).right,target) and
                      not other_access_traps(ttertiarynode(root).third,target);
                end
              else if root is tbinarynode then
                begin
                  if evaluated_with(tbinarynode(root).right,target) then
                    result:=not other_access_traps(tbinarynode(root).left,target)
                  else if evaluated_with(tbinarynode(root).left,target) then
                    result:=not other_access_traps(tbinarynode(root).right,target);
                end
              else if root is tunarynode then
                result:=evaluated_with(tunarynode(root).left,target);
            end;
        end;
      end;


    { Does every iteration evaluate target before the body has done anything
      which can be told from the outside?  Then a read target needs may
      stand behind the entry test of the loop, in front of the first
      iteration: it raises what the first iteration would raise, at the
      place where the first iteration would raise it.  The statements in
      front of the one with target write locals only, raise nothing and
      leave the body nowhere. }
    function evaluated_first_in_body(body,target : tnode) : boolean;
      var
        statement,
        inner : tnode;
        e : teffect;
        quiet : boolean;
      begin
        result:=false;
        if not assigned(body) then
          exit;
        if body.nodetype<>blockn then
          exit(evaluated_with(body,target));
        statement:=tblocknode(body).left;
        while assigned(statement) and (statement.nodetype=statementn) do
          begin
            inner:=tstatementnode(statement).left;
            if assigned(inner) then
              case inner.nodetype of
                nothingn,
                tempcreaten,
                tempdeleten:
                  ;
                blockn:
                  { target stands among the first statements of the block
                    or nowhere: a whole block which is quiet is not asked
                    for }
                  exit(evaluated_first_in_body(inner,target));
                else
                  begin
                    if evaluated_with(inner,target) then
                      exit(true);
                    if has_node_of_type(inner,
                         [ifn,casen,whilerepeatn,forn,tryexceptn,tryfinallyn,onn,
                          raisen,calln,asmn,labeln,goton,breakn,continuen,exitn]) then
                      exit;
                    effect_init(e);
                    try
                      tree_effect(inner,e);
                      quiet:=(e.ieffects=[]) and
                        not e.wunbounded and
                        (e.wclasses-[ac_local]=[]);
                    finally
                      effect_done(e);
                    end;
                    if not quiet then
                      exit;
                  end;
              end;
            statement:=tstatementnode(statement).right;
          end;
      end;


    type
      pfirstaccesssearch = ^tfirstaccesssearch;
      tfirstaccesssearch = record
        body,
        access : tnode;
      end;

    function find_access_evaluated_first(var n : tnode;arg : pointer) : foreachnoderesult;
      begin
        if (n.nodetype=vecn) and
           n.isequal(pfirstaccesssearch(arg)^.access) and
           evaluated_first_in_body(pfirstaccesssearch(arg)^.body,n) then
          result:=fen_norecurse_true
        else
          result:=fen_false;
      end;


    { an implicit array pointer (dynamic array, dynamic string) is a base
      VALUE loaded from the variable - bumping a cached copy is only legal
      while nothing in the body can replace that value }
    function vector_base_is_stable(loop : tfornode;n : tvecnode;bodyquiet : boolean) : boolean;
      begin
        if n.left.nodetype=subscriptn then
          result:=field_vector_base_is_stable(loop,tsubscriptnode(n.left),bodyquiet)
        else
          result:=not(is_implicit_array_pointer(n.left.resultdef)) or
                  implicit_array_base_is_loop_invariant(loop,n.left);
      end;


    function is_equal_access(var n : tnode;arg : pointer) : foreachnoderesult;
      begin
        if (n.nodetype=vecn) and n.isequal(tnode(arg)) then
          result:=fen_norecurse_true
        else
          result:=fen_false;
      end;


    { In how many places does the code of the body compute the address of
      access?  The expressions of one statement share an address; two
      statements, and a condition and the statements it guards, do not. }
    procedure count_access_places(n,access : tnode;var places : longint);
      begin
        if not assigned(n) then
          exit;
        case n.nodetype of
          blockn:
            count_access_places(tblocknode(n).left,access,places);
          statementn:
            begin
              count_access_places(tstatementnode(n).left,access,places);
              count_access_places(tstatementnode(n).right,access,places);
            end;
          ifn:
            begin
              count_access_places(tifnode(n).left,access,places);
              count_access_places(tifnode(n).right,access,places);
              count_access_places(tifnode(n).t1,access,places);
            end;
          whilerepeatn:
            begin
              count_access_places(twhilerepeatnode(n).left,access,places);
              count_access_places(twhilerepeatnode(n).right,access,places);
            end;
          else
            if foreachnodestatic(pm_postprocess,n,@is_equal_access,pointer(access)) then
              inc(places);
        end;
      end;


    { A dynamic array which is a field, its elements of a size the processor
      scales by itself: the scaled access costs the read of the pointer from
      the object and nothing else, and the maintained pointer costs its step
      and its start.  The pointer pays where an iteration has more than one
      read to lose: the counter is narrower than an address and is extended
      for every access, or the address is computed in more than one place. }
    function field_walk_pays(loop : tfornode;n : tvecnode) : boolean;
      var
        places : longint;
      begin
        if loop.left.resultdef.size<voidpointertype.size then
          exit(true);
        places:=0;
        count_access_places(loop.t2,n,places);
        result:=places>1;
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
          or ((((n.left.nodetype=loadn) and
                (is_implicit_array_pointer(n.left.resultdef) or
                 ((tloadnode(n.left).symtableentry.typ=staticvarsym) and
                  not(vo_is_thread_var in tstaticvarsym(tloadnode(n.left).symtableentry).varoptions)))) or
               { a dynamic array which is a field is reloaded from the
                 object on every element }
               ((n.left.nodetype=subscriptn) and
                is_implicit_array_pointer(n.left.resultdef) and
                field_walk_pays(loop,n))) and
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
        guardedinitcode,
        calccode,
        deletecode : tblocknode;
        initcodestatements,
        guardedinitcodestatements,
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
        { the facts a walk of a field array asks about, collected on the body
          as it is before any access became a temp }
        fieldbodyquiet : boolean;
        nfirstaccesses : sizeint;
        { copies of the field accesses which every iteration evaluates first }
        firstaccesses : array of tnode;
        function has_equal_induction(n : tnode) : boolean;
        function findpreviousstrengthreduction(var n: tnode): boolean;
        procedure addinduction(temp : ttempcreatenode; expr : tnode);
        procedure addinvariantseed(kind : tloopinvariantinitkind; n : tnode);
        function strip_proven_open_array_rangecheck(var n: tnode): foreachnoderesult;
        function field_seed_is_evaluated(n : tnode) : boolean;
        procedure collect_field_facts;
        function collect_first_access(var n: tnode): foreachnoderesult;
        function dostrengthreductiontest(var n: tnode): foreachnoderesult;
        procedure optimizeinductionvariablessingleforloop(var n: tnode);
      end;


    function toptimizeinductionvariablescontext.has_equal_induction(n : tnode) : boolean;
      var
        i : longint;
      begin
        for i:=0 to ninductions-1 do
          if inductions[i].expr.isequal(n) then
            exit(true);
        result:=false;
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


    procedure toptimizeinductionvariablescontext.addinvariantseed(kind : tloopinvariantinitkind; n : tnode);
      begin
        case kind of
          liik_unconditional:
            addstatement(initcodestatements,n);
          liik_guarded:
            begin
              if not assigned(guardedinitcode) then
                guardedinitcode:=internalstatements(guardedinitcodestatements);
              addstatement(guardedinitcodestatements,n);
            end;
          else
            internalerror(2026091301);
        end;
      end;


    { Open-array range checking is expanded during type checking, before the
      loop optimizer runs.  Keep that lowering for the general case, but undo
      the exact compiler-generated wrapper when the enclosing for loop itself
      proves the index range.  This restores the source counter/vector
      relation for ordinary strength reduction without teaching the optimizer
      to guess through arbitrary user blocks or removing either operand's
      evaluation. }
    function toptimizeinductionvariablescontext.strip_proven_open_array_rangecheck(
      var n: tnode): foreachnoderesult;
      var
        block : tblocknode;
        statements : array[0..4] of tstatementnode;
        temp : ptempinfo;
        assignment : tassignmentnode;
        check : tifnode;
        condition : taddnode;
        vector : tvecnode;
        sourceindex,oldindex : tnode;
        highsym : tabstractvarsym;
        i : longint;
      begin
        result:=fen_false;
        if (n.nodetype<>blockn) or
          not(bnf_open_array_rangecheck in
            tblocknode(n).blocknodeflags) then
          exit;

        block:=tblocknode(n);
        statements[0]:=tstatementnode(block.left);
        for i:=0 to 3 do
          begin
            if not assigned(statements[i]) or
              (statements[i].nodetype<>statementn) or
              not assigned(statements[i].right) or
              (statements[i].right.nodetype<>statementn) then
              exit;
            statements[i+1]:=tstatementnode(statements[i].right);
          end;
        if assigned(statements[4].right) or
          (statements[0].left.nodetype<>tempcreaten) or
          (statements[1].left.nodetype<>assignn) or
          (statements[2].left.nodetype<>ifn) or
          (statements[3].left.nodetype<>tempdeleten) or
          (statements[4].left.nodetype<>vecn) then
          exit;

        temp:=ttempcreatenode(statements[0].left).tempinfo;
        assignment:=tassignmentnode(statements[1].left);
        if (actualtargetnode(@assignment.left)^.nodetype<>temprefn) or
          (ttemprefnode(actualtargetnode(@assignment.left)^).tempinfo<>temp) or
          (ttempdeletenode(statements[3].left).tempinfo<>temp) or
          not assignment.right.isequal(currforloop.left) then
          exit;

        check:=tifnode(statements[2].left);
        if not(nf_internal in check.flags) or assigned(check.t1) or
          (check.right.nodetype<>calln) or
          (tcallnode(check.right).procdefinition<>
             search_system_proc('fpc_rangeerror')) or
          (check.left.nodetype<>gten) then
          exit;
        condition:=taddnode(check.left);
        sourceindex:=strip_internal_rangecheck_conversion(condition.left);
        if (sourceindex.nodetype<>temprefn) or
          (ttemprefnode(sourceindex).tempinfo<>temp) or
          (condition.right.nodetype<>addn) or
          not is_constintnode(taddnode(condition.right).right) or
          (get_ordinal_value(taddnode(condition.right).right)<>1) then
          exit;

        vector:=tvecnode(statements[4].left);
        if not is_open_array(vector.left.resultdef) or
          (vector.right.nodetype<>temprefn) or
          (ttemprefnode(vector.right).tempinfo<>temp) or
          (vector.left.nodetype<>loadn) or
          (tloadnode(vector.left).symtableentry.typ<>paravarsym) then
          exit;
        highsym:=get_high_value_sym(
          tparavarsym(tloadnode(vector.left).symtableentry));
        sourceindex:=strip_internal_rangecheck_conversion(
          taddnode(condition.right).left);
        if not assigned(highsym) or (sourceindex.nodetype<>loadn) or
          (tloadnode(sourceindex).symtableentry<>highsym) then
          exit;
        if lnf_backward in currforloop.loopflags then
          begin
            if not bound_is_array_high(currforloop.right,vector.left) or
              not bound_is_array_low(currforloop.t1,vector.left) then
              exit;
          end
        else if not bound_is_array_low(currforloop.right,vector.left) or
          not bound_is_array_high(currforloop.t1,vector.left) then
          exit;

        { Transfer the original counter load and vector out of the wrapper.
          The temporary and explicit check remain owned by the old block and
          are destroyed with it. }
        sourceindex:=assignment.right;
        assignment.right:=nil;
        statements[4].left:=nil;
        oldindex:=vector.right;
        vector.right:=sourceindex;
        oldindex.free;
        n:=vector;
        block.free;
        node_reset_pass1_write(n);
        do_firstpass(n);
      end;


    function strip_proven_open_array_rangecheck_callback(var n: tnode;
      arg: pointer): foreachnoderesult;
      begin
        result:=toptimizeinductionvariablescontext(arg^).
          strip_proven_open_array_rangecheck(n);
      end;


    { n reads its array from a field.  The read of the field may stand in
      front of the first iteration if the first iteration does it whatever
      happens: n, or an equal access which has its pointer already, is
      evaluated first in the body }
    function toptimizeinductionvariablescontext.field_seed_is_evaluated(n : tnode) : boolean;
      var
        i : longint;
      begin
        for i:=0 to nfirstaccesses-1 do
          if firstaccesses[i].isequal(n) then
            exit(true);
        result:=false;
      end;


    function collect_first_access_callback(var n: tnode; arg: pointer): foreachnoderesult; forward;

    { The facts about the field accesses of the loop, from the body as it is
      before any access became a temp }
    procedure toptimizeinductionvariablescontext.collect_field_facts;
      begin
        fieldbodyquiet:=false;
        nfirstaccesses:=0;
        if not foreachnodestatic(pm_postprocess,currforloop.t2,@has_field_vector,nil) then
          exit;
        fieldbodyquiet:=field_loop_body_is_quiet(currforloop);
        if fieldbodyquiet then
          foreachnodestatic(pm_postprocess,currforloop.t2,@collect_first_access_callback,@self);
      end;


    function toptimizeinductionvariablescontext.collect_first_access(var n: tnode): foreachnoderesult;
      var
        search : tfirstaccesssearch;
      begin
        result:=fen_false;
        if not is_field_vector(n) or
           not counter_indexes_vector(currforloop,tvecnode(n)) or
           field_seed_is_evaluated(n) then
          exit;
        search.body:=currforloop.t2;
        search.access:=n;
        if foreachnodestatic(pm_postprocess,currforloop.t2,
             @find_access_evaluated_first,@search) then
          begin
            if nfirstaccesses>=length(firstaccesses) then
              SetLength(firstaccesses,4+nfirstaccesses+nfirstaccesses shr 1);
            firstaccesses[nfirstaccesses]:=n.getcopy;
            inc(nfirstaccesses);
          end;
      end;


    function collect_first_access_callback(var n: tnode; arg: pointer): foreachnoderesult;
      begin
        result:=toptimizeinductionvariablescontext(arg^).collect_first_access(n);
      end;


    { checks if the strength of n can be reduced, currforloop is the tforloop being considered }
    function toptimizeinductionvariablescontext.dostrengthreductiontest(var n: tnode): foreachnoderesult;
      var
        tempnode,startvaltemp : ttempcreatenode;
        nn : tnode;
        nt : tnodetype;
        nflags : tnodeflags;
        invariantkind : tloopinvariantinitkind;
        fieldseed : boolean;
      begin
        result:=fen_false;
        nflags:=n.flags;
        case n.nodetype of
          forn:
            { inform for loop search routine, that it needs to search more deeply }
            containsnestedforloop:=true;
          muln:
            begin
              invariantkind:=loop_invariant_init_kind(currforloop,taddnode(n).left);
              if (taddnode(n).right.nodetype=loadn) and
                taddnode(n).right.isequal(currforloop.left) and
                { plain read of the loop variable? }
                not(nf_write in taddnode(n).right.flags) and
                not(nf_modify in taddnode(n).right.flags) and
                (invariantkind<>liik_invalid) then
                begin
                  taddnode(n).swapleftright;
                  invariantkind:=loop_invariant_init_kind(currforloop,taddnode(n).right);
                end
              else
                invariantkind:=loop_invariant_init_kind(currforloop,taddnode(n).right);

              if (taddnode(n).left.nodetype=loadn) and
                taddnode(n).left.isequal(currforloop.left) and
                { plain read of the loop variable? }
                not(nf_write in taddnode(n).left.flags) and
                not(nf_modify in taddnode(n).left.flags) and
                not(cs_check_overflow in n.localswitches) and
                (invariantkind<>liik_invalid) then
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
                      addinvariantseed(invariantkind,cassignmentnode.create(ctemprefnode.create(tempnode),
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
              invariantkind:=loop_invariant_init_kind(currforloop,tvecnode(n).right);
              if is_normal_array(tvecnode(n).left.resultdef) and
                not(is_packed_array(tvecnode(n).left.resultdef)) and
                not(is_managed_type(n.resultdef)) and
                (tvecnode(n).left.nodetype=loadn) and
                (([cs_check_overflow,cs_check_range]*n.localswitches)=[]) and
                (invariantkind<>liik_invalid) then
                begin
                  changedforloop:=true;
                  if not(findpreviousstrengthreduction(n)) then
                    begin
                      tempnode:=ctempcreatenode.create(voidpointertype,voidpointertype.size,tt_persistent,true);
                      addinduction(tempnode,n);
                      addstatement(initcodestatements,tempnode);
                      addinvariantseed(invariantkind,cassignmentnode.create(
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
                { an access equal to one which walks a pointer already joins
                  it: the questions below were answered when that pointer
                  was made, and the body has changed since - that access is
                  a temp now, and to the effect model a store through it is
                  a store through a pointer }
                (has_equal_induction(n) or
                 (vector_base_is_stable(currforloop,tvecnode(n),fieldbodyquiet) and
                  pointer_bump_profitable(currforloop,tvecnode(n)) and
                  { a dynamic array which is a field: its pointer is read
                    from the object, and the first iteration reads it anyway }
                  (not is_field_vector(n) or
                   field_seed_is_evaluated(n)))) then
                begin
                  fieldseed:=is_field_vector(n);
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
                      nn.localswitches:=nn.localswitches-
                        [cs_check_range,cs_check_overflow];
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
                      if fieldseed and (lnf_testatbegin in currforloop.loopflags) then
                        { the pointer is read from a field of an object: the
                          read stands where the first iteration would do it }
                        addinvariantseed(liik_guarded,
                          cassignmentnode.create(ctemprefnode.create(tempnode),nn))
                      else
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
        i : longint;
      begin
        { do we have DFA available? }
        if pi_dfaavailable in current_procinfo.flags then
          begin
            CalcDefSum(tfornode(n).t2);
          end;
        currforloop:=tfornode(n);
        initcode:=nil;
        guardedinitcode:=nil;
        calccode:=nil;
        deletecode:=nil;
        initcodestatements:=nil;
        guardedinitcodestatements:=nil;
        calccodestatements:=nil;
        deletecodestatements:=nil;
        ninductions:=0;
        docalcatend:=false;
        { Recover the direct vector form hidden by the open-array range-check
          lowering before looking for induction expressions. }
        foreachnodestatic(pm_postprocess,n,
          @strip_proven_open_array_rangecheck_callback,@self);
        collect_field_facts;
        { find all expressions being candidates for strength reduction
          and replace them }
        foreachnodestatic(pm_postprocess,n,@dostrengthreductiontest_callback,@self);
        for i:=0 to nfirstaccesses-1 do
          firstaccesses[i].free;
        nfirstaccesses:=0;

        { clue everything together }
        if assigned(initcode) then
          begin
            do_firstpass(tnode(initcode));
            if assigned(guardedinitcode) then
              do_firstpass(tnode(guardedinitcode));
            do_firstpass(tnode(calccode));
            do_firstpass(tnode(deletecode));
            { create a new for node, the old one will be released by the compiler }
            oldn:=n;
            newfor:=cfornode.create(tfornode(oldn).left,tfornode(oldn).right,tfornode(oldn).t1,tfornode(oldn).t2,lnf_backward in tfornode(oldn).loopflags);
            tfornode(newfor).loopflags:=tfornode(oldn).loopflags;
            tfornode(newfor).looppreheader:=guardedinitcode;
            guardedinitcode:=nil;
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


{****************************************************************************
                         Loop-invariant code motion

  F2 deliberately starts with a small, auditable surface.  It moves only
  trap-free integer/pointer expressions and exact native int-to-FP conversions
  over exact current-frame values.
  The effect model owns all alias/mutation decisions; this unit owns only
  tree shape, profitability and placement.
****************************************************************************}

    const
      licm_max_hoists_per_loop = 4;
      licm_max_pressure_for_cheap = 6;

    type
      tlicmplan = record
        loopeffect : teffect;
        exprs : TFPList;
        temps : TFPList;
        { Integer and vector-FP values compete for different registers. }
        pressure : array[boolean] of longint;
      end;
      plicmplan = ^tlicmplan;

      tlicmreplace = record
        expr : tnode;
        temp : ttempcreatenode;
        count : longint;
      end;
      plicmreplace = ^tlicmreplace;

    function licm_scalar_def(def : tdef) : boolean;
      begin
        result:=assigned(def) and
          (((is_ordinal(def)) and (def.size<=sizeof(aint))) or
           (def.typ=pointerdef));
      end;


    function licm_count_temps(var n : tnode; arg : pointer) : foreachnoderesult;
      var
        plan : plicmplan;
      begin
        result:=fen_false;
        if (n.nodetype<>temprefn) or
           not(ti_may_be_in_reg in ttemprefnode(n).tempflags) then
          exit;
        plan:=plicmplan(arg);
        if plan^.temps.IndexOf(ttemprefnode(n).tempinfo)<0 then
          begin
            plan^.temps.Add(ttemprefnode(n).tempinfo);
            inc(plan^.pressure[use_vectorfpu(n.resultdef)]);
          end;
      end;


    function licm_candidate_shape(n : tnode; var score : longint) : boolean;
      begin
        result:=false;
        if not assigned(n) then
          exit;
        if effect_int_to_real_is_exact(n) then
          begin
            result:=licm_candidate_shape(ttypeconvnode(n).left,score);
            if result then
              inc(score,2);
            exit;
          end;
        if not licm_scalar_def(n.resultdef) then
          exit;
        case n.nodetype of
          ordconstn,
          pointerconstn,
          niln,
          loadn:
            result:=true;
          typeconvn:
            result:=licm_candidate_shape(ttypeconvnode(n).left,score);
          unaryminusn,
          unaryplusn,
          notn:
            result:=licm_candidate_shape(tunarynode(n).left,score);
          addn,
          subn,
          muln,
          andn,
          orn,
          xorn,
          shln,
          shrn:
            begin
              result:=licm_candidate_shape(tbinarynode(n).left,score) and
                licm_candidate_shape(tbinarynode(n).right,score);
              if result then
                case n.nodetype of
                  muln:
                    if (tbinarynode(n).left.nodetype=ordconstn) or
                       (tbinarynode(n).right.nodetype=ordconstn) then
                      inc(score,2)
                    else
                      inc(score,4);
                  shln,
                  shrn:
                    inc(score);
                  else
                    ;
                end;
            end;
          else
            ;
        end;
      end;


    function licm_find_candidates(var n : tnode; arg : pointer) : foreachnoderesult;
      var
        plan : plicmplan;
        score,pressure,i : longint;
      begin
        result:=fen_false;
        { A nested loop owns its candidates and preheader.  Its effects are
          nevertheless already part of plan.loopeffect. }
        if n.nodetype=whilerepeatn then
          exit(fen_norecurse_false);
        score:=0;
        if not licm_candidate_shape(n,score) or (score=0) then
          exit;
        plan:=plicmplan(arg);
        if not effect_licm_invariant(n,plan^.loopeffect) then
          exit;
        pressure:=plan^.pressure[use_vectorfpu(n.resultdef)];
        if (score<4) and (pressure>licm_max_pressure_for_cheap) then
          exit;
        for i:=0 to plan^.exprs.count-1 do
          if (tnode(plan^.exprs[i]).resultdef=n.resultdef) and
             (tnode(plan^.exprs[i]).localswitches=n.localswitches) and
             tnode(plan^.exprs[i]).isequal(n) then
            { The existing temp will replace this occurrence too. }
            exit(fen_norecurse_false);
        if plan^.exprs.count>=licm_max_hoists_per_loop then
          exit(fen_norecurse_false);
{$ifdef DEBUG_OPTLICM}
        writeln('LICM candidate in ',current_procinfo.procdef.procsym.realname,
          ' score=',score,' pressure=',pressure);
        printnode(output,n);
{$endif DEBUG_OPTLICM}
        plan^.exprs.add(n.getcopy);
        { Integer hoists can replace their input registers; retain the existing
          input-count heuristic.  Exact int-to-FP hoists instead add a value in
          another register class, without releasing any FP input register. }
        if use_vectorfpu(n.resultdef) then
          inc(plan^.pressure[true]);
        result:=fen_norecurse_false;
      end;


    function licm_replace_uses(var n : tnode; arg : pointer) : foreachnoderesult;
      var
        rep : plicmreplace;
        pos : tfileposinfo;
      begin
        result:=fen_false;
        if n.nodetype=whilerepeatn then
          exit(fen_norecurse_false);
        rep:=plicmreplace(arg);
        if (n.flags*[nf_write,nf_modify]=[]) and
           (n.resultdef=rep^.expr.resultdef) and
           (n.localswitches=rep^.expr.localswitches) and
           n.isequal(rep^.expr) then
          begin
            pos:=n.fileinfo;
            n.free;
            n:=ctemprefnode.create(rep^.temp);
            n.fileinfo:=pos;
            typecheckpass(n);
            inc(rep^.count);
            result:=fen_norecurse_false;
          end;
      end;


    function optimizeinvariantssingleloop(var n : tnode) : boolean;
      var
        plan : tlicmplan;
        rep : tlicmreplace;
        initcode,deletecode : tblocknode;
        initstatements,deletestatements,newstatements : tstatementnode;
        verifycode : tblocknode;
        verifystatements : tstatementnode;
        expr,init,check : tnode;
        temp : ttempcreatenode;
        i : longint;
        verify : boolean;
      begin
        result:=false;
        plan.exprs:=TFPList.create;
        plan.temps:=TFPList.create;
        plan.pressure[false]:=0;
        plan.pressure[true]:=0;
        effect_init(plan.loopeffect);
        try
          verify:=defined_macro('OPTCORE_VERIFY');
          { One model walk for the whole lowered loop: condition, body and
            for-step latch are all mutation authorities. }
          tree_effect(n,plan.loopeffect);
          if assigned(plan.loopeffect.rsyms) then
            for i:=0 to plan.loopeffect.rsyms.count-1 do
              inc(plan.pressure[use_vectorfpu(tabstractvarsym(plan.loopeffect.rsyms[i]).vardef)]);
          foreachnodestatic(pm_postprocess,n,@licm_count_temps,@plan);
          if assigned(tloopnode(n).left) then
            foreachnodestatic(pm_preprocess,tloopnode(n).left,
              @licm_find_candidates,@plan);
          if assigned(tloopnode(n).right) then
            foreachnodestatic(pm_preprocess,tloopnode(n).right,
              @licm_find_candidates,@plan);
          { The latch is analysed above, but is not a hoist source in v1. }
          if plan.exprs.count=0 then
            exit;

          if verify then
            verifycode:=internalstatements(verifystatements)
          else
            verifycode:=nil;
          initcode:=internalstatements(initstatements);
          deletecode:=internalstatements(deletestatements);
          for i:=0 to plan.exprs.count-1 do
            begin
              expr:=tnode(plan.exprs[i]);
              temp:=ctempcreatenode.create(expr.resultdef,expr.resultdef.size,
                tt_persistent,true);
              rep.expr:=expr;
              rep.temp:=temp;
              rep.count:=0;
              if assigned(tloopnode(n).left) then
                foreachnodestatic(pm_preprocess,tloopnode(n).left,
                  @licm_replace_uses,@rep);
              if assigned(tloopnode(n).right) then
                foreachnodestatic(pm_preprocess,tloopnode(n).right,
                  @licm_replace_uses,@rep);
              if rep.count=0 then
                begin
                  { A previously applied maximal candidate may have consumed
                    this overlapping subexpression.  Do not emit a dead temp
                    or turn a harmless stale plan entry into an IE. }
                  temp.free;
                  continue;
                end;
              addstatement(initstatements,temp);
              init:=cassignmentnode.create(ctemprefnode.create(temp),expr.getcopy);
              node_tree_set_filepos(init,expr.fileinfo);
              addstatement(initstatements,init);
              if verify then
                begin
                  { Diagnostic-only executable proof.  The candidate is
                    recomputed at the start of every entered iteration and
                    compared with the preheader value.  Normal builds do not
                    contain this code. }
                  check:=cifnode.create_internal(
                    caddnode.create_internal(unequaln,
                      ctemprefnode.create(temp),expr.getcopy),
                    ccallnode.createintern('fpc_rangeerror',nil),nil);
                  node_tree_set_filepos(check,expr.fileinfo);
                  do_firstpass(check);
                  addstatement(verifystatements,check);
                end;
              addstatement(deletestatements,ctempdeletenode.create(temp));
            end;
          if verify then
            begin
              { Both while and repeat store their body in right.  Checks run
                after the while entry test, or before the first repeat body,
                and before every entered body thereafter. }
              addstatement(verifystatements,tloopnode(n).right);
              tloopnode(n).right:=verifycode;
            end;
          do_firstpass(tnode(initcode));
          do_firstpass(tnode(deletecode));
          expr:=n;
          n:=internalstatements(newstatements);
          addstatement(newstatements,initcode);
          addstatement(newstatements,expr);
          addstatement(newstatements,deletecode);
          result:=true;
        finally
          for i:=0 to plan.exprs.count-1 do
            tnode(plan.exprs[i]).free;
          plan.exprs.free;
          plan.temps.free;
          effect_done(plan.loopeffect);
        end;
      end;


    function licm_walk(var n : tnode; arg : pointer) : foreachnoderesult;
      begin
        result:=fen_false;
        if (n.nodetype=whilerepeatn) and
           optimizeinvariantssingleloop(n) then
          pboolean(arg)^:=true;
      end;


    function OptimizeLoopInvariants(var node : tnode) : boolean;
      begin
        result:=false;
        { Outer loops are visited first. Candidate collection never crosses
          a nested-loop boundary, so every occurrence belongs to the nearest
          structural preheader. }
        foreachnodestatic(pm_preprocess,node,@licm_walk,@result);
      end;


{****************************************************************************
                 Stable dynamic-array base reuse after LICM

  A dynamic-array descriptor already is the element-storage pointer.  When a
  lowered loop uses the same stable descriptor in at least two read-only direct
  element expressions, load it once in that loop's preheader and share a typed
  pointer temp.  At most two bases are selected to bound register pressure.
  This pass deliberately runs after LICM: opteffect v1 treats compiler temps as
  an unanalyzable identity, so inserting this temp earlier would hide otherwise
  profitable invariant index arithmetic from LICM.
****************************************************************************}

    const
      loopvectorbase_max_bases = 2;

    type
      tloopvectorbaseentry = record
        sym : tabstractvarsym;
        base : tnode;
        count : longint;
        written : boolean;
        eligible : boolean;
        temp : ttempcreatenode;
      end;
      tloopvectorbaseentries = array of tloopvectorbaseentry;
      ploopvectorbaseplan = ^tloopvectorbaseplan;
      tloopvectorbaseplan = record
        loop : tloopnode;
        entries : tloopvectorbaseentries;
      end;


    function loopvectorbasecandidate(n : tnode;
      out sym : tabstractvarsym) : boolean;
      begin
        result:=false;
        sym:=nil;
{$ifdef cpu64bitaddr}
        if (n.nodetype<>vecn) or
           (tvecnode(n).left.nodetype<>loadn) or
           not(tloadnode(tvecnode(n).left).symtableentry is tabstractvarsym) or
           not(is_dynamic_array(tvecnode(n).left.resultdef)) or
           is_packed_array(tvecnode(n).left.resultdef) or
           (([cs_check_overflow,cs_check_range]*n.localswitches)<>[]) then
          exit;
        sym:=tabstractvarsym(tloadnode(tvecnode(n).left).symtableentry);
        result:=true;
{$endif cpu64bitaddr}
      end;


    function countloopvectorbases(var n : tnode;arg : pointer) : foreachnoderesult;
      var
        plan : ploopvectorbaseplan;
        sym : tabstractvarsym;
        i : sizeint;
      begin
        result:=fen_false;
        if n.nodetype=whilerepeatn then
          exit(fen_norecurse_false);
        if not loopvectorbasecandidate(n,sym) then
          exit;
        plan:=ploopvectorbaseplan(arg);
        for i:=0 to length(plan^.entries)-1 do
          if plan^.entries[i].sym=sym then
            begin
              inc(plan^.entries[i].count);
              if n.flags*[nf_write,nf_modify]<>[] then
                plan^.entries[i].written:=true;
              exit;
            end;
        i:=length(plan^.entries);
        setlength(plan^.entries,i+1);
        plan^.entries[i].sym:=sym;
        plan^.entries[i].base:=tvecnode(n).left.getcopy;
        plan^.entries[i].count:=1;
        plan^.entries[i].written:=n.flags*[nf_write,nf_modify]<>[];
        plan^.entries[i].eligible:=false;
        plan^.entries[i].temp:=nil;
      end;


    function invalidatesloweredloopbase(var n : tnode;
      arg : pointer) : foreachnoderesult;
      begin
        if n.nodetype=calln then
          result:=fen_norecurse_true
        else
          result:=invalidatesimplicitarraybase(n,arg);
      end;


    function loweredloopbaseisstable(loop : tloopnode;
      sym : tabstractvarsym) : boolean;
      var
        context : timplicitbasecontext;
      begin
        result:=false;
        if not(sym.typ in [localvarsym,paravarsym]) or
           sym.addr_taken or
           (vo_volatile in sym.varoptions) then
          exit;
        if (sym.typ=paravarsym) and
           (tparavarsym(sym).varspez<>vs_value) then
          exit;
        { every call is a barrier here }
        context.sym:=sym;
        context.reach:=cr_any;
        context.writers:=nil;
        if assigned(loop.left) and
           foreachnodestatic(pm_preprocess,loop.left,
             @invalidatesloweredloopbase,@context) then
          exit;
        result:=not assigned(loop.right) or
          not foreachnodestatic(pm_preprocess,loop.right,
            @invalidatesloweredloopbase,@context);
      end;


    function replaceloopvectorbase(var n : tnode;arg : pointer) : foreachnoderesult;
      var
        plan : ploopvectorbaseplan;
        sym : tabstractvarsym;
        newnode : tnode;
        i : sizeint;
      begin
        result:=fen_false;
        if n.nodetype=whilerepeatn then
          exit(fen_norecurse_false);
        if not loopvectorbasecandidate(n,sym) then
          exit;
        plan:=ploopvectorbaseplan(arg);
        for i:=0 to length(plan^.entries)-1 do
          if (plan^.entries[i].sym=sym) and
             assigned(plan^.entries[i].temp) then
            begin
              { Keep the pointer as the vector base until type checking.
                Pointer indexing inserts tc_pointer_2_array only after the
                regability check; pre-inserting an array type would force the
                otherwise registerable pointer temp to memory. }
              newnode:=cvecnode.create(
                ctemprefnode.create(plan^.entries[i].temp),
                tvecnode(n).right);
              tvecnode(n).right:=nil;
              tvecnode(newnode).vecnodeflags:=
                tvecnode(n).vecnodeflags+[vnf_internal_address_index];
              newnode.flags:=n.flags;
              newnode.fileinfo:=n.fileinfo;
              newnode.localswitches:=n.localswitches;
              n.free;
              n:=newnode;
              do_firstpass(n);
              exit(fen_norecurse_false);
            end;
      end;


    function optimizeloopvectorbasessingle(var n : tnode) : boolean;
      var
        plan : tloopvectorbaseplan;
        initcode,deletecode : tblocknode;
        initstatements,deletestatements,newstatements : tstatementnode;
        ptrdef : tpointerdef;
        oldn : tnode;
        i,best : sizeint;
        selected : longint;
      begin
        result:=false;
        plan.loop:=tloopnode(n);
        setlength(plan.entries,0);
        if assigned(plan.loop.left) then
          foreachnodestatic(pm_postprocess,plan.loop.left,
            @countloopvectorbases,@plan);
        if assigned(plan.loop.right) then
          foreachnodestatic(pm_postprocess,plan.loop.right,
            @countloopvectorbases,@plan);
        initcode:=nil;
        deletecode:=nil;
        try
          for i:=0 to length(plan.entries)-1 do
            plan.entries[i].eligible:=
              (plan.entries[i].count>=2) and
              not plan.entries[i].written and
              loweredloopbaseisstable(plan.loop,plan.entries[i].sym);
          for selected:=1 to loopvectorbase_max_bases do
            begin
              best:=-1;
              for i:=0 to length(plan.entries)-1 do
                if plan.entries[i].eligible and
                   not assigned(plan.entries[i].temp) then
                  begin
                    if best<0 then
                      best:=i
                    else if plan.entries[i].count>
                            plan.entries[best].count then
                      best:=i;
                  end;
              if best<0 then
                break;
              if not assigned(initcode) then
                begin
                  initcode:=internalstatements(initstatements);
                  deletecode:=internalstatements(deletestatements);
                end;
              { Generated pointer indexing is an internal address form, not
                a source-mode permission.  Keep its pointer definition
                private rather than mutating a reusable source type. }
              ptrdef:=cpointerdef.create(
                tarraydef(plan.entries[best].base.resultdef).elementdef);
              ptrdef.has_pointer_math:=true;
              plan.entries[best].temp:=ctempcreatenode.create(ptrdef,
                ptrdef.size,tt_persistent,true);
              addstatement(initstatements,plan.entries[best].temp);
              addstatement(initstatements,cassignmentnode.create(
                ctemprefnode.create(plan.entries[best].temp),
                { The descriptor value is already the payload pointer;
                  @array[0] would manufacture another vector access. }
                ctypeconvnode.create_internal(
                  plan.entries[best].base,ptrdef)));
              plan.entries[best].base:=nil;
              addstatement(deletestatements,
                ctempdeletenode.create(plan.entries[best].temp));
            end;
          if not assigned(initcode) then
            exit;
          if assigned(plan.loop.left) then
            foreachnodestatic(pm_postprocess,plan.loop.left,
              @replaceloopvectorbase,@plan);
          if assigned(plan.loop.right) then
            foreachnodestatic(pm_postprocess,plan.loop.right,
              @replaceloopvectorbase,@plan);
          do_firstpass(tnode(initcode));
          do_firstpass(tnode(deletecode));
          oldn:=n;
          n:=internalstatements(newstatements);
          addstatement(newstatements,initcode);
          addstatement(newstatements,oldn);
          addstatement(newstatements,deletecode);
          result:=true;
        finally
          for i:=0 to length(plan.entries)-1 do
            plan.entries[i].base.free;
          setlength(plan.entries,0);
        end;
      end;


    function loopvectorbasewalk(var n : tnode;arg : pointer) : foreachnoderesult;
      begin
        result:=fen_false;
        if (n.nodetype=whilerepeatn) and
           optimizeloopvectorbasessingle(n) then
          pboolean(arg)^:=true;
      end;


    function OptimizeLoopVectorBases(var node : tnode) : boolean;
      begin
        result:=false;
        foreachnodestatic(pm_preprocess,node,@loopvectorbasewalk,@result);
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
        { somebody looks at the field in the record while the loop would
          have it in a temp }
        Observed: Boolean;
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
                    ThisTemp.Observed:=False;
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


    function record_loop_calls(var n:tnode; arg: pointer): foreachnoderesult;
      begin
        if n.nodetype=calln then
          result:=fen_norecurse_true
        else
          result:=fen_false;
      end;


    { A field kept in a temp is a store put off until the loop is left by
      its end.  Whoever looks at the record before that sees the value from
      in front of the loop:

        the handlers and the finally bodies of the try statements the loop
        stands in, and the code a try..except goes on with, when an exception
        leaves the loop; a finally body as well when Exit leaves it;

        a finally body inside the loop which was outlined into a routine of
        its own: it reads and writes the frame, not the temp;

        the code behind the target of a goto which leaves the loop; and a
        managed record's Finalize on an exceptional or Exit edge.  A label
        of the loop which is entered from outside passes by the load of the
        temps.

      Such a field stays in the record.  The rule for a local variable is
      the same one (mark_seh_memory_syms in psub). }
    type
      precordobservers = ^trecordobservers;
      trecordobservers = record
        fields : tlinkedlist;
        { the subtree which is not looked at }
        skip : tnode;
        { a read of a field the loop writes counts, or every access does }
        readsonly : boolean;
      end;

      penclosingtries = ^tenclosingtries;
      tenclosingtries = record
        fields : tlinkedlist;
        loop,
        root : tnode;
        leftbyexception,
        leftbyexit : boolean;
      end;

      ptrycontinuation = ^ttrycontinuation;
      ttrycontinuation = record
        fields : tlinkedlist;
        guarded : tnode;
        found : boolean;
      end;

      precordjumps = ^trecordjumps;
      trecordjumps = record
        labels : tfplist;
        loop : tnode;
      end;


    { the body of a finally block which was outlined, nil if it stands in
      the tree; known is false if the body cannot be looked at }
    function outlined_finally_body(n : tnode;out known : boolean) : tnode;
      var
        pd : tabstractprocdef;
        pi : tprocinfo;
      begin
        result:=nil;
        known:=true;
        if not assigned(ttryfinallynode(n).right) or
           (ttryfinallynode(n).right.nodetype<>calln) then
          exit;
        pd:=tcallnode(ttryfinallynode(n).right).procdefinition;
        if not assigned(pd) or
           (pd.typ<>procdef) or
           (tprocdef(pd).proctypeoption<>potype_exceptfilter) then
          exit;
        pi:=current_procinfo.find_nestedproc_by_pd(tprocdef(pd));
        if assigned(pi) then
          result:=tcgprocinfo(pi).code;
        known:=assigned(result);
      end;


    procedure mark_observed_field(fields : tlinkedlist;base : tsym;
      field : tsym;isread,readsonly : boolean;var found : boolean);
      var
        pair : TFieldTempPair;
      begin
        pair:=TFieldTempPair(fields.First);
        while assigned(pair) do
          begin
            if pair.BaseSymbol=base then
              begin
                found:=true;
                if (not assigned(field) or (pair.Field=field)) and
                   (isread or not readsonly) and
                   (pair.FieldWritten or not readsonly) then
                  pair.Observed:=true;
              end;
            pair:=TFieldTempPair(pair.Next);
          end;
      end;


    procedure mark_all_fields_observed(fields : tlinkedlist);
      var
        pair : TFieldTempPair;
      begin
        pair:=TFieldTempPair(fields.First);
        while assigned(pair) do
          begin
            pair.Observed:=true;
            pair:=TFieldTempPair(pair.Next);
          end;
      end;


    function mark_observed_fields(var n : tnode;arg : pointer) : foreachnoderesult; forward;

    { the function cannot name itself within itself }
    function mark_observed_fields_again(var n : tnode;arg : pointer) : foreachnoderesult;
      begin
        result:=mark_observed_fields(n,arg);
      end;


    function mark_observed_fields(var n : tnode;arg : pointer) : foreachnoderesult;
      var
        load : tnode;
        body : tnode;
        known,
        found : boolean;
      begin
        result:=fen_false;
        if n=precordobservers(arg)^.skip then
          exit(fen_norecurse_false);
        case n.nodetype of
          subscriptn:
            begin
              load:=tsubscriptnode(n).left;
              if load.nodetype=loadn then
                begin
                  found:=false;
                  mark_observed_field(precordobservers(arg)^.fields,
                    tloadnode(load).symtableentry,tsubscriptnode(n).vs,
                    (nf_modify in load.flags) or not(nf_write in load.flags),
                    precordobservers(arg)^.readsonly,found);
                  if found then
                    result:=fen_norecurse_false;
                end;
            end;
          loadn:
            begin
              { the record as a whole }
              found:=false;
              mark_observed_field(precordobservers(arg)^.fields,
                tloadnode(n).symtableentry,nil,
                (nf_modify in n.flags) or not(nf_write in n.flags),
                precordobservers(arg)^.readsonly,found);
            end;
          tryfinallyn:
            begin
              body:=outlined_finally_body(n,known);
              if not known then
                mark_all_fields_observed(precordobservers(arg)^.fields)
              else if assigned(body) then
                foreachnodestatic(body,@mark_observed_fields_again,arg);
            end;
          else
            ;
        end;
      end;


    procedure mark_fields_observed_in(tree : tnode;fields : tlinkedlist;
      skip : tnode;readsonly : boolean);
      var
        observers : trecordobservers;
      begin
        if not assigned(tree) then
          exit;
        observers.fields:=fields;
        observers.skip:=skip;
        observers.readsonly:=readsonly;
        foreachnodestatic(tree,@mark_observed_fields,@observers);
      end;


    function mark_outlined_finally_in_loop(var n : tnode;arg : pointer) : foreachnoderesult;
      var
        body : tnode;
        known : boolean;
      begin
        result:=fen_false;
        if n.nodetype<>tryfinallyn then
          exit;
        body:=outlined_finally_body(n,known);
        if not known then
          mark_all_fields_observed(tlinkedlist(arg))
        else
          mark_fields_observed_in(body,tlinkedlist(arg),nil,false);
      end;


    function is_this_node(var n : tnode;arg : pointer) : foreachnoderesult;
      begin
        if n=tnode(arg) then
          result:=fen_norecurse_true
        else
          result:=fen_false;
      end;


    function may_revisit_before_try(var n : tnode;arg : pointer) : foreachnoderesult;
      begin
        result:=fen_false;
        if (n.nodetype=goton) or
           ((n.nodetype in [forn,whilerepeatn]) and
            foreachnodestatic(n,@is_this_node,ptrycontinuation(arg)^.guarded)) then
          result:=fen_norecurse_true;
      end;


    function mark_try_continuation(var n : tnode;arg : pointer) : foreachnoderesult;
      var
        statement : tnode;
      begin
        result:=fen_false;
        if n.nodetype<>statementn then
          exit;
        statement:=tstatementnode(n).statement;
        if assigned(statement) and
           foreachnodestatic(statement,@is_this_node,
             ptrycontinuation(arg)^.guarded) then
          begin
            ptrycontinuation(arg)^.found:=true;
            mark_fields_observed_in(tstatementnode(n).next,
              ptrycontinuation(arg)^.fields,nil,true);
          end;
      end;


    procedure mark_fields_after_try(root,guarded : tnode;fields : tlinkedlist);
      var
        continuation : ttrycontinuation;
      begin
        continuation.fields:=fields;
        continuation.guarded:=guarded;
        continuation.found:=false;
        { A surrounding loop or a goto can run earlier statements again.
          Otherwise only the tails of the statement lists containing this
          try can observe a field after its handler. }
        if not foreachnodestatic(root,@may_revisit_before_try,@continuation) then
          foreachnodestatic(root,@mark_try_continuation,@continuation);
        if not continuation.found then
          mark_fields_observed_in(root,fields,guarded,true);
      end;


    function mark_enclosing_try_observers(var n : tnode;arg : pointer) : foreachnoderesult;
      var
        body : tnode;
        known : boolean;
      begin
        result:=fen_false;
        if not(n.nodetype in [tryexceptn,tryfinallyn]) or
           not assigned(tbinarynode(n).left) or
           not foreachnodestatic(tbinarynode(n).left,@is_this_node,
             penclosingtries(arg)^.loop) then
          exit;
        if n.nodetype=tryfinallyn then
          begin
            body:=outlined_finally_body(n,known);
            if not known then
              mark_all_fields_observed(penclosingtries(arg)^.fields)
            else
              begin
                if not assigned(body) then
                  body:=ttryfinallynode(n).right;
                mark_fields_observed_in(body,penclosingtries(arg)^.fields,nil,true);
              end;
          end
        else if penclosingtries(arg)^.leftbyexception then
          begin
            { the handlers, and everything the routine goes on with behind
              them: all of it but the guarded block }
            mark_fields_observed_in(ttryexceptnode(n).right,
              penclosingtries(arg)^.fields,nil,true);
            mark_fields_observed_in(ttryexceptnode(n).t1,
              penclosingtries(arg)^.fields,nil,true);
            mark_fields_after_try(penclosingtries(arg)^.root,n,
              penclosingtries(arg)^.fields);
          end;
      end;


    function find_exit_of_routine(var n : tnode;arg : pointer) : foreachnoderesult;
      begin
        result:=fen_false;
        case n.nodetype of
          exitn:
            result:=fen_norecurse_true;
          blockn:
            { the body of an inlined routine: its Exit leaves the block }
            if nf_block_with_exit in n.flags then
              result:=fen_norecurse_false;
          else
            ;
        end;
      end;


    function find_jump_out_of_loop(var n : tnode;arg : pointer) : foreachnoderesult;
      var
        target : tlabelnode;
      begin
        result:=fen_false;
        if n.nodetype<>goton then
          exit;
        target:=resolved_goto_target(tgotonode(n));
        if not assigned(target) or
           (precordjumps(arg)^.labels.indexof(target)<0) then
          result:=fen_norecurse_true;
      end;


    function find_jump_into_loop(var n : tnode;arg : pointer) : foreachnoderesult;
      var
        target : tlabelnode;
      begin
        result:=fen_false;
        if n=precordjumps(arg)^.loop then
          exit(fen_norecurse_false);
        if n.nodetype<>goton then
          exit;
        target:=resolved_goto_target(tgotonode(n));
        if not assigned(target) or
           (precordjumps(arg)^.labels.indexof(target)>=0) then
          result:=fen_norecurse_true;
      end;


    function loop_has_foreign_jump(loop,root : tnode) : boolean;
      var
        jumps : trecordjumps;
        i : longint;
      begin
        result:=false;
        jumps.loop:=loop;
        jumps.labels:=tfplist.create;
        try
          foreachnodestatic(loop,@collect_loop_label,jumps.labels);
          if foreachnodestatic(loop,@find_jump_out_of_loop,@jumps) then
            exit(true);
          if jumps.labels.count=0 then
            exit;
          for i:=0 to jumps.labels.count-1 do
            if assigned(tlabelnode(jumps.labels[i]).labsym) and
               (tlabelnode(jumps.labels[i]).labsym.nonlocal or
                tlabelnode(jumps.labels[i]).labsym.has_nonlocal_entry) then
              exit(true);
          result:=foreachnodestatic(root,@find_jump_into_loop,@jumps);
        finally
          jumps.labels.free;
        end;
      end;


    procedure drop_observed_fields(loop,root : tnode;fields : tlinkedlist);
      var
        enclosing : tenclosingtries;
        pair,
        nextpair : TFieldTempPair;
      begin
        if loop_has_foreign_jump(loop,root) then
          mark_all_fields_observed(fields)
        else
          begin
            foreachnodestatic(loop,@mark_outlined_finally_in_loop,fields);
            enclosing.fields:=fields;
            enclosing.loop:=loop;
            enclosing.root:=root;
            enclosing.leftbyexception:=effect_may_trap(loop);
            enclosing.leftbyexit:=foreachnodestatic(loop,@find_exit_of_routine,nil);
            if enclosing.leftbyexception or enclosing.leftbyexit then
              begin
                foreachnodestatic(root,@mark_enclosing_try_observers,@enclosing);
                { An implicit Finalize may read any field when the routine is
                  left without passing the store behind the loop. }
                pair:=TFieldTempPair(fields.First);
                while assigned(pair) do
                  begin
                    if pair.FieldWritten and
                       (mop_finalize in trecordsymtable(trecorddef(
                         pair.BaseSymbol.vardef).symtable).managementoperators) then
                      pair.Observed:=true;
                    pair:=TFieldTempPair(pair.Next);
                  end;
              end;
          end;
        pair:=TFieldTempPair(fields.First);
        while assigned(pair) do
          begin
            nextpair:=TFieldTempPair(pair.Next);
            if pair.Observed then
              begin
                pair.TempCreate.Free;
                fields.Remove(pair);
                pair.Free;
              end;
            pair:=nextpair;
          end;
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
        LoopCalls: Boolean;
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

                { Fields whose address escapes into a call cannot be promoted.
                  Nor is a field the loop only writes worth a register when
                  the loop calls: in the record each write is one store where
                  it stands, in a temp the field holds a register the call
                  saves for the whole loop - one Self or a variable of the
                  loop would otherwise have (the loop of fcl-xml's
                  ParseMarkupDecl pushed Self out of them on SysV) }
                LoopCalls:=foreachnodestatic(pm_postprocess,n,@record_loop_calls,nil);
                ThisTemp:=TFieldTempPair(RecordData.Fields.First);
                while Assigned(ThisTemp) do
                  begin
                    NextTemp:=TFieldTempPair(ThisTemp.Next);
                    if ThisTemp.AddressEscapes or
                       (LoopCalls and not ThisTemp.FieldRead) then
                      begin
                        ThisTemp.TempCreate.Free;
                        RecordData.Fields.Remove(ThisTemp);
                      end;
                    ThisTemp:=NextTemp;
                  end;

                { Nor can the fields somebody looks at in the record while
                  the loop runs or when it is left }
                if RecordData.Fields.Count > 0 then
                  drop_observed_fields(n,pnode(arg)^,RecordData.Fields);

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
        { the routine as it stands at that moment goes along: the loops in
          it are replaced one by one }
        Result:=foreachnodestatic(pm_preprocess,n,@_optimize_record_writes,@n);
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
          (tfornode(n).loopflags*loopcounterexitdiscardflags<>[]) and
          { The ordinary successor may not observe the source counter, while a
            call in the body can still transfer to an outer label which does.
            Reversing such a loop changes the value visible at that abrupt
            continuation. }
          not(tnf_loopvar_observable_on_abrupt_exit in n.transientflags) and
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
