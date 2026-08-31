{
    Conservative effect model of the tree layer

    Copyright (c) 2026 by the MoonCompiler development team

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
unit opteffect;

{ The single owner of the tree-layer effect model documented in
  doc/OPTIMIZER.md.  Every future tree optimization asks THIS unit what a tree
  reads and writes, whether it may trap or synchronize, and why the model
  refused a narrower answer.  No pass is allowed to grow its own memory
  analysis.

  The model separates two independent axes:

  - storage classes (taliasclass): WHERE the memory lives.  ac_local is the
    only class with exact symbol identity; every indirect access maps to the
    conservative "wide" set of all classes except ac_local (the frontend
    guarantees that a local without addr_taken is unreachable through any
    pointer; the one exception - absolute overlays, which do not set
    addr_taken on their target - is resolved explicitly by the classifier);

  - instruction effects (tinsteffect): WHAT the operation does beyond plain
    reads and writes: may synchronize (full barrier), involves managed-type
    helpers (may run user Initialize/Finalize/Copy), may trap (a trapping
    instruction observes all previous stores).

  The walker is deliberately closed: any node kind it does not explicitly
  prove harmless receives the maximal effect (reads and writes everything,
  including all locals, with every instruction effect).  Errors are therefore
  only possible in the direction of MORE effects, never fewer.

  Reason ids (teffectreason) are a stable machine contract: tests and tooling
  match them literally.  Extend the list if needed, but never rename existing
  ids and never introduce two ids for the same physical meaning.

  Remark policy of observe mode: every reason occurrence emits one
  machine-stable remark line; a node normally produces at most one remark
  (the most specific reason), except accesses that carry two independent
  facts (an absolute overlay journals the alias and what it lands on).
  er_may_trap is only remarked for explicit trap sources (div/mod, checked
  arithmetic, raise, checked casts); the implicit nil-dereference trap of
  heap accesses sets ie_trap in the effect without its own remark, otherwise
  every array access would drown the statistics.  er_may_sync is reserved:
  in v1 every synchronization source has a more specific reason
  (opaque_call, volatile_or_atomic, inline_asm, managed_operation).

  v1 closure carriers that refine the ARCHITECTURE record: the boolean pair
  runbounded/wunbounded distinguishes "reads/writes the locals enumerated in
  rsyms/wsyms" from "reads/writes ALL locals" (asm, unknown nodes) - a plain
  set cannot carry that after a union; hastemps records that the tree
  contains temp nodes, for which v1 has no identity carrier (review R2-02):
  consumers must not treat temp-carrying trees as candidates, and
  effects_conflict answers "conflict" whenever either side carries temps. }

{$i fpcdefs.inc}

  interface

    uses
      globtype,cclasses,
      node,
      symdef;

    type
      { storage classes - ARCHITECTURE paragraph 2.1; only physical storages }
      taliasclass = (
        { current frame, address not taken: the only class with exact
          symbol identity }
        ac_local,
        { frame slots with escaped address; fields of class/interface
          instances; heap of unknown structure }
        ac_escaped,
        { own heap payload of a dynamic array / ansistring / unicodestring }
        ac_heapelem,
        { statics accessed directly by name }
        ac_global,
        ac_threadvar,
        { locals visible to nested routines/funclets }
        ac_parentframe
      );
      taliasclasses = set of taliasclass;

      { instruction effects - properties of the operation, not of memory }
      tinsteffect = (
        { possible synchronization: volatile/atomic access, asm, call without
          a proven absence of synchronization inside.  Full barrier. }
        ie_sync,
        { managed-type helpers involved: the node is as opaque as a call and
          may run user Initialize/Finalize/Copy }
        ie_managed,
        { may trap/throw: observes all previous stores (CONTRACT paragraph 1) }
        ie_trap
      );
      tinsteffects = set of tinsteffect;

      { stable reason ids: why the model refused a narrower classification.
        The spelling of effect_reason_str is a wire contract for tests. }
      teffectreason = (
        er_none,
        er_unknown_node,
        er_opaque_call,
        er_pointer_alias,
        er_byref_alias,
        er_global_memory,
        er_threadvar_memory,
        er_volatile_or_atomic,
        er_inline_asm,
        er_managed_operation,
        er_may_trap,
        er_may_sync,
        er_fp_environment,
        er_compiler_temp,
        er_property_access,
        er_captured_or_outer_scope,
        er_string_cow
      );

      teffect = record
        rclasses,
        wclasses : taliasclasses;
        ieffects : tinsteffects;
        { exact symbol identities, only for ac_local (element type: tsym).
          nil until the first symbol is recorded; owned by the effect and
          released by effect_done.  The symbols themselves belong to their
          symtables and must not be stored beyond the analysis. }
        rsyms,
        wsyms : TFPList;
        { ac_local without enumerable symbols ("reads/writes ALL locals") }
        runbounded,
        wunbounded : boolean;
        { tree contains temp nodes: v1 has no temp identity (R2-02) }
        hastemps : boolean;
      end;

    const
      { all storage classes reachable through any indirection: everything
        except exact locals (frontend guarantee, ARCHITECTURE 2.1) }
      wideclasses = [ac_escaped,ac_heapelem,ac_global,ac_threadvar,ac_parentframe];
      { conservative closure: everything, including all locals }
      allclasses = [low(taliasclass)..high(taliasclass)];
      allinsteffects = [low(tinsteffect)..high(tinsteffect)];

      effect_reason_str : array[teffectreason] of string[24] = (
        'none',
        'unknown_node',
        'opaque_call',
        'pointer_alias',
        'byref_alias',
        'global_memory',
        'threadvar_memory',
        'volatile_or_atomic',
        'inline_asm',
        'managed_operation',
        'may_trap',
        'may_sync',
        'fp_environment',
        'compiler_temp',
        'property_access',
        'captured_or_outer_scope',
        'string_cow'
      );

    procedure effect_init(out e : teffect);
    procedure effect_done(var e : teffect);
    procedure effect_union(var dst : teffect; const src : teffect);

    { the model query: conservative effect of the whole tree n.
      e must be initialized with effect_init and released with effect_done. }
    procedure tree_effect(n : tnode; var e : teffect);

    { may the trees behind a and b touch the same memory, or does a barrier
      forbid reordering them?  v1 conflict promises (review R3-02): exact
      symbol identity inside ac_local, ac_heapelem as one class, and the
      ordinary block [ac_escaped,ac_global,ac_threadvar,ac_parentframe] where
      every pair is assumed to intersect.  ie_sync on either side is a full
      barrier.  ie_trap is a motion gate for the consumer, not an aliasing
      fact, and does not enter this predicate. }
    function effects_conflict(const a,b : teffect) : boolean;

    { Is candidate a trap-free unmanaged value expression whose only memory
      inputs are exact local/value-parameter symbols, and are those symbols
      unchanged by loop?  This is the sole F2 invariance query: LICM must not
      grow a second mutation/alias scan.  pressure is the number of distinct
      exact locals read by the loop and is only a profitability hint. }
    function effect_licm_invariant(candidate : tnode; const loopeffect : teffect;
      out pressure : longint) : boolean;

    { observe-only consumer (-OoEFFECTOBSERVE): walks the final routine tree,
      emits one machine-stable remark per classified reason occurrence and one
      aggregated per-routine summary.  Analyzes only; never touches the tree. }
    procedure effect_observe_procedure(n : tnode; pd : tprocdef);

  implementation

    uses
      cutils,
      verbose,
      compinnr,procinfo,paramgr,
      symconst,symtype,symbase,symsym,defutil,defcmp,
      nutils,nbas,nld,ncal,ncnv,ninl,nflw;

    type
      teffectwalk = record
        e : ^teffect;
        { observe mode: emit remarks }
        observing : boolean;
        counters : array[teffectreason] of longint;
        nodes : longint;
      end;
      peffectwalk = ^teffectwalk;

    procedure effect_init(out e : teffect);
      begin
        e.rclasses:=[];
        e.wclasses:=[];
        e.ieffects:=[];
        e.rsyms:=nil;
        e.wsyms:=nil;
        e.runbounded:=false;
        e.wunbounded:=false;
        e.hastemps:=false;
      end;


    procedure effect_done(var e : teffect);
      begin
        e.rsyms.free;
        e.rsyms:=nil;
        e.wsyms.free;
        e.wsyms:=nil;
      end;


    procedure addsym(var list : TFPList; sym : tsym);
      begin
        if not assigned(list) then
          list:=TFPList.Create;
        if list.IndexOf(sym)<0 then
          list.Add(sym);
      end;


    procedure addsymlist(var dst : TFPList; src : TFPList);
      var
        i : longint;
      begin
        if not assigned(src) then
          exit;
        for i:=0 to src.Count-1 do
          addsym(dst,tsym(src[i]));
      end;


    procedure effect_union(var dst : teffect; const src : teffect);
      begin
        dst.rclasses:=dst.rclasses+src.rclasses;
        dst.wclasses:=dst.wclasses+src.wclasses;
        dst.ieffects:=dst.ieffects+src.ieffects;
        addsymlist(dst.rsyms,src.rsyms);
        addsymlist(dst.wsyms,src.wsyms);
        dst.runbounded:=dst.runbounded or src.runbounded;
        dst.wunbounded:=dst.wunbounded or src.wunbounded;
        dst.hastemps:=dst.hastemps or src.hastemps;
      end;


    function symlists_intersect(a : TFPList; aunbounded : boolean;
                                b : TFPList; bunbounded : boolean) : boolean;
      var
        i : longint;
      begin
        result:=true;
        if aunbounded or bunbounded then
          exit;
        if assigned(a) and assigned(b) then
          for i:=0 to a.Count-1 do
            if b.IndexOf(a[i])>=0 then
              exit;
        result:=false;
      end;


    function classpairs_conflict(ac : taliasclasses; alist : TFPList; aunb : boolean;
                                 bc : taliasclasses; blist : TFPList; bunb : boolean) : boolean;
      const
        ordinaryclasses = [ac_escaped,ac_global,ac_threadvar,ac_parentframe];
      begin
        result:=true;
        { v1 promise: any pair inside the ordinary block intersects }
        if (ac*ordinaryclasses<>[]) and (bc*ordinaryclasses<>[]) then
          exit;
        if (ac_heapelem in ac) and (ac_heapelem in bc) then
          exit;
        if (ac_local in ac) and (ac_local in bc) and
           symlists_intersect(alist,aunb,blist,bunb) then
          exit;
        result:=false;
      end;


    function effects_conflict(const a,b : teffect) : boolean;
      begin
        result:=true;
        { full barrier }
        if ie_sync in (a.ieffects+b.ieffects) then
          exit;
        { no temp identity in v1: refuse to reason about temp-carrying trees }
        if a.hastemps or b.hastemps then
          exit;
        { write vs read/write in both directions }
        if classpairs_conflict(a.wclasses,a.wsyms,a.wunbounded,
                               b.rclasses,b.rsyms,b.runbounded) or
           classpairs_conflict(a.wclasses,a.wsyms,a.wunbounded,
                               b.wclasses,b.wsyms,b.wunbounded) or
           classpairs_conflict(a.rclasses,a.rsyms,a.runbounded,
                               b.wclasses,b.wsyms,b.wunbounded) then
          exit;
        result:=false;
      end;


    function effect_licm_invariant(candidate : tnode; const loopeffect : teffect;
      out pressure : longint) : boolean;
      var
        ce : teffect;
        i : longint;
        sym : tabstractvarsym;
      begin
        result:=false;
        pressure:=0;
        if not assigned(candidate) or not assigned(candidate.resultdef) or
           is_managed_type(candidate.resultdef) then
          exit;
        effect_init(ce);
        try
          tree_effect(candidate,ce);
          if assigned(loopeffect.rsyms) then
            pressure:=loopeffect.rsyms.count;
          { The expression itself must be a plain computation over exact
            current-frame values.  In particular: no compiler temp identity,
            no implicit helper, no trap, no write, no escaped/global/heap
            read, and no unenumerated local set. }
          if ce.hastemps or ce.runbounded or ce.wunbounded or
             (ce.ieffects<>[]) or (ce.wclasses<>[]) or
             ((ce.rclasses-[ac_local])<>[]) then
            exit;
          if (ac_local in ce.rclasses) and not assigned(ce.rsyms) then
            exit;
          if assigned(ce.rsyms) then
            for i:=0 to ce.rsyms.count-1 do
              begin
                sym:=tabstractvarsym(ce.rsyms[i]);
                if is_managed_type(sym.vardef) or
                   not((sym.typ=localvarsym) or
                       ((sym.typ=paravarsym) and
                        (tparavarsym(sym).varspez=vs_value))) then
                  exit;
              end;
          { The loop effect includes its condition, body and lowered latch.
            Its writes/barriers are therefore the only mutation authority. }
          if effects_conflict(ce,loopeffect) then
            exit;
          result:=true;
        finally
          effect_done(ce);
        end;
      end;


{*****************************************************************************
                          Observe remarks and counters
*****************************************************************************}

    { emitremark=false counts the reason in the aggregated statistics
      without its own per-node remark line: used for the implicit
      nil-dereference trap of heap/instance accesses, where a remark per
      array access would flood the output while the refusal statistics
      must stay complete (review F-05) }
    procedure journal(var ctx : teffectwalk; n : tnode; reason : teffectreason;
                      const detail : string; emitremark : boolean = true);
      var
        s : ansistring;
      begin
        inc(ctx.counters[reason]);
        if not (ctx.observing and emitremark) then
          exit;
        s:='reason='+effect_reason_str[reason]+' node='+nodetype2str[n.nodetype];
        if detail<>'' then
          s:=s+' detail='+detail;
        CGMessagePos1(n.fileinfo,cg_d_effect_observe,s);
      end;


{*****************************************************************************
                     Symbol classification (the one classifier)
*****************************************************************************}

    { The single classification function of data symbols, built only on
      frontend facts: sym kind, varspez, addr_taken, different_scope,
      vo_is_thread_var, vo_volatile.  Everybody asks it; nobody duplicates
      it.  An absolute overlay resolves to its target symbol: the frontend
      does NOT set addr_taken on the target of an equal-size overlay, so the
      only sound mapping is "access to the overlay is an access to the
      target". }
    procedure classify_var_sym(var ctx : teffectwalk; n : tnode;
                               sym : tabstractvarsym; iswrite : boolean);
      var
        classes : taliasclasses;
        exact : boolean;
        reason : teffectreason;
        target : ppropaccesslistitem;
      begin
        classes:=[];
        exact:=false;
        reason:=er_none;
        case sym.typ of
          staticvarsym:
            begin
              if vo_is_thread_var in sym.varoptions then
                begin
                  classes:=[ac_threadvar];
                  reason:=er_threadvar_memory;
                end
              else
                begin
                  classes:=[ac_global];
                  reason:=er_global_memory;
                end;
            end;
          localvarsym,
          paravarsym:
            begin
              if (sym.typ=paravarsym) and
                 ((tparavarsym(sym).varspez in [vs_var,vs_out,vs_constref]) or
                  is_open_array(sym.vardef) or
                  (sym.vardef.typ=formaldef) or
                  { a const parameter that the ABI passes by address is a
                    live alias of the caller's storage (the frontend does not
                    set addr_taken on a const actual), so it may overlap
                    anything the caller can reach }
                  ((tparavarsym(sym).varspez=vs_const) and
                   assigned(sym.owner) and
                   (sym.owner.defowner is tabstractprocdef) and
                   paramanager.push_addr_param(vs_const,sym.vardef,
                     tabstractprocdef(sym.owner.defowner).proccalloption))) then
                begin
                  { access goes through a caller-supplied reference: the
                    target may live anywhere except our exact locals }
                  classes:=wideclasses;
                  reason:=er_byref_alias;
                end
              else if sym.addr_taken then
                begin
                  classes:=[ac_escaped];
                  if sym.different_scope then
                    include(classes,ac_parentframe);
                  reason:=er_pointer_alias;
                end
              else if sym.different_scope then
                begin
                  classes:=[ac_parentframe];
                  reason:=er_captured_or_outer_scope;
                end
              else
                begin
                  classes:=[ac_local];
                  exact:=true;
                end;
            end;
          absolutevarsym:
            begin
              target:=nil;
              if (tabsolutevarsym(sym).abstyp=tovar) and
                 assigned(tabsolutevarsym(sym).ref) then
                target:=tabsolutevarsym(sym).ref.firstsym;
              if assigned(target) and
                 (target^.sltype=sl_load) and
                 (target^.sym is tabstractvarsym) then
                begin
                  { the overlay is exactly the target's memory (this also
                    covers the Result/function-name funcret aliases the
                    frontend builds as absolutevarsyms) }
                  classify_var_sym(ctx,n,tabstractvarsym(target^.sym),iswrite);
                  exit;
                end;
              { absolute over a raw address (or an unresolvable target) }
              classes:=wideclasses;
              reason:=er_pointer_alias;
            end;
          else
            begin
              { unknown data symbol kind: conservative closure }
              classes:=allclasses;
              if iswrite then
                ctx.e^.wunbounded:=true
              else
                ctx.e^.runbounded:=true;
              reason:=er_unknown_node;
            end;
        end;
        if vo_volatile in sym.varoptions then
          begin
            include(ctx.e^.ieffects,ie_sync);
            reason:=er_volatile_or_atomic;
          end;
        if iswrite then
          begin
            ctx.e^.wclasses:=ctx.e^.wclasses+classes;
            if exact then
              addsym(ctx.e^.wsyms,sym);
          end
        else
          begin
            ctx.e^.rclasses:=ctx.e^.rclasses+classes;
            if exact then
              addsym(ctx.e^.rsyms,sym);
          end;
        if reason<>er_none then
          journal(ctx,n,reason,sym.realname);
      end;


