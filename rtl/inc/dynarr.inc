{
    This file is part of the Free Pascal run time library.
    Copyright (c) 2000 by Florian Klaempfl
    member of the Free Pascal development team.

    This file implements the helper routines for dyn. Arrays in FPC

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************
}

type
   { don't add new fields, the size is used }
   { to calculate memory requirements       }
   pdynarray = ^tdynarray;
   { removed packed here as
     1) both fields have typically the same size (2, 4 or 8 bytes), if this is not the case, packed
        should be used only for this architecture
     2) the memory blocks are sufficiently well aligned
     3) in particular 64 bit CPUs which require natural alignment suffer from
        the packed as it causes each field access being split in 8 single loads and appropriate shift operations
   }
   tdynarray = { packed } record
      refcount : ptrint;
      high : tdynarrayindex;
   end;

   pdynarraytypedata = ^tdynarraytypedata;
   tdynarraytypedata =
{$ifndef FPC_REQUIRES_PROPER_ALIGNMENT}
   packed
{$endif FPC_REQUIRES_PROPER_ALIGNMENT}
   record
     {$if declared(TRttiDataCommon)}
     common: TRttiDataCommon;
     {$endif declared TRttiDataCommon}
     case TTypeKind of
       tkArray: (
         elSize : SizeUInt;
         elType2 : PPointer;
         varType : Longint;
         elType : PPointer;
       );
       { include for proper alignment }
       tkInt64: (
         dummy : Int64
       );
   end;

procedure fpc_dynarray_rangecheck(p : pointer;i : tdynarrayindex);[Public,Alias:'FPC_DYNARRAY_RANGECHECK']; compilerproc;
  begin
     if not(assigned(p)) or (i<0) or (i>pdynarray(p-sizeof(tdynarray))^.high) then
       HandleErrorAddrFrameInd(201,get_pc_addr,get_frame);
  end;


function fpc_dynarray_length(p : pointer) : tdynarrayindex;[Public,Alias:'FPC_DYNARRAY_LENGTH']; compilerproc;
  begin
     if assigned(p) then
       fpc_dynarray_length:=pdynarray(p-sizeof(tdynarray))^.high+1
     else
       fpc_dynarray_length:=0;
  end;


function fpc_dynarray_high(p : pointer) : tdynarrayindex;[Public,Alias:'FPC_DYNARRAY_HIGH']; compilerproc;
  begin
     if assigned(p) then
       fpc_dynarray_high:=pdynarray(p-sizeof(tdynarray))^.high
     else
       fpc_dynarray_high:=-1;
  end;


procedure fpc_dynarray_clear(var p : pointer;ti : pointer); [Public,Alias:'FPC_DYNARRAY_CLEAR']; compilerproc;
  var
    pv : pdynarray;
  begin
    pv:=p;
    if not assigned(pv) then
      exit;
    p:=nil;
    if (pv[-1].refcount=1) or (pv[-1].refcount>0) and
{$ifdef VER3_2}
      declocked(pv[-1].refcount)
{$else}
      (AtomicDecrement(pv[-1].refcount)=0)
{$endif}
      then
      begin
        ti:=pdynarraytypedata(aligntoqword(ti+2+PByte(ti)[1]))^.elType;
        if assigned(ti) then
          int_finalizearray(pv,PPointer(ti)^,pv[-1].high+1);
        freemem(pv-1);
      end;
  end;

{ alias for internal use }
Procedure fpc_dynarray_clear (var p : pointer;ti : pointer);[external name 'FPC_DYNARRAY_CLEAR'];


procedure fpc_dynarray_incr_ref(p : pointer);[Public,Alias:'FPC_DYNARRAY_INCR_REF']; compilerproc;
  begin
     if assigned(p) and (pdynarray(p)[-1].refcount>0) then
{$ifdef VER3_2}
       inclocked(pdynarray(p)[-1].refcount);
{$else}
       AtomicIncrement(pdynarray(p)[-1].refcount);
{$endif}
  end;

{ provide local access to dynarr_decr_ref for dynarr_setlength }
procedure fpc_dynarray_incr_ref(p : pointer); [external name 'FPC_DYNARRAY_INCR_REF'];


procedure fpc_dynarray_assign(var dest: Pointer; src: Pointer; ti: pointer);[public,alias:'FPC_DYNARRAY_ASSIGN']; compilerproc;
  var
    pv : pdynarray;
  begin
    { flattened incr_ref + clear: an assignment is one call deep instead of
      relaying through two helper frames on every managed-array store }
    if assigned(src) and (pdynarray(src)[-1].refcount>0) then
{$ifdef VER3_2}
      inclocked(pdynarray(src)[-1].refcount);
{$else}
      AtomicIncrement(pdynarray(src)[-1].refcount);
{$endif}
    pv:=dest;
    dest:=src;
    if assigned(pv) then
      if (pv[-1].refcount=1) or (pv[-1].refcount>0) and
{$ifdef VER3_2}
        declocked(pv[-1].refcount)
{$else}
        (AtomicDecrement(pv[-1].refcount)=0)
{$endif}
        then
        begin
          ti:=pdynarraytypedata(aligntoqword(ti+2+PByte(ti)[1]))^.elType;
          if assigned(ti) then
            int_finalizearray(pv,PPointer(ti)^,pv[-1].high+1);
          freemem(pv-1);
        end;
  end;

procedure fpc_dynarray_assign(var dest: Pointer; src: Pointer; ti: pointer);[external name 'FPC_DYNARRAY_ASSIGN'];

function dynarray_has_custom_operation(typeinfo : pointer;
  operation : TRTTIRecOpType;out elementsize : sizeint) : boolean; inline;
  begin
    result:=assigned(typeinfo) and
      (PTypeKind(typeinfo)^ in [tkRecord,tkObject,tkArray]) and
      RTTIManagementAndSize(typeinfo,operation,elementsize,true);
  end;

function dynarray_copy_complex_may_raise(typeinfo : pointer) : boolean; forward;
function dynarray_copy_element(source,dest,typeinfo : pointer) : sizeint; forward;
function SkipTrailingNils(data : PPointer;count : SizeInt) : SizeInt; forward;

{ Keep the ordinary scalar and reference-counted string paths independent of
  the recursive record walk.  Only acquiring these built-in types can raise. }
function dynarray_copy_may_raise(typeinfo : pointer) : boolean; inline;
  begin
    result:=assigned(typeinfo) and (PTypeKind(typeinfo)^ in [tkRecord,tkObject,tkArray
{$ifdef FPC_HAS_FEATURE_CLASSES}
      ,tkInterface
{$endif}
{$ifdef FPC_HAS_FEATURE_VARIANTS}
      ,tkVariant
{$endif}
{$if defined(FPC_HAS_FEATURE_WIDESTRINGS) and not defined(FPC_WIDESTRING_EQUAL_UNICODESTRING)}
      ,tkWString
{$endif}
      ]) and (not (PTypeKind(typeinfo)^ in [tkRecord,tkObject,tkArray]) or
        dynarray_copy_complex_may_raise(typeinfo));
  end;

