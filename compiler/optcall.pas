{
    Replaces calls by inline code

    Copyright (c) 1998-2026 by Florian Klaempfl and others

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

unit optcall;

{$i fpcdefs.inc}

{ $define EXTDEBUG_INLINE}

  interface

    uses
      node;

    procedure do_optinline(var rootnode : tnode;out changed: boolean);

  implementation

    uses
      cutils,cclasses,
      globtype,
      verbose,globals,
      defutil,defcmp,
      symconst,symtype,symdef,symsym,
      parabase,paramgr,
      procinfo,
      nutils,
      fmodule,
      pass_1,
      compinnr,
      symtable,
      nbas,ncal,ncnv,nflw,ninl,nld,nmem,
      optloop;

    { this procedure removes the user code flag because it prevents optimizations }
    function removeusercodeflag(var n : tnode; arg : pointer) : foreachnoderesult;
      begin
        result:=fen_false;
        if nf_usercode_entry in n.flags then
          begin
            exclude(n.flags,nf_usercode_entry);
            result:=fen_norecurse_true;
          end;
      end;


    function setinlinelevel(var n:tnode; arg:pointer):foreachnoderesult;
      begin
        if n.nodetype=calln then
          tcallnode(n).inlinelevel:=PtrUInt(arg);
        result:=fen_false;
      end;


    { reference symbols that are imported from another unit }
    function importglobalsyms(var n:tnode; arg:pointer):foreachnoderesult;
      var
        sym : tsym;
      begin
        result:=fen_false;
        if n.nodetype=loadn then
          begin
            sym:=tloadnode(n).symtableentry;
            if sym.typ=staticvarsym then
              begin
                if FindUnitSymtable(tloadnode(n).symtable).moduleid<>current_module.moduleid then
                  current_module.addimportedsym(sym);
              end
            else if (sym.typ=constsym) and (tconstsym(sym).consttyp in [constwresourcestring,constresourcestring]) then
              begin
                if tloadnode(n).symtableentry.owner.moduleid<>current_module.moduleid then
                  current_module.addimportedsym(sym);
              end;
          end
        else if (n.nodetype=calln) then
          begin
            if (assigned(tcallnode(n).procdefinition)) and
               (tcallnode(n).procdefinition.typ=procdef) and
               (findunitsymtable(tcallnode(n).procdefinition.owner).moduleid<>current_module.moduleid) then
              current_module.addimportedsym(tprocdef(tcallnode(n).procdefinition).procsym);
          end;
      end;


    function redoalinaparams(var n: tnode; arg: pointer): foreachnoderesult;
      begin
        result:=fen_false;
        if n.nodetype=calln then
          begin
            { re-init varargs paraloc that may have been invalidated by inlining }
            if assigned(tcallnode(n).varargsparas) then
              paramanager.create_varargs_paraloc_info(tcallnode(n).procdefinition,callerside,tcallnode(n).varargsparas);
            tcallnode(n).order_parameters;
          end;
      end;


    function clear_funcret_borrow(var n: tnode; arg: pointer): foreachnoderesult;
      begin
        result:=fen_false;
        if n.nodetype=calln then
          begin
            tcallnode(n).funcret_borrow:=false;
            tcallnode(n).funcret_byref:=false;
          end;
      end;


    { The call whose value n is, reached through parts that run no code and
      keep no pointer into the value: a conversion the compiler made or one of
      a value that is not managed, an element or a character selected by an
      index without calls or assignments, a field. }
    function projected_call(n: tnode): tcallnode;
      var
        bottom: tnode;
      begin
        result:=nil;
        bottom:=n;
        while bottom.nodetype in [typeconvn,vecn,subscriptn] do
          bottom:=tunarynode(bottom).left;
        if bottom.nodetype<>calln then
          exit;
        while n<>bottom do
          begin
            case n.nodetype of
              typeconvn:
                if not(nf_internal in n.flags) and
                   is_managed_type(ttypeconvnode(n).left.resultdef) then
                  exit;
              vecn:
                if might_have_sideeffects(tvecnode(n).right,[]) then
                  exit;
              else
                ;
            end;
            n:=tunarynode(n).left;
          end;
        result:=tcallnode(bottom);
      end;


    { The helpers of the string types (compare, assign, concatenate, convert,
      Copy) and the dynamic-array assignment, which takes its reference to the
      source before it releases anything, run no code of the program. }
    function helper_reads_only(call: tcallnode): boolean;
      var
        helper: string;
      begin
        result:=false;
        if not assigned(call.procdefinition) or
           (call.procdefinition.typ<>procdef) or
           not(po_compilerproc in call.procdefinition.procoptions) then
          exit;
        helper:=upper(tprocdef(call.procdefinition).procsym.name);
        result:=(helper='FPC_DYNARRAY_ASSIGN') or
                (copy(helper,1,12)='FPC_ANSISTR_') or
                (copy(helper,1,12)='FPC_WIDESTR_') or
                (copy(helper,1,15)='FPC_UNICODESTR_');
      end;


    { An inlined call may hand its source to the consumer of its value instead
      of a reference of its own (tcallnode.funcret_borrow) when the consumer
      finishes reading the value before any code can run that could change the
      source: an operator, Length/High, the step of Inc/Dec, a store without a
      helper and a helper that only reads, while the other operands run no code
      either.  Everything else - a call of a routine above all, a pointer to
      the value, an operand that calls or assigns - keeps the reference. }
    function mark_funcret_borrow(var n: tnode; arg: pointer): foreachnoderesult;

      { Follow storage contained in the returned value, stopping at an
        implicit dereference: the address of an object's field or a dynamic
        array element is not the address of the returned pointer itself. }
      procedure use_address(value: tnode);
        begin
          while assigned(value) do
            begin
              case value.nodetype of
                calln:
                  begin
                    tcallnode(value).funcret_byref:=true;
                    exit;
                  end;
                typeconvn:
                  if ttypeconvnode(value).convtype<>tc_equal then
                    exit;
                subscriptn:
                  if is_implicit_pointer_object_type(tsubscriptnode(value).left.resultdef) then
                    exit;
                vecn:
                  if not(((tvecnode(value).left.resultdef.typ=arraydef) and
                           not is_special_array(tvecnode(value).left.resultdef)) or
                          is_shortstring(tvecnode(value).left.resultdef)) then
                    exit;
                else
                  exit;
              end;
              value:=tunarynode(value).left;
            end;
        end;

      procedure borrow(value, other: tnode);
        var
          call: tcallnode;
        begin
          call:=projected_call(value);
          if assigned(call) and
             (not assigned(other) or not might_have_sideeffects(other,[])) then
            call.funcret_borrow:=true;
        end;

      var
        call: tcallnode;
        para,
        other: tcallparanode;
        readonlyhelper: boolean;
      begin
        result:=fen_false;
        case n.nodetype of
          addrn:
            use_address(taddrnode(n).left);
          inlinen:
            case tinlinenode(n).inlinenumber of
              in_length_x,
              in_high_x:
                borrow(tinlinenode(n).left,nil);
              in_inc_x,
              in_dec_x:
                begin
                  para:=tcallparanode(tinlinenode(n).left);
                  if assigned(para.right) then
                    borrow(tcallparanode(para.right).left,para.left);
                end;
              else
                ;
            end;
          assignn:
            if not is_managed_type(tassignmentnode(n).left.resultdef) and
               (tassignmentnode(n).left.resultdef.typ<>pointerdef) then
              borrow(tassignmentnode(n).right,tassignmentnode(n).left);
          calln:
            begin
              readonlyhelper:=helper_reads_only(tcallnode(n));
              para:=tcallparanode(tcallnode(n).left);
              while assigned(para) do
                begin
                  if paramanager.push_addr_param_for_proc(para.parasym.varspez,para.parasym.vardef,
                      tcallnode(n).procdefinition) then
                    use_address(para.left);
                  if readonlyhelper then
                    begin
                      call:=projected_call(para.left);
                      other:=tcallparanode(tcallnode(n).left);
                      while assigned(call) and assigned(other) do
                        begin
                          if (other<>para) and
                             might_have_sideeffects(other.left,[]) then
                            call:=nil;
                          other:=tcallparanode(other.right);
                        end;
                      if assigned(call) then
                        call.funcret_borrow:=true;
                    end;
                  para:=tcallparanode(para.right);
                end;
            end;
          else
            if n.inheritsfrom(tbinopnode) and
               (n.resultdef.typ<>pointerdef) then
              begin
                borrow(tbinarynode(n).left,tbinarynode(n).right);
                borrow(tbinarynode(n).right,tbinarynode(n).left);
              end;
        end;
      end;


    function doinline(var _n: tnode; arg: pointer): foreachnoderesult;
      var
        n,
        body,
        frameblock : tnode;
        para : tcallparanode;
        inlineblock,
        constructionblock,
        inlinecleanupblock : tblocknode;
        framestatement,
        outerstatement : tstatementnode;
        callnode: tcallnode;
      begin
        result:=fen_false;
        if not(_n.nodetype=calln) or not(po_inline in tcallnode(_n).procdefinition.procoptions) then
          exit;
        callnode:=tcallnode(_n);

        { first_call_pass freezes the complete semantic inline decision after
          hidden parameters/result storage exist and before call ABI layout.
          Re-evaluating it here against already transformed actuals can turn
          an inline into a real call after its outgoing area was omitted. }
        if not(cnf_do_inline in callnode.callnodeflags) then
          begin
            if not(po_compilerproc in callnode.procdefinition.procoptions) then
              Message1(cg_n_no_inline,tprocdef(callnode.procdefinition).customprocname([pno_proctypeoption, pno_paranames,pno_ownername, pno_noclassmarker, pno_prettynames]));
            exit;
          end;

        if not(assigned(tprocdef(callnode.procdefinition).inlininginfo) and
          assigned(tprocdef(callnode.procdefinition).inlininginfo^.code)) then
          internalerror(200412021);

        callnode.inlinelocals:=TFPObjectList.create(true);

        { inherit flags }
        current_procinfo.flags:=current_procinfo.flags+
          ((callnode.procdefinition as tprocdef).inlininginfo^.flags*inherited_inlining_flags);

        { Create new code block for inlining }
        inlineblock:=internalstatements(outerstatement);
        { make sure that valid_for_assign() returns false for this block
          (otherwise assigning values to the block will result in assigning
           values to the inlined function's result) }
        include(inlineblock.flags,nf_no_lvalue);
        inlinecleanupblock:=internalstatements(callnode.inlinecleanupstatement);

        if assigned(callnode.callinitblock) then
          addstatement(outerstatement,callnode.callinitblock.getcopy);

        { replace complex parameters with temps. Temp creations and flag
          zeroing land in inlineinitstatement (outside the frame), the
          construction phase - Initialize, guard arming, the user's Assigns -
          in inlineconstructionstatement (inside it) }
        callnode.inlineinitstatement:=outerstatement;
        constructionblock:=internalstatements(callnode.inlineconstructionstatement);
        callnode.createinlineparas;
        outerstatement:=callnode.inlineinitstatement;

        { create a copy of the body and replace parameter loads with the parameter values }
        body:=tprocdef(callnode.procdefinition).inlininginfo^.code.getcopy;
        foreachnodestatic(pm_postprocess,body,@ removeusercodeflag,nil);
        foreachnodestatic(pm_postprocess,body,@importglobalsyms,nil);
        foreachnodestatic(pm_postprocess,body,@setinlinelevel,pointer(callnode.inlinelevel+1));
        foreachnode(pm_preprocess,body,@callnode.replaceparaload,@callnode.fileinfo);

        { The frame covers the construction phase AND the body: copies and
          managed locals die at the callee's return point and during unwind,
          including an unwind out of a later Initialize/Assign of the
          construction itself (C-003) - the flag-gated finalizers skip
          whatever was never built. The temp slots are released after the
          frame, in the cleanup block. }
        frameblock:=internalstatements(framestatement);
        addstatement(framestatement,constructionblock);
        addstatement(framestatement,body);
        if assigned(callnode.inlinemanagedcleanupblock) then
          begin
            frameblock:=ctryfinallynode.create_implicit(frameblock,callnode.inlinemanagedcleanupblock);
            callnode.inlinemanagedcleanupblock:=nil;
            { the frame costs the caller its DFA passes - the same price a
              hand-written try..finally pays; when the post-inline
              simplifier proves the body non-throwing and strips the frame,
              TransformNodeTree clears the flag again and DFA returns }
            include(current_procinfo.flags,pi_uses_exceptions);
          end;

        { Concat the frame and finalization parts }
        addstatement(outerstatement,frameblock);
        addstatement(outerstatement,inlinecleanupblock);
        inlinecleanupblock:=nil;
        callnode.inlineinitstatement:=outerstatement;

        if assigned(callnode.callcleanupblock) then
          addstatement(callnode.inlineinitstatement,callnode.callcleanupblock.getcopy);

        { the last statement of the new inline block must return the
          location and type of the function result.
          This is not needed when the result is not used, also the tempnode is then
          already destroyed  by a tempdelete in the callcleanupblock tree }
        if not is_void(callnode.resultdef) and
           (cnf_return_value_used in callnode.callnodeflags) then
          begin
            if assigned(callnode.funcretnode) then
              addstatement(callnode.inlineinitstatement,callnode.funcretnode.getcopy)
            else
              begin
                para:=tcallparanode(callnode.left);
                while assigned(para) do
                  begin
                    if (vo_is_hidden_para in para.parasym.varoptions) and
                       (vo_is_funcret in para.parasym.varoptions) then
                      begin
                        addstatement(callnode.inlineinitstatement,para.left.getcopy);
                        break;
                      end;
                    para:=tcallparanode(para.right);
                  end;
              end;
          end;

        typecheckpass(tnode(inlineblock));
        doinlinesimplify(tnode(inlineblock));
        firstpass(tnode(inlineblock));
        _n:=inlineblock;

        { if the function result is used then verify that the blocknode
          returns the same result type as the original callnode }
        if (cnf_return_value_used in callnode.callnodeflags) and
           not(equal_defs(_n.resultdef,callnode.resultdef)) then
          internalerror(200709171);

        { free the temps for the locals }
        callnode.inlinelocals.free;
        callnode.inlinelocals:=nil;
        callnode.inlineinitstatement:=nil;
        callnode.inlineconstructionstatement:=nil;
        callnode.inlinecleanupstatement:=nil;

        n:=callnode.optimize_funcret_assignment(inlineblock);
        if assigned(n) then
          begin
            { the optimization edits the block in place; the returned node is
              either that same block or a replacement created by the renewed
              first pass, which then already freed the edited block }
            inlineblock:=nil;
            _n:=n;
          end;

        PBoolean(arg)^:=true;

        { the calls of the body and of the actuals moved into it meet their
          consumers only now; the traversal inlines them next }
        foreachnodestatic(pm_postprocess,_n,@mark_funcret_borrow,nil);

{$ifdef EXTDEBUG_INLINE}
        writeln;
        writeln('**************************************************************************************************************');
        writeln('************************** Inlined ',tprocdef(callnode.procdefinition).mangledname,'**************************');
        writeln('**************************************************************************************************************');
{$endif EXTDEBUG_INLINE}
      end;


    procedure do_optinline(var rootnode: tnode;out changed: boolean);
      begin
        changed:=false;
{$ifdef EXTDEBUG_INLINE}
        writeln('************************ Tree before inlining ******************************');
        printnode(rootnode);
        writeln('****************************************************************************');
{$endif EXTDEBUG_INLINE}
        { The borrow is a fact of the use, not of the call: record it on the
          call at the point where the inliner will consume it; a context-free
          result node must not carry this permission. }
        foreachnodestatic(pm_postprocess,rootnode,@clear_funcret_borrow,nil);
        foreachnodestatic(pm_postprocess,rootnode,@mark_funcret_borrow,nil);
        foreachnodestatic(pm_postprocess, rootnode, @doinline, @changed);
        if changed then
          begin
            doinlinesimplify(rootnode);
            { after inlining, call nodes in the tree may have parameters
              whose subtrees now contain additional calls (e.g. fpc_shortstr_sint
              from an inlined str() call). The parent call nodes need their
              parameter analysis redone to recalculate parameter ordering and
              stack tainting info, otherwise parameters may be evaluated in the
              wrong order corrupting already pushed stack parameters }
            foreachnodestatic(pm_postprocess,rootnode,@redoalinaparams,nil);
{$ifdef EXTDEBUG_INLINE}
            writeln('************************ Tree after inlining ******************************');
            printnode(rootnode);
            writeln('****************************************************************************');
{$endif EXTDEBUG_INLINE}
          end;
      end;

end.