{*****************************************************************************
                              Effect helpers
*****************************************************************************}

    procedure add_wide(var ctx : teffectwalk; doread,dowrite : boolean);
      begin
        if doread then
          ctx.e^.rclasses:=ctx.e^.rclasses+wideclasses;
        if dowrite then
          ctx.e^.wclasses:=ctx.e^.wclasses+wideclasses;
      end;


    { conservative closure: reads and writes everything, all locals included,
      with every instruction effect }
    procedure add_everything(var ctx : teffectwalk);
      begin
        ctx.e^.rclasses:=allclasses;
        ctx.e^.wclasses:=allclasses;
        ctx.e^.ieffects:=ctx.e^.ieffects+allinsteffects;
        ctx.e^.runbounded:=true;
        ctx.e^.wunbounded:=true;
      end;


    { a managed operation without a proven passport: as wide as a call and
      may run user Initialize/Finalize/Copy (CONTRACT paragraph 6) }
    procedure add_managed_opaque(var ctx : teffectwalk);
      begin
        add_wide(ctx,true,true);
        ctx.e^.ieffects:=ctx.e^.ieffects+[ie_sync,ie_managed,ie_trap];
      end;


    { an opaque helper call hidden behind a language operation (big set
      arithmetic, ...): full barrier like any call without a summary }
    procedure add_opaque_helper(var ctx : teffectwalk);
      begin
        add_wide(ctx,true,true);
        ctx.e^.ieffects:=ctx.e^.ieffects+[ie_sync,ie_trap];
      end;


    function checked_switches(n : tnode) : boolean;
      begin
        result:=(n.localswitches*[cs_check_range,cs_check_overflow])<>[];
      end;


    { operations on sets beyond the machine word are opaque RTL helpers,
      small sets are pure bit arithmetic }
    function bigset_def(def : tdef) : boolean;
      begin
        result:=assigned(def) and (def.typ=setdef) and not is_smallset(def);
      end;


    { string-typed values whose operations lower to managed RTL helpers }
    function stringlike_def(def : tdef) : boolean;
      begin
        result:=is_dynamicstring(def) or is_widestring(def) or
          is_shortstring(def);
      end;