{ Copy-construct values into zeroed, unpublished storage.  Copy construction
  is distinct from default construction: Delphi's managed-record Assign is
  invoked directly and Initialize must not run.  Mark the current zeroed slot
  live before entering user code, because a raising Assign may already have
  acquired resources; rollback then finalizes exactly the attempted prefix,
  never untouched tail slots. }
procedure dynarray_copy_custom(source,dest,typeinfo : pointer;
  count,elementsize : sizeint;var constructed : sizeint); inline;
  var
    i : sizeint;
  begin
    for i:=0 to count-1 do
      begin
        inc(constructed);
        int_Copy(source+i*elementsize,dest+i*elementsize,typeinfo);
      end;
  end;

{$ifdef FPC_HAS_FEATURE_CLASSES}
procedure dynarray_acquire_interfaces(data : PPointer;var constructed : sizeint);
  var
    i,count : sizeint;
    intf : pointer;
  begin
    count:=SkipTrailingNils(data,constructed);
    if count=0 then
      exit;
    try
      for i:=0 to count-1 do
        begin
          intf:=data[i];
          if assigned(intf) then
            IUnknown(intf)._AddRef;
        end;
    except
      constructed:=i;
      raise;
    end;
  end;
{$endif}

procedure dynarray_finish_copy(data,typeinfo : pointer;count : sizeint;var constructed : sizeint); inline;
  begin
{$ifdef FPC_HAS_FEATURE_CLASSES}
    if PTypeKind(typeinfo)^=tkInterface then
      begin
        constructed:=count;
        dynarray_acquire_interfaces(data,constructed);
      end;
{$endif}
  end;

procedure dynarray_copy_elements(source,dest,typeinfo : pointer;
  count,elementsize : sizeint;var constructed : sizeint);
  var
    i : sizeint;
  begin
    { Only a callback which can leave a partial value needs zeroed storage. }
    fillchar(dest^,count*elementsize,0);
    if not (PTypeKind(typeinfo)^ in [tkRecord,tkObject,tkArray]) then
      begin
        dynarray_copy_custom(source,dest,typeinfo,count,elementsize,constructed);
        exit;
      end;
    for i:=0 to count-1 do
      begin
        dynarray_copy_element(source+i*elementsize,dest+i*elementsize,typeinfo);
        inc(constructed);
      end;
  end;

