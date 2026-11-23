{ Shared transaction for record arrays. The compiler selects the ownership transfer at the call site. }
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
{$ifdef FPC_WEAK_ARRAY_ELEMENTS}
               if not Assigned(newp) then HandleError(203);
{$endif}
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
{$ifdef FPC_WEAK_ARRAY_ELEMENTS}
               realp:=p-sizeof(tdynarray);
               if newlen=oldlen then
                 newp:=realp
               else if newlen<oldlen then
                 newp:=DeleteWeakArrayRange(realp,newlen,oldlen-newlen,elesize,eletypemngd)
               else if WeakTableActive then
                 newp:=GrowWeakArrayOwnership(realp,size,elesize)
               else
                 begin
                   newp:=reallocmem(realp,size);
                   if not Assigned(newp) then HandleError(203);
                 end;
{$else}
               { Finalize if shrinking. }
               if assigned(eletypemngd) and (newlen<oldlen) then
                 int_finalizearray(p+elesize*newlen,eletypemngd,oldlen-newlen);
               realp:=p-sizeof(tdynarray);
               newp:=reallocmem(realp,size);
{$endif}
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
{$ifdef FPC_WEAK_ARRAY_ELEMENTS}
          if not Assigned(newp) then HandleError(203);
{$endif}
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