{*****************************************************************************
                                The walker
*****************************************************************************}

    procedure walk_tree(var ctx : teffectwalk; n : tnode); forward;

    { effect of writing INTO the designator n (the store target).  Descends
      the designator spine; non-spine children (index expressions, pointer
      expressions) are walked as reads.  istop marks the outermost designator
      node: a temprefn that IS the whole target writes only the temp itself
      (no identity in v1), while a temprefn used as the BASE of a designator
      holds the address of unknown storage and the write is wide
      (Pascal-check hole 2: with-temps). }
    procedure add_store_target(var ctx : teffectwalk; n : tnode; istop : boolean);
      begin
        if not assigned(n) then
          exit;
        inc(ctx.nodes);
        case n.nodetype of
          loadn:
            begin
              if tloadnode(n).symtableentry is tabstractvarsym then
                classify_var_sym(ctx,n,tabstractvarsym(tloadnode(n).symtableentry),true)
              else
                begin
                  ctx.e^.wclasses:=allclasses;
                  ctx.e^.wunbounded:=true;
                  journal(ctx,n,er_unknown_node,'store:'+tloadnode(n).symtableentry.realname);
                end;
            end;
          vecn:
            begin
              { the index expression is evaluated (read) }
              walk_tree(ctx,tbinarynode(n).right);
              if checked_switches(n) then
                begin
                  include(ctx.e^.ieffects,ie_trap);
                  journal(ctx,n,er_may_trap,'');
                end;
              if is_dynamic_array(tbinarynode(n).left.resultdef) then
                begin
                  { element store writes the payload and READS the descriptor;
                    Delphi dynamic arrays are not COW (axiom A17) }
                  include(ctx.e^.wclasses,ac_heapelem);
                  include(ctx.e^.ieffects,ie_trap);
                  journal(ctx,n,er_may_trap,'',false);
                  walk_tree(ctx,tbinarynode(n).left);
                end
              else if is_dynamicstring(tbinarynode(n).left.resultdef) or
                      is_widestring(tbinarynode(n).left.resultdef) then
                begin
                  { S[i]:= uniquifies through an RTL helper that takes S by
                    var: the DESCRIPTOR itself is written and the payload may
                    be reallocated (Pascal-check hole 1, axiom A17).
                    Conservative until a passport exists: managed opaque. }
                  include(ctx.e^.wclasses,ac_heapelem);
                  add_managed_opaque(ctx);
                  journal(ctx,n,er_string_cow,'');
                  { the descriptor is both read and written }
                  walk_tree(ctx,tbinarynode(n).left);
                  add_store_target(ctx,tbinarynode(n).left,false);
                end
              else if tbinarynode(n).left.resultdef.typ=pointerdef then
                begin
                  { pointer indexing writes through the pointer }
                  add_wide(ctx,false,true);
                  include(ctx.e^.ieffects,ie_trap);
                  journal(ctx,n,er_pointer_alias,'');
                  walk_tree(ctx,tbinarynode(n).left);
                end
              else if (tbinarynode(n).left.resultdef.typ=arraydef) or
                      is_shortstring(tbinarynode(n).left.resultdef) then
                { static array / shortstring / open array: writing an element
                  writes the base storage itself (open-array bases classify
                  wide through their by-ref symbol) }
                add_store_target(ctx,tbinarynode(n).left,false)
              else
                begin
                  { unknown designator base }
                  ctx.e^.wclasses:=allclasses;
                  ctx.e^.wunbounded:=true;
                  ctx.e^.ieffects:=ctx.e^.ieffects+allinsteffects;
                  journal(ctx,n,er_unknown_node,'store-base');
                  walk_tree(ctx,tbinarynode(n).left);
                end;
            end;
          subscriptn:
            begin
              if is_implicit_pointer_object_type(tunarynode(n).left.resultdef) then
                begin
                  { field of a heap instance }
                  include(ctx.e^.wclasses,ac_escaped);
                  include(ctx.e^.ieffects,ie_trap);
                  journal(ctx,n,er_may_trap,'',false);
                  walk_tree(ctx,tunarynode(n).left);
                end
              else
                { field of a value record/object: writing the field writes
                  the record variable itself }
                add_store_target(ctx,tunarynode(n).left,false);
            end;
          derefn:
            begin
              add_wide(ctx,false,true);
              include(ctx.e^.ieffects,ie_trap);
              journal(ctx,n,er_pointer_alias,'');
              walk_tree(ctx,tunarynode(n).left);
            end;
          typeconvn:
            begin
              if nf_absolute in n.flags then
                { an absolute reinterpretation of the same storage: the
                  parser already resolved the overlay, the child carries the
                  target symbol (this is also how every Result access looks) }
                add_store_target(ctx,tunarynode(n).left,istop)
              else if ttypeconvnode(n).convtype in [tc_equal,tc_int_2_int,
                tc_int_2_bool,tc_bool_2_bool,tc_bool_2_int,tc_char_2_char] then
                { lvalue casts keep the same storage }
                add_store_target(ctx,tunarynode(n).left,istop)
              else
                begin
                  add_wide(ctx,false,true);
                  include(ctx.e^.ieffects,ie_trap);
                  journal(ctx,n,er_unknown_node,'store-conv');
                  walk_tree(ctx,tunarynode(n).left);
                end;
            end;
          calln:
            begin
              { the store lands behind a call result (e.g. the payload
                pointer returned by a COW uniquify helper): wide write, and
                the call itself contributes its own barrier }
              add_wide(ctx,false,true);
              include(ctx.e^.ieffects,ie_trap);
              walk_tree(ctx,n);
            end;
          temprefn:
            begin
              ctx.e^.hastemps:=true;
              if istop and
                 ((ttemprefnode(n).tempflags*[ti_addr_taken,ti_reference])=[]) then
                { the temp itself is the target: v1 has no temp identity, the
                  empty effect is safe only because consumers must not accept
                  temp-carrying trees (hastemps) }
                journal(ctx,n,er_compiler_temp,'store')
              else
                begin
                  { writing THROUGH a temp: address of unknown storage }
                  add_wide(ctx,false,true);
                  include(ctx.e^.ieffects,ie_trap);
                  journal(ctx,n,er_compiler_temp,'store-base');
                end;
            end;
          else
            begin
              { any other store target: conservative closure }
              ctx.e^.wclasses:=allclasses;
              ctx.e^.wunbounded:=true;
              ctx.e^.ieffects:=ctx.e^.ieffects+allinsteffects;
              journal(ctx,n,er_unknown_node,'store:'+nodetype2str[n.nodetype]);
              walk_tree(ctx,n);
            end;
        end;
      end;


    { first (leftmost declared) argument of an intrinsic; the compiler wraps
      multi-argument intrinsics in a callparan chain whose head carries the
      written operand (see tinlinenode.mark_write) }
    function inline_arg1(n : tinlinenode) : tnode;
      begin
        result:=n.left;
        if assigned(result) and (result.nodetype=callparan) then
          result:=tcallparanode(result).left;
      end;


    function inline_arg2(n : tinlinenode) : tnode;
      begin
        result:=nil;
        if assigned(n.left) and (n.left.nodetype=callparan) then
          begin
            result:=tcallparanode(n.left).right;
            if assigned(result) and (result.nodetype=callparan) then
              result:=tcallparanode(result).left;
          end;
      end;


    procedure add_inline_effect(var ctx : teffectwalk; n : tinlinenode);
      var
        arg : tnode;
      begin
        case n.inlinenumber of
          { pure value operations }
          in_lo_word,in_hi_word,in_lo_long,in_hi_long,in_lo_qword,in_hi_qword,
          in_ord_x,in_chr_byte,in_assigned_x,
          in_sizeof_x,in_bitsizeof_x,in_typeof_x,in_typeinfo_x,
          in_gettypekind_x,in_ismanagedtype_x,in_isconstvalue_x,
          in_ror_x,in_ror_x_y,in_rol_x,in_rol_x_y,in_sar_x,in_sar_x_y,
          in_bsf_x,in_bsr_x,in_popcnt_x,
          in_addr_x,in_ofs_x,in_prefetch_var,in_default_x,
          in_get_frame,in_get_caller_addr,in_get_caller_frame,
          in_aligned_x,in_unaligned_x,
          in_min_dword,in_min_longint,in_max_dword,in_max_longint,
          in_min_qword,in_min_int64,in_max_qword,in_max_int64:
            ;
          { the length/bound of a heap container is stored in the heap block
            HEADER in front of the payload (dynarr.inc/astrings.inc): the
            read touches escaped memory, not just the descriptor symbol -
            a pointer write into the header must conflict with it
            (ARCHITECTURE 2.2: "E (header) + sym") }
          in_length_x,in_low_x,in_high_x:
            begin
              arg:=inline_arg1(n);
              if assigned(arg) and
                 (is_dynamic_array(arg.resultdef) or
                  is_dynamicstring(arg.resultdef) or
                  is_widestring(arg.resultdef)) then
                include(ctx.e^.rclasses,ac_escaped);
            end;
          { pure, but may range/overflow-check }
          in_pred_x,in_succ_x,in_abs_long:
            begin
              if checked_switches(n) then
                begin
                  include(ctx.e^.ieffects,ie_trap);
                  journal(ctx,n,er_may_trap,'');
                end;
            end;
          { value-pure FP operations: the FP environment is observable
            (CONTRACT paragraph 4), so they are never unconditionally
            trap-free }
          in_trunc_real,in_round_real,in_frac_real,in_int_real,
          in_pi_real,in_abs_real,in_sqr_real,in_sqrt_real,
          in_fma_single,in_fma_double,in_fma_extended,in_fma_float128,
          in_max_single,in_max_double,in_min_single,in_min_double,
          in_min_quad,in_max_quad:
            begin
              include(ctx.e^.ieffects,ie_trap);
              journal(ctx,n,er_fp_environment,'');
            end;
          { volatile view: every access executes, full barrier }
          in_volatile_x:
            begin
              include(ctx.e^.ieffects,ie_sync);
              journal(ctx,n,er_volatile_or_atomic,'');
            end;
          { atomic intrinsics: read-modify-write of memory + barrier }
          in_atomic_inc,in_atomic_dec,in_atomic_xchg,in_atomic_cmp_xchg:
            begin
              add_wide(ctx,true,true);
              ctx.e^.ieffects:=ctx.e^.ieffects+[ie_sync,ie_trap];
              journal(ctx,n,er_volatile_or_atomic,'');
            end;
          { precise writers: the first argument is the written operand }
          in_inc_x,in_dec_x:
            begin
              add_store_target(ctx,inline_arg1(n),true);
              if checked_switches(n) then
                begin
                  include(ctx.e^.ieffects,ie_trap);
                  journal(ctx,n,er_may_trap,'');
                end;
            end;
          in_include_x_y,in_exclude_x_y:
            add_store_target(ctx,inline_arg1(n),true);
          { the load-modify-store intrinsics (in_and_assign_x_y & co) are
            deliberately NOT whitelisted: they are only created by
            do_optloadmodifystore, which runs AFTER every point this model
            is called from (the observe hook and the PLAN's tree
            consumers); should the pipeline ever move, the conservative
            default classifies them as everything - review F-06 }
          in_swapvalues:
            begin
              add_store_target(ctx,inline_arg1(n),true);
              add_store_target(ctx,inline_arg2(n),true);
            end;
          { managed/compilerproc helpers: maximal until a proven passport
            (may run user Initialize/Finalize/Copy - CONTRACT paragraph 6) }
          in_setlength_x,in_finalize_x,in_initialize_x,in_copy_x,
          in_concat_x,in_insert_x_y_z,in_delete_x_y_z,in_setstring_x_y_z,
          in_str_x_string,in_val_x,in_writestr_x,in_readstr_x,
          in_new_x,in_dispose_x,in_box_x,in_unbox_x_y:
            begin
              add_managed_opaque(ctx);
              journal(ctx,n,er_managed_operation,'');
            end;
          else
            begin
              { unknown intrinsic: conservative closure }
              add_everything(ctx);
              journal(ctx,n,er_unknown_node,'inlinen:'+tostr(longint(n.inlinenumber)));
            end;
        end;
      end;


    procedure add_call_effect(var ctx : teffectwalk; n : tcallnode);
      var
        p : tcallparanode;
        detail : string;
      begin
        { a call without a proven transitive summary is a full barrier: may
          read and write everything reachable, synchronize and throw }
        add_wide(ctx,true,true);
        ctx.e^.ieffects:=ctx.e^.ieffects+[ie_sync,ie_trap];
        detail:='';
        if assigned(n.procdefinition) and
           (n.procdefinition.typ=procdef) and
           assigned(tprocdef(n.procdefinition).procsym) then
          detail:=tprocdef(n.procdefinition).procsym.realname;
        if nf_isproperty in n.flags then
          journal(ctx,n,er_property_access,detail)
        else
          journal(ctx,n,er_opaque_call,detail);
        { var/out actuals are written by the callee.  The wide effect above
          covers escaped storage, but a local passed to a proven non-capturing
          formal keeps addr_taken=false (axiom A1) and only this explicit
          store makes its mutation visible. }
        p:=tcallparanode(n.left);
        while assigned(p) do
          begin
            if assigned(p.parasym) and
               (p.parasym.varspez in [vs_var,vs_out]) and
               assigned(p.left) then
              begin
                journal(ctx,p.left,er_byref_alias,'');
                add_store_target(ctx,p.left,true);
              end;
            p:=tcallparanode(p.right);
          end;
        { the call writes its result location }
        if assigned(n.funcretnode) then
          add_store_target(ctx,n.funcretnode,true);
      end;


    function effect_walk_node(var n : tnode; arg : pointer) : foreachnoderesult;
      var
        ctx : peffectwalk absolute arg;
        sym : tsym;
        i : longint;
      begin
        result:=fen_false;
        inc(ctx^.nodes);
        case n.nodetype of
          { leaves without memory effects }
          ordconstn,realconstn,stringconstn,pointerconstn,niln,setconstn,
          guidconstn,typen,rttin,nothingn,setelementn,arrayconstructorrangen,
          loadvmtaddrn,loadparentfpn,addrn,
          { pure control flow }
          blockn,statementn,ifn,whilerepeatn,casen,labeln,goton,breakn,
          continuen,callparan,tryexceptn,tryfinallyn:
            ;
          { value operations; sets beyond the machine word and string forms
            lower to RTL helpers, real arithmetic interacts with the
            observable FP environment }
          addn,muln,subn,symdifn,orn,xorn,andn,
          ltn,lten,gtn,gten,equaln,unequaln,inn,
          shrn,shln,notn,unaryminusn,unaryplusn:
            begin
              if bigset_def(n.resultdef) or
                 ((n.nodetype=inn) and
                  bigset_def(tbinarynode(n).right.resultdef)) or
                 ((n.nodetype in [ltn,lten,gtn,gten,equaln,unequaln]) and
                  bigset_def(tbinarynode(n).left.resultdef)) then
                begin
                  { big-set arithmetic and comparison: opaque RTL helper }
                  add_opaque_helper(ctx^);
                  journal(ctx^,n,er_opaque_call,'set-helper');
                end
              else if ((n.nodetype=addn) and
                       (stringlike_def(n.resultdef) or
                        is_dynamic_array(n.resultdef))) or
                      ((n.nodetype in [ltn,lten,gtn,gten,equaln,unequaln]) and
                       stringlike_def(tbinarynode(n).left.resultdef)) then
                begin
                  { concatenation and string comparison: managed RTL helpers }
                  add_managed_opaque(ctx^);
                  journal(ctx^,n,er_managed_operation,'');
                end
              else if (n.resultdef.typ=floatdef) or
                      ((n.nodetype in [ltn,lten,gtn,gten,equaln,unequaln]) and
                       (tbinarynode(n).left.resultdef.typ=floatdef)) then
                begin
                  include(ctx^.e^.ieffects,ie_trap);
                  journal(ctx^,n,er_fp_environment,'');
                end
              else if checked_switches(n) then
                begin
                  include(ctx^.e^.ieffects,ie_trap);
                  journal(ctx^,n,er_may_trap,'');
                end;
            end;
          divn,modn:
            begin
              include(ctx^.e^.ieffects,ie_trap);
              journal(ctx^,n,er_may_trap,'');
            end;
          slashn:
            begin
              include(ctx^.e^.ieffects,ie_trap);
              journal(ctx^,n,er_fp_environment,'');
            end;
          loadn:
            begin
              case tloadnode(n).symtableentry.typ of
                staticvarsym,localvarsym,paravarsym,absolutevarsym:
                  classify_var_sym(ctx^,n,
                    tabstractvarsym(tloadnode(n).symtableentry),false);
                procsym,labelsym:
                  { code addresses, not data };
                else
                  begin
                    add_everything(ctx^);
                    journal(ctx^,n,er_unknown_node,
                      'load:'+tloadnode(n).symtableentry.realname);
                  end;
              end;
            end;
          vecn:
            begin
              if checked_switches(n) then
                begin
                  include(ctx^.e^.ieffects,ie_trap);
                  journal(ctx^,n,er_may_trap,'');
                end;
              if is_dynamic_array(tbinarynode(n).left.resultdef) or
                 is_dynamicstring(tbinarynode(n).left.resultdef) or
                 is_widestring(tbinarynode(n).left.resultdef) then
                begin
                  { heap payload read + descriptor read (children) + implicit
                    nil-descriptor trap }
                  include(ctx^.e^.rclasses,ac_heapelem);
                  include(ctx^.e^.ieffects,ie_trap);
                  journal(ctx^,n,er_may_trap,'',false);
                end
              else if tbinarynode(n).left.resultdef.typ=pointerdef then
                begin
                  add_wide(ctx^,true,false);
                  include(ctx^.e^.ieffects,ie_trap);
                  journal(ctx^,n,er_pointer_alias,'');
                end
              else if (tbinarynode(n).left.resultdef.typ=arraydef) or
                      is_shortstring(tbinarynode(n).left.resultdef) then
                { static/open array, shortstring: the base symbol read comes
                  from the children walk }
              else
                begin
                  add_everything(ctx^);
                  journal(ctx^,n,er_unknown_node,'vec-base');
                end;
            end;
          subscriptn:
            begin
              if is_implicit_pointer_object_type(tunarynode(n).left.resultdef) then
                begin
                  include(ctx^.e^.rclasses,ac_escaped);
                  include(ctx^.e^.ieffects,ie_trap);
                  journal(ctx^,n,er_may_trap,'',false);
                end;
              { value record/object: base symbol read comes from children }
            end;
          derefn:
            begin
              add_wide(ctx^,true,false);
              include(ctx^.e^.ieffects,ie_trap);
              journal(ctx^,n,er_pointer_alias,'');
            end;
          isn:
            { reads the instance header (vmt) }
            include(ctx^.e^.rclasses,ac_escaped);
          asn:
            begin
              { helper-based casts contribute through their call child }
              if not assigned(tasnode(n).call) then
                begin
                  include(ctx^.e^.rclasses,ac_escaped);
                  include(ctx^.e^.ieffects,ie_trap);
                  journal(ctx^,n,er_may_trap,'as-cast');
                end;
            end;
          typeconvn:
            begin
              if nf_absolute in n.flags then
                { same-storage reinterpretation; the child load carries the
                  resolved target symbol }
              else
                case ttypeconvnode(n).convtype of
                  tc_equal,tc_int_2_int,tc_int_2_bool,tc_bool_2_bool,
                  tc_bool_2_int,tc_char_2_char,tc_proc_2_procvar,
                  tc_nil_2_methodprocvar,tc_cord_2_pointer,tc_array_2_pointer:
                    begin
                      { a range-checked narrowing conversion may trap }
                      if checked_switches(n) then
                        begin
                          include(ctx^.e^.ieffects,ie_trap);
                          journal(ctx^,n,er_may_trap,'');
                        end;
                    end;
                  tc_int_2_real,tc_real_2_real,tc_real_2_currency:
                    begin
                      include(ctx^.e^.ieffects,ie_trap);
                      journal(ctx^,n,er_fp_environment,'');
                    end;
                  tc_set_to_set:
                    begin
                      if bigset_def(n.resultdef) or
                         bigset_def(ttypeconvnode(n).left.resultdef) then
                        begin
                          add_opaque_helper(ctx^);
                          journal(ctx^,n,er_opaque_call,'set-helper');
                        end;
                    end;
                  tc_pointer_2_array:
                    begin
                      { a dereference boundary }
                      add_wide(ctx^,true,false);
                      include(ctx^.e^.ieffects,ie_trap);
                      journal(ctx^,n,er_pointer_alias,'');
                    end;
                  else
                    begin
                      { string/variant/interface/dynarray conversions run
                        managed helpers; everything unlisted is opaque }
                      add_managed_opaque(ctx^);
                      journal(ctx^,n,er_managed_operation,
                        'conv:'+tostr(longint(ttypeconvnode(n).convtype)));
                    end;
                end;
            end;
          temprefn:
            begin
              ctx^.e^.hastemps:=true;
              if (ttemprefnode(n).tempflags*[ti_addr_taken,ti_reference])<>[] then
                begin
                  { the temp holds an address / its address escaped: reading
                    it can observe unknown memory }
                  add_wide(ctx^,true,false);
                  journal(ctx^,n,er_compiler_temp,'ref');
                end
              else
                journal(ctx^,n,er_compiler_temp,'');
            end;
          tempcreaten:
            { the temp init code is walked by the engine }
            ctx^.e^.hastemps:=true;
          tempdeleten:
            begin
              ctx^.e^.hastemps:=true;
              if assigned(ttempdeletenode(n).tempinfo^.typedef) and
                 is_managed_type(ttempdeletenode(n).tempinfo^.typedef) then
                begin
                  { finalization of a managed temp may run user Finalize }
                  add_managed_opaque(ctx^);
                  journal(ctx^,n,er_managed_operation,'temp-finalize');
                end;
            end;
          finalizetempsn:
            begin
              add_managed_opaque(ctx^);
              journal(ctx^,n,er_managed_operation,'finalize-temps');
            end;
          arrayconstructorn:
            begin
              { the tail links of a constructor chain carry no resultdef }
              if assigned(n.resultdef) and
                 (is_managed_type(n.resultdef) or
                  ((n.resultdef.typ=arraydef) and
                   is_managed_type(tarraydef(n.resultdef).elementdef))) then
                begin
                  add_managed_opaque(ctx^);
                  journal(ctx^,n,er_managed_operation,'array-constructor');
                end;
            end;
          assignn:
            begin
              { manual handling: the left designator is a store target, the
                right side is an ordinary read tree.  Managed assignments
                run refcount helpers and may call user operators. }
              if is_managed_type(tbinarynode(n).left.resultdef) then
                begin
                  add_managed_opaque(ctx^);
                  journal(ctx^,n,er_managed_operation,'assign');
                end;
              add_store_target(ctx^,tbinarynode(n).left,true);
              walk_tree(ctx^,tbinarynode(n).right);
              result:=fen_norecurse_false;
            end;
          calln:
            add_call_effect(ctx^,tcallnode(n));
          inlinen:
            add_inline_effect(ctx^,tinlinenode(n));
          asmn:
            begin
              add_everything(ctx^);
              journal(ctx^,n,er_inline_asm,'');
            end;
          forn:
            begin
              { forn never reaches the observe hook (ConvertForLoops runs
                first on both pipeline branches), but it IS alive for the
                model's next consumer: the PLAN gives the existing
                induction/strength pass a model gate, and that pass runs
                BEFORE ConvertForLoops.  The loop variable is written by the
                loop machinery (the counter read comes from the generic
                children walk). }
              add_store_target(ctx^,tloopnode(n).left,true);
              if checked_switches(n) then
                begin
                  include(ctx^.e^.ieffects,ie_trap);
                  journal(ctx^,n,er_may_trap,'');
                end;
            end;
          exitn:
            begin
              if assigned(current_procinfo) and
                 assigned(current_procinfo.procdef.funcretsym) then
                classify_var_sym(ctx^,n,
                  tabstractvarsym(current_procinfo.procdef.funcretsym),true);
            end;
          raisen:
            begin
              include(ctx^.e^.ieffects,ie_trap);
              journal(ctx^,n,er_may_trap,'raise');
            end;
          onn:
            begin
              { entering the handler writes the exception variable }
              if assigned(tonnode(n).excepTSymtable) then
                for i:=0 to tonnode(n).excepTSymtable.SymList.Count-1 do
                  begin
                    sym:=tsym(tonnode(n).excepTSymtable.SymList[i]);
                    if sym is tabstractvarsym then
                      classify_var_sym(ctx^,n,tabstractvarsym(sym),true);
                  end;
            end;
          else
            begin
              { conservative closure: any node the model does not know reads
                and writes everything and carries every instruction effect }
              add_everything(ctx^);
              journal(ctx^,n,er_unknown_node,nodetype2str[n.nodetype]);
            end;
        end;
      end;


    procedure walk_tree(var ctx : teffectwalk; n : tnode);
      begin
        if assigned(n) then
          foreachnodestatic(pm_postprocess,n,@effect_walk_node,@ctx);
      end;