procedure dynarray_copy_managed(source,dest,typeinfo : pointer;
  count,elementsize : sizeint;var constructed : sizeint); inline;
  begin
{$ifdef FPC_HAS_FEATURE_CLASSES}
    if PTypeKind(typeinfo)^=tkInterface then
      { Assemble pointers in bulk; finish_copy acquires them before publication.
        Keep the other types' per-element construction outside this fast path. }
      move(source^,dest^,count*elementsize)
    else
{$endif}
      dynarray_copy_elements(source,dest,typeinfo,count,elementsize,constructed);
  end;

procedure dynarray_discard_custom(header : pdynarray;typeinfo : pointer;
  constructed : sizeint); inline;
  begin
    try
      if constructed>0 then
        int_FinalizeArray(header+1,typeinfo,constructed);
    finally
      freemem(header);
    end;
  end;

{ provide local access to dynarr_setlength }
procedure int_dynarray_setlength(var p : pointer;pti : pointer;
  dimcount : sizeint;dims : pdynarrayindex);[external name 'FPC_DYNARR_SETLENGTH'];
procedure int_dynarray_setlength_record(var p : pointer;pti : pointer;
  dimcount : sizeint;dims : pdynarrayindex);[external name 'FPC_DYNARR_SETLENGTH_RECORD'];

{ SetLength for records, objects and static arrays: the element types that can
  have a custom Initialize or Copy operator, that is user code which may raise
  in the middle of the work.  The steps are transactional for that reason.
  The compiler calls this routine directly when it sees such an element type
  (dynarray_setlength_procname in ninl.pas); fpc_dynarray_setlength below sends
  the callers that only have RTTI here.  It is correct for every element type. }
procedure fpc_dynarray_setlength_record(var p : pointer;pti : pointer;
  dimcount : sizeint;dims : pdynarrayindex);[Public,Alias:'FPC_DYNARR_SETLENGTH_RECORD']; compilerproc;

  var
     i : tdynarrayindex;
     movelen,size,_size,elesize,oldlen,newlen,constructed : sizeint;
     { contains the "fixed" pointers where the refcount }
     { and high are at positive offsets                 }
     realp,newp : pdynarray;
     ti,eletypemngd,olddata,newdata : pointer;
     customcopy,custominitialize,freshcarrier : boolean;

  begin
     newlen:=dims[0];
     { negative or zero length? }
     if newlen<=0 then
       begin
         { negative length is not allowed }
         if newlen<0 then
           HandleErrorAddrFrameInd(201,get_pc_addr,get_frame);
         { if the new dimension is 0, we've to release all data }
         fpc_dynarray_clear(p,pti);
         exit;
       end;

     { skip kind and name }
     ti:=aligntoqword(Pointer(pti)+2+PByte(pti)[1]);

     elesize:=pdynarraytypedata(ti)^.elSize;
     { only set if type needs finalization }
     eletypemngd:=pdynarraytypedata(ti)^.elType;
     if assigned(eletypemngd) then
       eletypemngd:=PPointer(eletypemngd)^;

     { determine new memory size, throw a runtime error on overflow }
{$push} {$q+,r+}
     size:=elesize*newlen+sizeof(tdynarray);
{$pop}

     olddata:=p;
     if assigned(p) then
       oldlen:=pdynarray(p-sizeof(tdynarray))^.high+1
     else
       oldlen:=0;
     customcopy:=false;
     if assigned(olddata) then
       if pdynarray(olddata-sizeof(tdynarray))^.refcount<>1 then
         customcopy:=dynarray_copy_may_raise(eletypemngd);
     custominitialize:=(newlen>oldlen) and
       dynarray_has_custom_operation(eletypemngd,rotInitialize,_size);

     if assigned(p) then
       begin
          if pdynarray(p-sizeof(tdynarray))^.refcount<>1 then
            begin
               freshcarrier:=true;
               newp:=getmem(size);
               newdata:=newp+1;
               { make an unique copy }
               movelen:=oldlen;
               if newlen<movelen then
                 movelen:=newlen;
               if customcopy then
                 begin
                   constructed:=0;
                   try
                     dynarray_copy_managed(p,newdata,eletypemngd,
                       movelen,elesize,constructed);
                     dynarray_finish_copy(newdata,eletypemngd,movelen,constructed);
                   except
                     dynarray_discard_custom(newp,eletypemngd,constructed);
                     raise;
                   end;
                 end
               else
                 begin
                   move(p^,newdata^,elesize*movelen);
                   if assigned(eletypemngd) then
                     int_AddRefArray(newdata,eletypemngd,movelen);
                 end;
            end
          else
            begin
               freshcarrier:=false;
               movelen:=oldlen;
               if newlen<movelen then
                 movelen:=newlen;
               { Finalize if shrinking. }
               if assigned(eletypemngd) and (newlen<oldlen) then
                 int_finalizearray(p+elesize*newlen,eletypemngd,oldlen-newlen);
               realp:=p-sizeof(tdynarray);
               newp:=reallocmem(realp,size);
               { ReallocMem may move the carrier.  Publish that address before
                 a custom Initialize can raise; the old logical length in the
                 header keeps the caller's array valid on failure. }
               p:=newp+1;
            end;
       end
     else
       begin
          movelen:=0;
          freshcarrier:=true;
          newp:=AllocMem(size);
          newdata:=newp+1;
       end;
     if newlen>oldlen then
       begin
          { Initialize new items. }
          if oldlen<>0 then { Skip if AllocMem was used. CAREFUL: Assigned(p) won’t work because of fpc_dynarray_clear above. }
            fillchar((pointer(newp)+sizeof(tdynarray)+elesize*oldlen)^,(newlen-oldlen)*elesize,0);
          if custominitialize then
            try
              int_InitializeArray(pointer(newp)+sizeof(tdynarray)+elesize*oldlen,
                eletypemngd,newlen-oldlen);
            except
              if freshcarrier then
                begin
                  try
                    if movelen>0 then
                      int_FinalizeArray(newdata,eletypemngd,movelen);
                  finally
                    freemem(newp);
                  end;
                end;
              raise;
            end;
       end;
     if freshcarrier then
       begin
         { p still owns olddata here: construction above cannot strand it. }
         if assigned(olddata) then
           fpc_dynarray_clear(p,pti);
         p:=newdata;
       end;
     newp^.refcount:=1;
     newp^.high:=newlen-1;
     { handle nested arrays }
     if dimcount>1 then
       begin
          for i:=0 to newlen-1 do
            int_dynarray_setlength(pointer((pointer(newp)+sizeof(tdynarray)+i*elesize)^),
              pdynarraytypedata(ti)^.elType2^,dimcount-1,@dims[1]);
       end;
  end;


procedure fpc_dynarray_setlength(var p : pointer;pti : pointer;
  dimcount : sizeint;dims : pdynarrayindex);[Public,Alias:'FPC_DYNARR_SETLENGTH']; compilerproc;

  var
     i : tdynarrayindex;
     movelen,size,elesize,oldlen,newlen : sizeint;
     { contains the "fixed" pointers where the refcount }
     { and high are at positive offsets                 }
     realp,newp : pdynarray;
     ti,eletypemngd : pointer;

  begin
     newlen:=dims[0];
     { negative or zero length? }
     if newlen<=0 then
       begin
         { negative length is not allowed }
         if newlen<0 then
           HandleErrorAddrFrameInd(201,get_pc_addr,get_frame);
         { if the new dimension is 0, we've to release all data }
         fpc_dynarray_clear(p,pti);
         exit;
       end;

     { skip kind and name }
     ti:=aligntoqword(Pointer(pti)+2+PByte(pti)[1]);

     elesize:=pdynarraytypedata(ti)^.elSize;
     { only set if type needs finalization }
     eletypemngd:=pdynarraytypedata(ti)^.elType;
     if assigned(eletypemngd) then
       begin
         eletypemngd:=PPointer(eletypemngd)^;
         { Records, objects and static arrays can have a custom Initialize or
           Copy operator: user code in the middle of the work.  The
           transactional routine exists for that, and they take it.  Every
           other element type runs the straight code below - the code it ran
           before the transactional routine existed - because it is faster
           (Pulse hot-rtl, Ryzen 5800X, families of four RTL placements: a
           fresh array of 16 strings 105.5 -> 95.3 cycles, of 64 Double
           73.2 -> 71.0).  One test of the type kind decides, nothing else is
           looked up here.  Code compiled by this compiler does not come here
           with such an element type: it calls the routine above.

           Shared copies that can enter user code or copy a Windows
           WideString are routed below, inside the existing shared arm.
           Unique shrink keeps its basic guarantee: a raising finalizer can
           leave already finalized slots while the old length remains. }
         if PTypeKind(eletypemngd)^ in [tkRecord,tkObject,tkArray] then
           begin
             int_dynarray_setlength_record(p,pti,dimcount,dims);
             exit;
           end;
       end;

     { determine new memory size, throw a runtime error on overflow }
{$push} {$q+,r+}
     size:=elesize*newlen+sizeof(tdynarray);
{$pop}

     if assigned(p) then
       begin
          oldlen:=pdynarray(p-sizeof(tdynarray))^.high+1;
          if pdynarray(p-sizeof(tdynarray))^.refcount<>1 then
            begin
               if dynarray_copy_may_raise(eletypemngd) then
                 begin
                   int_dynarray_setlength_record(p,pti,dimcount,dims);
                   exit;
                 end;
               newp:=getmem(size);
               { make an unique copy }
               movelen:=oldlen;
               if newlen<movelen then
                 movelen:=newlen;
               move(p^,(pointer(newp)+sizeof(tdynarray))^,elesize*movelen);
               { increment ref. count of managed members }
               if assigned(eletypemngd) then
                 int_AddRefArray(pointer(newp)+sizeof(tdynarray),eletypemngd,movelen);

               { a declock(ref. count) isn't enough here }
               { it could be that the in MT environments }
               { in the mean time the refcount was       }
               { decremented                             }

               { it is, because it doesn't really matter }
               { if the array is now removed             }
               fpc_dynarray_clear(p,pti);
            end
          else
            begin
               { Finalize if shrinking. }
               if assigned(eletypemngd) and (newlen<oldlen) then
                 int_finalizearray(p+elesize*newlen,eletypemngd,oldlen-newlen);
               realp:=p-sizeof(tdynarray);
               newp:=reallocmem(realp,size);
            end;
       end
     else
       begin
          oldlen:=0;
          newp:=AllocMem(size);
       end;
     if newlen>oldlen then
       begin
          { Initialize new items. }
          if oldlen<>0 then { Skip if AllocMem was used. CAREFUL: Assigned(p) won’t work because of fpc_dynarray_clear above. }
            fillchar((pointer(newp)+sizeof(tdynarray)+elesize*oldlen)^,(newlen-oldlen)*elesize,0);
          { zero is the initial value of every element type that comes here }
       end;
     p:=pointer(newp)+sizeof(tdynarray);
     newp^.refcount:=1;
     newp^.high:=newlen-1;
     { handle nested arrays }
     if dimcount>1 then
       begin
          for i:=0 to newlen-1 do
            int_dynarray_setlength(pointer((pointer(newp)+sizeof(tdynarray)+i*elesize)^),
              pdynarraytypedata(ti)^.elType2^,dimcount-1,@dims[1]);
       end;
  end;


{ provide local access to array_to_dynarray_copy }
function int_array_to_dynarray_copy(psrc : pointer;ti : pointer;
    lowidx,count,maxcount:tdynarrayindex;
    elesize : sizeint;
    eletype : pointer
    ) : fpc_stub_dynarray;[external name 'FPC_ARR_TO_DYNARR_COPY'];


{$if defined(VER3_2)}
function fpc_dynarray_copy(psrc : pointer;ti : pointer;
    lowidx,count:tdynarrayindex) : fpc_stub_dynarray;[Public,Alias:'FPC_DYNARR_COPY'];compilerproc;
  var
    realpsrc : pdynarray;
    eletype,tti : pointer;
    elesize : sizeint;
  begin
     fpc_dynarray_clear(pointer(result),ti);
     if psrc=nil then
       exit;
     realpsrc:=pdynarray(psrc-sizeof(tdynarray));

     tti:=aligntoqword(ti+2+PByte(ti)[1]);
     elesize:=pdynarraytypedata(tti)^.elSize;
     { only set if type needs finalization }
     if assigned(pdynarraytypedata(tti)^.elType) then
       eletype:=pdynarraytypedata(tti)^.elType^
     else
       eletype:=nil;

     fpc_array_to_dynarray_copy(psrc,ti,lowidx,count,realpsrc^.high+1,elesize,eletype);
  end;
{$endif VER3_2}

{ copy a custom array (open/dynamic/static) to dynamic array }
function fpc_array_to_dynarray_copy(psrc : pointer;ti : pointer;
    lowidx,count,maxcount:tdynarrayindex;
    elesize : sizeint;
    eletype : pointer
    ) : fpc_stub_dynarray;[Public,Alias:'FPC_ARR_TO_DYNARR_COPY'];compilerproc;
  var
    size,constructed : sizeint;
    olddata,newdata : pointer;
    newheader : pdynarray;
    customcopy : boolean;
  begin
     newdata:=nil;
     if psrc<>nil then
       begin

{$ifndef FPC_DYNARRAYCOPY_FIXED}
         if (lowidx=-1) and (count=-1) then
           begin
             lowidx:=0;
             count:=high(tdynarrayindex);
           end;
{$endif FPC_DYNARRAYCOPY_FIXED}
         if lowidx<0 then
           begin
             { Dynamic-array Copy decreases count for a negative index. }
             if count>0 then
               count:=count+lowidx
             else
               count:=0;
             lowidx:=0;
           end;
         if count>maxcount-lowidx then
           count:=maxcount-lowidx;
         if count>0 then
           begin
             size:=elesize*count;
             customcopy:=dynarray_copy_may_raise(eletype);
             newheader:=getmem(size+sizeof(tdynarray));
             newheader^.refcount:=1;
             newheader^.high:=count-1;
             newdata:=newheader+1;
             if customcopy then
               begin
                 constructed:=0;
                 try
                   dynarray_copy_managed(psrc+elesize*lowidx,newdata,eletype,
                     count,elesize,constructed);
                   dynarray_finish_copy(newdata,eletype,count,constructed);
                 except
                   dynarray_discard_custom(newheader,eletype,constructed);
                   raise;
                 end;
               end
             else
               begin
                 move(pointer(psrc+elesize*lowidx)^,newdata^,size);
                 if assigned(eletype) then
                   int_AddRefArray(newdata,eletype,count);
               end;
           end;
       end;

     { Construct before clearing: Copy(A,...) remains valid when A is also
       selected as the hidden result, and a raising Assign preserves it. }
     olddata:=pointer(result);
     pointer(result):=nil;
     if assigned(olddata) then
       fpc_dynarray_clear(olddata,ti);
     pointer(result):=newdata;
   end;


{ Copy an array whose element type needs no finalization.  The compiler knows
  this property before lowering Copy(), so this path does not need RTTI and
  does not enter the general dynamic-array finalizer. }
function fpc_array_to_dynarray_copy_unmanaged(psrc : pointer;
    lowidx,count,maxcount:tdynarrayindex;
    elesize : sizeint
    ) : fpc_stub_dynarray;[Public,Alias:'FPC_ARR_TO_DYNARR_COPY_UNMANAGED'];compilerproc;
  var
    size : sizeint;
    olddata,newdata,newheader : pointer;
    oldheader : pdynarray;
  begin
     newdata:=nil;
     if psrc<>nil then
       begin
{$ifndef FPC_DYNARRAYCOPY_FIXED}
         if (lowidx=-1) and (count=-1) then
           begin
             lowidx:=0;
             count:=high(tdynarrayindex);
           end;
{$endif FPC_DYNARRAYCOPY_FIXED}
         if lowidx<0 then
           begin
             if count>0 then
               count:=count+lowidx
             else
               count:=0;
             lowidx:=0;
           end;
         if count>maxcount-lowidx then
           count:=maxcount-lowidx;
         if count>0 then
           begin
             size:=elesize*count;
             getmem(newheader,size+sizeof(tdynarray));
             pdynarray(newheader)^.refcount:=1;
             pdynarray(newheader)^.high:=count-1;
             newdata:=newheader+sizeof(tdynarray);
             move(pointer(psrc+elesize*lowidx)^,newdata^,size);
           end;
       end;

     { Build the replacement before releasing the old value.  Besides giving
       strong exception safety, this keeps Copy(A,...) valid when A is also
       the destination selected for the hidden function result. }
     olddata:=pointer(result);
     pointer(result):=nil;
     if olddata<>nil then
       begin
         oldheader:=pdynarray(olddata)-1;
         if (oldheader^.refcount=1) or
            (oldheader^.refcount>0) and
{$ifdef VER3_2}
            declocked(oldheader^.refcount)
{$else}
            (AtomicDecrement(oldheader^.refcount)=0)
{$endif}
            then
           freemem(oldheader);
       end;
     pointer(result):=newdata;
  end;


procedure fpc_dynarray_delete(var p : pointer;source,count : SizeInt;pti : pointer);
   var
      newlen,oldlen : tdynarrayindex;
      elesize,_size,constructed : sizeint;
      { oldp is the same as p, actual header is accessed as oldp[-1].
        newp fairly points to the new header, array data starts at newp[1].
        realp takes the hit of being a var-parameter to ReallocMem not eligible for living in a register. }
      oldp,newp,realp : pdynarray;
      ti,eletypemngd : pointer;
      customcopy : boolean;

   begin
     oldp:=p;
     if not assigned(oldp) or (count<=0) then
       exit;
     newlen:=oldp[-1].high+1;
     { Checks source < 0 or source >= len, using the fact that len is never negative. }
     if SizeUint(source)>=SizeUint(newlen) then
       exit;
     { cap count, and maybe delete whole array }
     if count>=newlen-source then
       begin
         if source=0 then
           begin
             fpc_dynarray_clear(p,pti);
             exit;
           end;
         count:=newlen-source;
       end;

     { skip kind and name }
     ti:=aligntoqword(Pointer(pti)+2+PByte(pti)[1]);

     elesize:=pdynarraytypedata(ti)^.elSize;
     { only set if type needs finalization }
     eletypemngd:=pdynarraytypedata(ti)^.elType;
     if assigned(eletypemngd) then
       eletypemngd:=PPointer(eletypemngd)^;

     oldlen:=newlen;
     newlen:=newlen-count;

     if oldp[-1].refcount<>1 then
       begin
          { A custom Assign defines value identity.  Detach the complete
            shared array first, exactly as a semantic COW operation, then let
            the ordinary unique delete transfer surviving owners in-place. }
          if dynarray_copy_may_raise(eletypemngd) then
            begin
              customcopy:=dynarray_has_custom_operation(eletypemngd,rotCopy,_size);
              if customcopy then
                newp:=getmem(elesize*oldlen+sizeof(tdynarray))
              else
                newp:=getmem(elesize*newlen+sizeof(tdynarray));
              newp^.refcount:=1;
              if customcopy then
                newp^.high:=oldlen-1
              else
                newp^.high:=newlen-1;
              constructed:=0;
              try
                if customcopy then
                  dynarray_copy_managed(oldp,newp+1,eletypemngd,oldlen,elesize,constructed)
                else
                  begin
                    dynarray_copy_managed(oldp,newp+1,eletypemngd,source,elesize,constructed);
                    dynarray_copy_managed(pointer(oldp)+(source+count)*elesize,
                      pointer(newp+1)+source*elesize,eletypemngd,newlen-source,elesize,constructed);
                  end;
                dynarray_finish_copy(newp+1,eletypemngd,newp^.high+1,constructed);
              except
                dynarray_discard_custom(newp,eletypemngd,constructed);
                raise;
              end;
              fpc_dynarray_clear(p,pti);
              p:=newp+1;
              if not customcopy then
                exit;
              oldp:=p;
              if assigned(eletypemngd) then
                int_FinalizeArray(pointer(oldp)+source*elesize,
                  eletypemngd,count);
              move((pointer(oldp)+(source+count)*elesize)^,
                (pointer(oldp)+source*elesize)^,
                (newlen-source)*elesize);
              realp:=newp;
              newp:=reallocmem(realp,elesize*newlen+sizeof(tdynarray));
              newp^.high:=newlen-1;
              p:=newp+1;
              exit;
            end;
          { make an unique copy }
          newp:=getmem(elesize*newlen+sizeof(tdynarray));
          newp^.refcount:=1;
          { copy the elements that we still need }
          move(oldp^,pointer(newp+1)^,source*elesize);
          move((pointer(oldp)+(source+count)*elesize)^,(pointer(newp+1)+source*elesize)^,(newlen-source)*elesize);

          { increment ref. count of managed members }
          if assigned(eletypemngd) then
            int_AddRefArray(newp+1,eletypemngd,newlen);

          { a declock(ref. count) isn't enough here }
          { it could be that the in MT environments  }
          { in the mean time the refcount was       }
          { decremented                             }

          { it is, because it doesn't really matter }
          { if the array is now removed             }
          fpc_dynarray_clear(p,pti);
        end
      else
        begin
          { finalize the elements that will be removed }
          if assigned(eletypemngd) then
            int_FinalizeArray(pointer(oldp)+source*elesize,eletypemngd,count);

          { close the gap by moving the trailing elements to the front }
          move((pointer(oldp)+(source+count)*elesize)^,(pointer(oldp)+source*elesize)^,(newlen-source)*elesize);

          { resize the array }
          realp:=oldp-1;
          newp:=reallocmem(realp,elesize*newlen+sizeof(tdynarray));
        end;
    newp^.high:=newlen-1;
    p:=newp+1;
  end;


{ Move owners in a unique array.  The caller acquires any new values first
  if copying them can raise; ReallocMem leaves the old carrier on failure. }
function dynarray_insert_unique(oldp : pdynarray;source : SizeInt;data : pointer;
  count,elesize,newlen : SizeInt) : pdynarray; inline;
  var
    dataofs : SizeInt;
    newp,realp : pdynarray;
  begin
    { dataofs >= 0 means that 'data' points into the source array with byte offset 'dataofs' from the header.
      dataofs < 0 means that 'data' does not point into the array. }
    dataofs:=-1;
    if (data>=oldp) and (data<=pointer(oldp+1)+oldp^.high*elesize) then
      dataofs:=data-pointer(oldp);

    { resize the array }
    realp:=oldp; { 'realp' as a 'var'-parameter avoids taking 'oldp' address. }
    newp:=reallocmem(realp,elesize*newlen+sizeof(tdynarray));

    { Fixup overlapping 'data'. }
    if dataofs>=0 then
      begin
        data:=pointer(newp)+dataofs;
        { If 'data' points into the trailing part, account for it being moved by 'count'. }
        if data>=pointer(newp+1)+source*elesize then
          data:=data+count*elesize;
      end;

    { move the trailing part after the inserted data }
    move((pointer(newp+1)+source*elesize)^,(pointer(newp+1)+(source+count)*elesize)^,(newp^.high-source+1)*elesize);

    { move the inserted data to the destination }
    move(data^,(pointer(newp+1)+source*elesize)^,count*elesize);

    result:=newp;
  end;

{$ifdef FPC_HAS_FEATURE_CLASSES}
function dynarray_insert_interfaces(oldp : pdynarray;source : SizeInt;data : pointer;
  count,newlen : SizeInt) : pdynarray;
  var
    constructed,i : SizeInt;
    intf : pointer;
  begin
    constructed:=SkipTrailingNils(data,count);
    if constructed=0 then
      exit(dynarray_insert_unique(oldp,source,data,count,sizeof(pointer),newlen));
    try
      dynarray_acquire_interfaces(data,constructed);
      result:=dynarray_insert_unique(oldp,source,data,count,sizeof(pointer),newlen);
    except
      { These slots still belong to the source.  Release only the additional
        references, without clearing the source as FinalizeArray would. }
      for i:=0 to constructed-1 do
        begin
          intf:=PPointer(data)[i];
          if assigned(intf) then
            IUnknown(intf)._Release;
        end;
      raise;
    end;
  end;
{$endif}

procedure fpc_dynarray_insert(var p : pointer;source : SizeInt;data : pointer;count : SizeInt;pti : pointer);compilerproc;
  var
    newlen,oldlen : tdynarrayindex;
    elesize,constructed : sizeint;
    oldp,newp : pdynarray;
    ti,eletypemngd : pointer;
  begin
    if count=0 then
      exit;

    oldp:=p;
    if assigned(oldp) then
      begin
        dec(oldp);
        { cap insert index }
        newlen:=oldp^.high+1;
        if SizeUint(source)>SizeUint(newlen) then { Checks for not (0 <= source <= len), using the fact than 'newlen' is never negative. }
          if source<0 then
            source:=0
          else
            source:=newlen;
        newlen:=newlen+count;
      end
    else
      begin
        source:=0;
        newlen:=count;
      end;

    { skip kind and name }
    ti:=aligntoqword(Pointer(pti)+2+PByte(pti)[1]);

    elesize:=pdynarraytypedata(ti)^.elSize;
    { only set if type needs initialization }
    eletypemngd:=pdynarraytypedata(ti)^.elType;
    if assigned(eletypemngd) then
      eletypemngd:=PPointer(eletypemngd)^;

    if dynarray_copy_may_raise(eletypemngd) then
      begin
{$ifdef FPC_HAS_FEATURE_CLASSES}
        if (PTypeKind(eletypemngd)^=tkInterface) and assigned(oldp) and (oldp^.refcount=1) then
          begin
            newp:=dynarray_insert_interfaces(oldp,source,data,count,newlen);
            newp^.high:=newlen-1;
            p:=newp+1;
            exit;
          end;
{$endif}
        if assigned(oldp) then
          oldlen:=oldp^.high+1
        else
          oldlen:=0;
        newp:=getmem(elesize*newlen+sizeof(tdynarray));
        newp^.refcount:=1;
        newp^.high:=newlen-1;

        if assigned(oldp) and (oldp^.refcount=1) then
          begin
            { Existing elements keep their ownership; only the inserted
              values are copies.  Copy them before moving the old carrier so
              an exception leaves p and any aliased data source untouched. }
            constructed:=0;
            try
              dynarray_copy_managed(data,pointer(newp+1)+source*elesize,
                eletypemngd,count,elesize,constructed);
              dynarray_finish_copy(pointer(newp+1)+source*elesize,eletypemngd,count,constructed);
            except
              try
                if constructed>0 then
                  int_FinalizeArray(pointer(newp+1)+source*elesize,
                    eletypemngd,constructed);
              finally
                freemem(newp);
              end;
              raise;
            end;
            move(oldp[1],newp[1],source*elesize);
            move((pointer(oldp+1)+source*elesize)^,
              (pointer(newp+1)+(source+count)*elesize)^,
              (oldlen-source)*elesize);
            freemem(oldp);
          end
        else
          begin
            { A shared destination cannot transfer owners.  Construct the
              complete logical result in order so one rollback count covers
              every successful or currently executing Assign. }
            constructed:=0;
            try
              if source>0 then
                dynarray_copy_managed(oldp+1,newp+1,eletypemngd,
                  source,elesize,constructed);
              dynarray_copy_managed(data,pointer(newp+1)+source*elesize,
                eletypemngd,count,elesize,constructed);
              if oldlen>source then
                dynarray_copy_managed(pointer(oldp+1)+source*elesize,
                  pointer(newp+1)+(source+count)*elesize,eletypemngd,
                  oldlen-source,elesize,constructed);
              dynarray_finish_copy(newp+1,eletypemngd,newlen,constructed);
            except
              dynarray_discard_custom(newp,eletypemngd,constructed);
              raise;
            end;
            if assigned(oldp) then
              fpc_dynarray_clear(p,pti);
          end;
        p:=newp+1;
        exit;
      end;

    if not assigned(oldp) or (oldp^.refcount<>1) then
      begin
        newp:=getmem(elesize*newlen+sizeof(tdynarray));

        { copy leading elements. No-op when not Assigned(oldp) because in this case source = 0. }
        move(oldp[1],newp[1],source*elesize);
        { insert new elements }
        move(data^,(pointer(newp+1)+source*elesize)^,count*elesize);
        { copy trailing elements. This time must be careful with not Assigned(oldp). }
        if assigned(oldp) then
          move((pointer(oldp+1)+source*elesize)^,(pointer(newp+1)+(source+count)*elesize)^,(oldp^.high-source+1)*elesize);

        { increment ref. count of managed members }
        if assigned(eletypemngd) then
          int_AddRefArray(newp+1,eletypemngd,newlen);

        { a declock(ref. count) isn't enough here }
        { it could be that the in MT environments }
        { in the mean time the refcount was       }
        { decremented                             }

        { it is, because it doesn't really matter }
        { if the array is now removed             }
        fpc_dynarray_clear(p,pti);
      end
    else
      begin
        newp:=dynarray_insert_unique(oldp,source,data,count,elesize,newlen);

        { increase reference counts of inserted elements }
        if assigned(eletypemngd) then
          int_AddRefArray(pointer(newp+1)+source*elesize,eletypemngd,count);
      end;

    newp^.refcount:=1;
    newp^.high:=newlen-1;
    p:=newp+1;
  end;


{$ifdef FPC_HAS_FEATURE_CLASSES}
{ Moves cannot raise for interface slots.  Defer the exception frame until
  there is an actual reference to acquire; an all-nil copy owns only memory. }
procedure dynarray_finish_interface_copy(data : PPointer;count : SizeInt;header : pdynarray);
  var
    constructed,i : SizeInt;
    intf : pointer;
  begin
    constructed:=SkipTrailingNils(data,count);
    if constructed=0 then
      exit;
    try
      dynarray_acquire_interfaces(data,constructed);
    except
      for i:=0 to constructed-1 do
        begin
          intf:=data[i];
          if assigned(intf) then
            IUnknown(intf)._Release;
        end;
      if assigned(header) then
        freemem(header);
      raise;
    end;
  end;

procedure dynarray_copy_interface_parts(const sarr : array of pointer;
  first : SizeInt;olddata,newdata,destdata : pointer); inline;
  var
    i,bytes : SizeInt;
    source : pdynarray;
  begin
    for i:=first to high(sarr) do
      if assigned(sarr[i]) then
        begin
          source:=sarr[i];
          if source=olddata then
            source:=newdata;
          bytes:=(source[-1].high+1)*sizeof(pointer);
          move(source^,destdata^,bytes);
          inc(destdata,bytes);
        end;
  end;
{$endif}

procedure fpc_dynarray_concat_multi(var dest : pointer; pti: pointer; const sarr:array of pointer); compilerproc;
  var
    i,firstnonempty,elesize,totallen,copybytes,newdestdatapos,
      constructed,oldlen,partlen : sizeint;
    newp,realp,copysrc,olddestp : pdynarray;
    ti,eletypemngd,copydest : pointer;
  begin
    totallen:=0;
    for i:=high(sarr) downto 0 do
      if assigned(sarr[i]) then
        begin
          inc(totallen,pdynarray(sarr[i])[-1].high+1);
          firstnonempty:=i; { 1) allows for append optimization to work even with some prepended []s, 2) required for the reuse optimization. }
        end;

    if totallen=0 then
      begin
        fpc_dynarray_clear(dest,pti);
        exit;
      end;

    { Reuse the only nonempty input? }
    if totallen=pdynarray(sarr[firstnonempty])[-1].high+1 then
      begin
        fpc_dynarray_assign(dest,sarr[firstnonempty],pti);
        exit;
      end;

    { skip kind and name }
    ti:=aligntoqword(Pointer(pti)+2+PByte(pti)[1]);

    elesize:=pdynarraytypedata(ti)^.elSize;
    { only set if type needs initialization }
    eletypemngd:=pdynarraytypedata(ti)^.elType;
    if Assigned(eletypemngd) then
      eletypemngd:=PPointer(eletypemngd)^;

    if dynarray_copy_may_raise(eletypemngd) then
      begin
        olddestp:=dest;
        if assigned(olddestp) and (olddestp[-1].refcount=1) and
           (olddestp=sarr[firstnonempty]) then
          begin
            { The leftmost operand already owns the prefix.  Keep that
              ownership and construct only appended copies. }
            oldlen:=olddestp[-1].high+1;
            realp:=olddestp-1;
            newp:=reallocmem(realp,totallen*elesize+sizeof(tdynarray));
            dest:=newp+1;
            copydest:=pointer(newp+1)+oldlen*elesize;
            constructed:=0;
{$ifdef FPC_HAS_FEATURE_CLASSES}
            if PTypeKind(eletypemngd)^=tkInterface then
              begin
                dynarray_copy_interface_parts(sarr,firstnonempty+1,olddestp,newp+1,copydest);
                dynarray_finish_interface_copy(copydest,totallen-oldlen,nil);
              end
            else
{$endif}
            try
              for i:=firstnonempty+1 to high(sarr) do
                if assigned(sarr[i]) then
                  begin
                    copysrc:=sarr[i];
                    if copysrc=olddestp then
                      copysrc:=newp+1;
                    partlen:=copysrc[-1].high+1;
                    dynarray_copy_managed(copysrc,copydest,eletypemngd,
                      partlen,elesize,constructed);
                    inc(copydest,partlen*elesize);
                  end;
            except
              if constructed>0 then
                int_FinalizeArray(pointer(newp+1)+oldlen*elesize,
                  eletypemngd,constructed);
              raise;
            end;
            newp^.high:=totallen-1;
            exit;
          end;

        newp:=getmem(totallen*elesize+sizeof(tdynarray));
        newp^.refcount:=1;
        newp^.high:=totallen-1;
        copydest:=newp+1;
        constructed:=0;
{$ifdef FPC_HAS_FEATURE_CLASSES}
        if PTypeKind(eletypemngd)^=tkInterface then
          begin
            dynarray_copy_interface_parts(sarr,0,nil,newp+1,copydest);
            dynarray_finish_interface_copy(copydest,totallen,newp);
          end
        else
{$endif}
        try
          for i:=0 to high(sarr) do
            if assigned(sarr[i]) then
              begin
                copysrc:=sarr[i];
                partlen:=copysrc[-1].high+1;
                dynarray_copy_managed(copysrc,copydest,eletypemngd,
                  partlen,elesize,constructed);
                inc(copydest,partlen*elesize);
              end;
        except
          dynarray_discard_custom(newp,eletypemngd,constructed);
          raise;
        end;
        fpc_dynarray_clear(dest,pti);
        dest:=newp+1;
        exit;
      end;

    olddestp:=dest;
    { Reallocate when possible; in the hope this will reuse the chunk more often than do a redundant copy. }
    if assigned(olddestp) and (olddestp[-1].refcount=1) then
      begin
        if assigned(eletypemngd) then
          begin
            { Find dest occurrence among inputs. If found, reuse: remember its position, don't finalize now and don't AddRef later. }
            newdestdatapos:=0;
            for i:=0 to high(sarr) do
              if assigned(sarr[i]) then
                if sarr[i]<>olddestp then
                  inc(newdestdatapos,pdynarray(sarr[i])[-1].high+1)
                else
                  break;
            if newdestdatapos=totallen then { Dest doesn't occur among inputs. }
              int_FinalizeArray(olddestp,eletypemngd,olddestp[-1].high+1);
          end;
        realp:=olddestp-1;
        newp:=reallocmem(realp,totallen*elesize+sizeof(tdynarray));
        { First array can be skipped if appending. }
        if olddestp=sarr[firstnonempty] then
          inc(firstnonempty);
      end
    else
      begin
        olddestp:=nil; { Realloc case is distinguished later as assigned(olddestp). }
        { allocate new array }
        newp:=getmem(totallen*elesize+sizeof(tdynarray));
        newp^.refcount:=1;
      end;

    { Copy arrays from last to the first, so that possible occurences of Dest could read from the beginning of the reallocated Dest. }
    copydest:=pointer(newp+1)+totallen*elesize;
    for i:=high(sarr) downto firstnonempty do
      begin
        copysrc:=sarr[i];
        if not assigned(copysrc) then
          continue;
        if copysrc=olddestp then
          { Dest used as one of the pieces! Use new pointer instead. Array header still conveniently contains original 'high'.
            Can trigger only in the ReallocMem case, as otherwise olddestp = nil. }
          copysrc:=newp+1;
        copybytes:=(copysrc[-1].high+1)*elesize;
        dec(copydest,copybytes);
        move(copysrc^,copydest^,copybytes);
      end;

    if assigned(eletypemngd) then
      begin
        { AddRef everything in GetMem case or if Dest data was not reused in the ReallocMem case. }
        if not assigned(olddestp) or (newdestdatapos=totallen) then
          int_AddRefArray(pointer(newp+1),eletypemngd,totallen)
        else
          begin
            { Dest := A + Dest + B, Dest data reused. }
            if newdestdatapos>0 then
              { AddRef A. Since Dest := Dest + B is a common case, shortcut if nothing to do. }
              int_AddRefArray(newp+1,eletypemngd,newdestdatapos);
            { AddRef B. }
            int_AddRefArray(pointer(newp+1)+(newdestdatapos+newp^.high+1)*elesize,eletypemngd,totallen-(newdestdatapos+newp^.high+1));
          end;
      end;

    if not assigned(olddestp) then
      { clear at the end, dest could be a reference to an array being used also as source }
      fpc_dynarray_clear(dest,pti);

    newp^.high:=totallen-1;
    dest:=newp+1;
  end;


procedure fpc_dynarray_concat(var dest : pointer; pti: pointer; const src1,src2 : pointer); compilerproc;
  var
    totallen,elesize,ofs2,constructed,oldlen,src2len : sizeint;
    newp,realp,olddestp,copysrc : pdynarray;
    ti,eletypemngd : pointer;
  begin
    if not assigned(src1) or not assigned(src2) then
      begin
        fpc_dynarray_assign(dest, pointer(ptruint(src1) or ptruint(src2)), pti);
        exit; { From now on, both src1 and src2 are non-nil. }
      end;
    totallen:=pdynarray(src1)[-1].high+pdynarray(src2)[-1].high+2;

    { skip kind and name }
    ti:=aligntoqword(Pointer(pti)+2+PByte(pti)[1]);

    elesize:=pdynarraytypedata(ti)^.elSize;
    { only set if type needs initialization }
    eletypemngd:=pdynarraytypedata(ti)^.elType;
    if assigned(eletypemngd) then
      eletypemngd:=PPointer(eletypemngd)^;
    ofs2:=(pdynarray(src1)[-1].high+1)*elesize; { Offset of src2 data in the resulting array. }

    if dynarray_copy_may_raise(eletypemngd) then
      begin
        olddestp:=dest;
        if assigned(olddestp) and (olddestp[-1].refcount=1) and
           (olddestp=src1) then
          begin
            oldlen:=olddestp[-1].high+1;
            src2len:=pdynarray(src2)[-1].high+1;
            realp:=olddestp-1;
            newp:=reallocmem(realp,totallen*elesize+sizeof(tdynarray));
            dest:=newp+1;
            copysrc:=src2;
            if copysrc=olddestp then
              copysrc:=newp+1;
            constructed:=0;
            try
              dynarray_copy_managed(copysrc,pointer(newp+1)+oldlen*elesize,
                eletypemngd,src2len,elesize,constructed);
              dynarray_finish_copy(pointer(newp+1)+oldlen*elesize,eletypemngd,src2len,constructed);
            except
              if constructed>0 then
                int_FinalizeArray(pointer(newp+1)+oldlen*elesize,
                  eletypemngd,constructed);
              raise;
            end;
            newp^.high:=totallen-1;
            exit;
          end;

        newp:=getmem(totallen*elesize+sizeof(tdynarray));
        newp^.refcount:=1;
        newp^.high:=totallen-1;
        constructed:=0;
        try
          dynarray_copy_managed(src1,newp+1,eletypemngd,
            pdynarray(src1)[-1].high+1,elesize,constructed);
          dynarray_copy_managed(src2,pointer(newp+1)+ofs2,eletypemngd,
            pdynarray(src2)[-1].high+1,elesize,constructed);
          dynarray_finish_copy(newp+1,eletypemngd,totallen,constructed);
        except
          dynarray_discard_custom(newp,eletypemngd,constructed);
          raise;
        end;
        fpc_dynarray_clear(dest,pti);
        dest:=newp+1;
        exit;
      end;

    olddestp:=dest;
    { Reallocate when possible; in the hope this will reuse the chunk more often than do a redundant copy. }
    if assigned(olddestp) and (olddestp[-1].refcount=1) then
      begin
        { Finalize old dest contents, if they aren't going to be reused. }
        if assigned(eletypemngd) and (olddestp<>src1) and (olddestp<>src2) then
          int_FinalizeArray(olddestp,eletypemngd,olddestp[-1].high+1);

        realp:=olddestp-1;
        newp:=reallocmem(realp,totallen*elesize+sizeof(tdynarray));
        { Copy src2 first, as in the case of olddestp = src2 it must be copied first and in other cases the order does not matter. }
        copysrc:=src2;
        if copysrc=olddestp then
          { Use new pointer instead. Array header still conveniently contains original 'high'. }
          copysrc:=newp+1;
        move(copysrc^,(pointer(newp+1)+ofs2)^,(copysrc[-1].high+1)*elesize);
        if olddestp<>src1 then { Not an append, need to copy src1? }
          move(src1^,newp[1],(pdynarray(src1)[-1].high+1)*elesize);

        { AddRef new data. }
        if assigned(eletypemngd) then
          if src1=olddestp then
            { Dest data stayed in the same position; AddRef only copied src2. }
            int_AddRefArray(pointer(newp+1)+ofs2,eletypemngd,copysrc[-1].high+1)
          else if src2=olddestp then
            { Dest data was moved as if it was src2; AddRef only copied src1. }
            int_AddRefArray(newp+1,eletypemngd,pdynarray(src1)[-1].high+1)
          else
            { Dest data was not used, AddRef everything. }
            int_AddRefArray(newp+1,eletypemngd,totallen);
      end
    else
      begin
        { allocate new array }
        newp:=getmem(totallen*elesize+sizeof(tdynarray));
        newp^.refcount:=1;
        move(src1^,newp[1],ofs2);
        move(src2^,(pointer(newp+1)+ofs2)^,(pdynarray(src2)[-1].high+1)*elesize);

        { increase reference counts of all the elements }
        if assigned(eletypemngd) then
          int_AddRefArray(newp+1,eletypemngd,totallen);

        { clear at the end, dest could be a reference to an array being also source }
        fpc_dynarray_clear(dest,pti);
      end;
    newp^.high:=totallen-1;
    dest:=newp+1;
  end;

procedure DynArraySetLength(var a: Pointer; typeInfo: Pointer; dimCnt: SizeInt; lengthVec: PSizeInt);
  external name 'FPC_DYNARR_SETLENGTH';

function DynArraySize(a : pointer): tdynarrayindex;
  external name 'FPC_DYNARRAY_LENGTH';

procedure DynArrayClear(var a: Pointer; typeInfo: Pointer);
  external name 'FPC_DYNARRAY_CLEAR';

procedure DynArrayAssign(var dest: Pointer; src: Pointer; typeInfo: pointer);
  external name 'FPC_DYNARRAY_ASSIGN';

function DynArrayDim(typeInfo: Pointer): Integer;
  begin
    result:=0;
    while (typeInfo <> nil) and (pdynarraytypeinfo(typeInfo)^.kind = tkDynArray) do
    begin
      { skip kind and name }
      typeInfo:=aligntoqword(typeInfo+2+PByte(typeInfo)[1]);

      { element type info}
      typeInfo:=pdynarraytypedata(typeInfo)^.elType2^;

      Inc(result);
    end;
  end;

function DynArrayBounds(a: Pointer; typeInfo: Pointer): TBoundArray;
  var
    i,dim: sizeint;
  begin
    dim:=DynArrayDim(typeInfo);
    SetLength(result, dim);

    for i:=0 to pred(dim) do
      if a = nil then
        exit
      else
      begin
        a:=PPointerArray(a)^[0];
        result[i]:=DynArraySize(a)-1;
      end;
  end;

function IsDynArrayRectangular(a: Pointer; typeInfo: Pointer): Boolean;
  var
    i,j: sizeint;
    dim,count: sizeint;
  begin
    dim:=DynArrayDim(typeInfo);
    for i:=1 to pred(dim) do
    begin
      count:=DynArraySize(PPointerArray(a)^[0]);

      for j:=1 to Pred(DynArraySize(a)) do
        if count<>DynArraySize(PPointerArray(a)^[j]) then
          exit(false);

      a:=PPointerArray(a)^[0];
    end;
    result:=true;
  end;

function DynArrayIndex(a: Pointer; const indices: array of SizeInt; typeInfo: Pointer): Pointer;
  var
    i,h: sizeint;
  begin
    h:=High(indices);
    for i:=0 to h do
    begin
      { skip kind and name }
      typeInfo:=aligntoqword(Pointer(typeInfo)+2+PByte(typeInfo)[1]);
      if i=h then
        break;
      a := PPointerArray(a)^[indices[i]];
      { element type info}
      typeInfo:=pdynarraytypedata(typeInfo)^.elType2^;
    end;
    result:=a+SizeUint(indices[h])*pdynarraytypedata(typeInfo)^.elSize;
  end;

{ obsolete but needed for bootstrapping }
procedure fpc_dynarray_decr_ref(var p : pointer;ti : pointer); [Public,Alias:'FPC_DYNARRAY_DECR_REF']; compilerproc;
  begin
    fpc_dynarray_clear(p,ti);
  end;