{*****************************************************************************
                                Model queries
*****************************************************************************}

    procedure tree_effect(n : tnode; var e : teffect);
      var
        ctx : teffectwalk;
      begin
        fillchar(ctx,sizeof(ctx),0);
        ctx.e:=@e;
        ctx.observing:=false;
        walk_tree(ctx,n);
      end;


{*****************************************************************************
                                Observe mode
*****************************************************************************}

    function classes_str(c : taliasclasses; unbounded : boolean) : string;
      begin
        result:='';
        if ac_local in c then
          begin
            result:=result+'L';
            if unbounded then
              result:=result+'!';
          end;
        if ac_escaped in c then
          result:=result+'E';
        if ac_heapelem in c then
          result:=result+'H';
        if ac_global in c then
          result:=result+'G';
        if ac_threadvar in c then
          result:=result+'T';
        if ac_parentframe in c then
          result:=result+'P';
        if result='' then
          result:='-';
      end;


    function ieffects_str(ie : tinsteffects) : string;
      begin
        result:='';
        if ie_sync in ie then
          result:=result+'s';
        if ie_managed in ie then
          result:=result+'m';
        if ie_trap in ie then
          result:=result+'t';
        if result='' then
          result:='-';
      end;


    { sorted comma-joined real names of the exact-local symbols; '-' when
      empty.  Sorted so the machine wire is deterministic. }
    function symlist_names(list : TFPList) : ansistring;
      var
        i,j : longint;
        names : array of ansistring;
        t : ansistring;
      begin
        if not assigned(list) or (list.Count=0) then
          exit('-');
        setlength(names,list.Count);
        for i:=0 to list.Count-1 do
          names[i]:=tsym(list[i]).realname;
        for i:=1 to high(names) do
          for j:=high(names) downto i do
            if names[j]<names[j-1] then
              begin
                t:=names[j];
                names[j]:=names[j-1];
                names[j-1]:=t;
              end;
        result:=names[0];
        for i:=1 to high(names) do
          result:=result+','+names[i];
      end;


    function symlists_equal(a,b : TFPList) : boolean;
      var
        i : longint;
      begin
        result:=false;
        if (assigned(a) and (a.Count>0))<>(assigned(b) and (b.Count>0)) then
          exit;
        if assigned(a) and assigned(b) then
          begin
            if a.Count<>b.Count then
              exit;
            for i:=0 to a.Count-1 do
              if b.IndexOf(a[i])<0 then
                exit;
          end;
        result:=true;
      end;


    function okstr(b : boolean) : string;
      begin
        if b then
          result:='ok'
        else
          result:='BROKEN';
      end;


    function effects_equal(const a,b : teffect) : boolean;
      begin
        result:=(a.rclasses=b.rclasses) and
          (a.wclasses=b.wclasses) and
          (a.ieffects=b.ieffects) and
          (a.runbounded=b.runbounded) and
          (a.wunbounded=b.wunbounded) and
          (a.hastemps=b.hastemps) and
          symlists_equal(a.rsyms,b.rsyms) and
          symlists_equal(a.wsyms,b.wsyms);
      end;


    procedure effect_observe_procedure(n : tnode; pd : tprocdef);
      var
        ctx : teffectwalk;
        e,q,u : teffect;
        r : teffectreason;
        s,reasons : ansistring;
        procname : ansistring;
        queriesok,unionok,selfconflict : boolean;
      begin
        effect_init(e);
        fillchar(ctx,sizeof(ctx),0);
        ctx.e:=@e;
        ctx.observing:=true;
        walk_tree(ctx,n);
        if assigned(pd.procsym) then
          procname:=pd.procsym.realname
        else
          procname:=pd.mangledname;
        reasons:='';
        for r:=succ(er_none) to high(teffectreason) do
          if ctx.counters[r]>0 then
            begin
              if reasons<>'' then
                reasons:=reasons+',';
              reasons:=reasons+effect_reason_str[r]+':'+tostr(ctx.counters[r]);
            end;
        if reasons='' then
          reasons:='-';
        s:='proc='+procname+
           ' mid='+pd.mangledname+
           ' nodes='+tostr(ctx.nodes)+
           ' r='+classes_str(e.rclasses,e.runbounded)+
           ' w='+classes_str(e.wclasses,e.wunbounded)+
           ' ie='+ieffects_str(e.ieffects)+
           ' temps='+tostr(ord(e.hastemps))+
           ' reasons='+reasons;
        CGMessagePos1(pd.fileinfo,cg_d_effect_observe_summary,s);
        { the algebra line exercises the PUBLIC queries of the model - the
          exact facts a future consumer will decide by, which the class
          letters of the summary cannot carry (review F-03): tree_effect
          must reproduce the observed effect, effect_union must be
          idempotent from the empty effect, and effects_conflict must see
          the routine conflict with itself whenever it writes, carries a
          barrier or temps.  The gate asserts these fields per routine. }
        effect_init(q);
        tree_effect(n,q);
        queriesok:=effects_equal(q,e);
        effect_init(u);
        effect_union(u,q);
        effect_union(u,q);
        unionok:=effects_equal(u,q);
        selfconflict:=effects_conflict(q,q);
        s:='proc='+procname+
           ' mid='+pd.mangledname+
           ' rl='+symlist_names(e.rsyms)+
           ' wl='+symlist_names(e.wsyms)+
           ' sc='+tostr(ord(selfconflict))+
           ' q='+okstr(queriesok)+
           ' un='+okstr(unionok);
        CGMessagePos1(pd.fileinfo,cg_d_effect_observe_algebra,s);
        effect_done(u);
        effect_done(q);
        effect_done(e);
      end;

end.
