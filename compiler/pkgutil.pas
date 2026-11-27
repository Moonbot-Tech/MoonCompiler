{
    Copyright (c) 2013-2016 by Free Pascal Development Team

    This unit implements basic parts of the package system

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

unit pkgutil;

{$i fpcdefs.inc}

interface

  uses
    fmodule,fpkg,link,cstreams,cclasses;

  procedure createimportlibfromexternals;
  Function RewritePPU(const PPUFn:String;OutStream:TCStream):Boolean;
  procedure export_unit(u:tmodule);
  procedure export_package_initfinal;
  procedure export_package_packageflags;
  procedure export_package_regprocs;
  procedure load_packages;
  procedure add_package(const name:string;ignoreduplicates:boolean;direct:boolean);
  procedure add_package_unit_ref(package:tpackage);
  procedure add_package_libs(l:tlinker);
  procedure check_for_indirect_package_usages(modules:tlinkedlist);

implementation

  uses
    sysutils,
    globtype,systems,
    cutils,
    globals,verbose,
    aasmbase,aasmdata,aasmcnst,
    symtype,symconst,symsym,symdef,symbase,symtable,
    node,nld,ncal,nutils,
    psub,pdecsub,
    ppu,entfile,fpcp,
    export;

  procedure procexport(const s : string);
    var
      hp : texported_item;
    begin
      hp:=texported_item.create;
      hp.name:=stringdup(s);
      hp.options:=hp.options+[eo_name];
      exportlib.exportprocedure(hp);
    end;


  procedure varexport(const s : string);
    var
      hp : texported_item;
    begin
      hp:=texported_item.create;
      hp.name:=stringdup(s);
      hp.options:=hp.options+[eo_name];
      exportlib.exportvar(hp);
    end;


  { True when a symtable ultimately lives in a unit's implementation part.
    For methods of (possibly nested) record/object types this walks up the
    defowner chain to the containing module-level symtable. }
  function ownedbystaticsymtable(st:tsymtable):boolean;
    begin
      while assigned(st) and (st.symtabletype in [objectsymtable,recordsymtable]) do
        st:=tdef(st.defowner).owner;
      result:=assigned(st) and (st.symtabletype=staticsymtable);
    end;


  function exportableprocdef(pd:tprocdef;symtable:tsymtable):boolean;
    begin
      result:=
        not(pd.proccalloption in [pocall_internproc]) and
        not (df_generic in pd.defoptions) and
        ((pd.procoptions*[po_external])=[]) and
        (
          (symtable.symtabletype in [globalsymtable,recordsymtable,objectsymtable]) or
          (symtable.symtabletype=staticsymtable)
        ) and
        (
          { interface symbols are exported unconditionally;
            implementation-only symbols (unit level or methods of
            implementation types, however deeply nested) only when the
            object file actually carries them as globals -- i.e. public,
            or referenced from an inlined routine (df_has_global_ref).
            Exporting anything else would name symbols the linker
            cannot resolve. }
          not ownedbystaticsymtable(symtable) or
          ([po_public,po_has_public_name]*pd.procoptions<>[]) or
          (df_has_global_ref in pd.defoptions)
        );
    end;


  procedure exportprocsym(sym:tprocsym;symtable:tsymtable);
    var
      i : longint;
      pd : tprocdef;
    begin
      for i:=0 to tprocsym(sym).ProcdefList.Count-1 do
        begin
          pd:=tprocdef(tprocsym(sym).procdeflist[i]);
          if exportableprocdef(pd,symtable) then
            begin
              exportallprocdefnames(tprocsym(sym),pd,[eo_name,eo_no_sym_name]);
            end;
        end;
    end;


  { An overload declared only in the implementation, whose name already exists
    in the interface, is attached to the *interface* procsym -- it gets no
    procsym of its own in the implementation symtable. tprocsym.buildderef
    (symsym.pas) then persists only those procdefs whose owner is the procsym's
    own symtable, so the interface procsym in the .ppu carries the interface
    overloads alone.

    Such a procdef is in neither symlist walk of export_unit, and the package
    never exports it -- while the object file does define it globally, because
    an inlined interface routine calls it. Consumers of the package then hit
    "Undefined symbol" on the expanded inline body.

    Measured 2026-09-02 on sysutils:
      Trim(S:unicodestring)               -- interface, inline
      Trim(S:unicodestring;m:TTrimMode)   -- implementation only  <- missing
    The interface TRIM procsym carried 3 procdefs (the interface overloads);
    the 2-argument ones showed up in no walk at all.

    So reach them through the implementation DefList. Procdefs whose procsym
    does live in this symtable are already covered by the symlist walk. }
  procedure exportimplementationonlyprocdefs(u:tmodule);
    var
      i : longint;
      def : tdef;
      pd : tprocdef;
    begin
      if not assigned(u.localsymtable) then
        exit;
      for i:=0 to u.localsymtable.DefList.Count-1 do
        begin
          def:=tdef(u.localsymtable.DefList[i]);
          { deflist may hold NIL entries }
          if not assigned(def) or (def.typ<>procdef) then
            continue;
          pd:=tprocdef(def);
          if not assigned(pd.procsym) or (pd.procsym.owner=u.localsymtable) then
            continue;
          if exportableprocdef(pd,u.localsymtable) then
            exportallprocdefnames(tprocsym(pd.procsym),pd,[eo_name,eo_no_sym_name]);
        end;
    end;


  procedure exportabstractrecorddef(def:tabstractrecorddef;symtable:tsymtable); forward;


  procedure exportabstractrecordsymproc(sym:tobject;arg:pointer);
    begin
      case tsym(sym).typ of
        typesym:
          begin
            case ttypesym(sym).typedef.typ of
              objectdef,
              recorddef:
                exportabstractrecorddef(tabstractrecorddef(ttypesym(sym).typedef),tsymtable(arg));
              else
                ;
            end;
          end;
        procsym:
          begin
            { don't export methods of interfaces }
            if is_interface(tdef(tabstractrecordsymtable(arg).defowner)) then
              exit;
            exportprocsym(tprocsym(sym),tsymtable(arg));
          end;
        staticvarsym:
          begin
            { class vars of implementation types: same rule as unit-level
              statics in insert_export -- only when actually global }
            if ownedbystaticsymtable(tsymtable(arg)) and
                ([vo_is_public,vo_has_global_ref]*tstaticvarsym(sym).varoptions=[]) then
              exit;
            varexport(tsym(sym).mangledname);
          end;
        else
          ;
      end;
    end;


  procedure exportname(const s:tsymstr);
    var
      hp : texported_item;
    begin
      hp:=texported_item.create;
      hp.name:=stringdup(s);
      hp.options:=hp.options+[eo_name];
      exportlib.exportvar(hp);
    end;


  procedure exportabstractrecorddef(def:tabstractrecorddef;symtable:tsymtable);
    begin
      { for cross unit type aliases this might happen }
      if def.owner<>symtable then
        exit;
      { don't export generics or their nested types }
      if df_generic in def.defoptions then
        exit;
      def.symtable.SymList.ForEachCall(@exportabstractrecordsymproc,def.symtable);
      if def.typ=objectdef then
        begin
          if (oo_has_vmt in tobjectdef(def).objectoptions) then
            exportname(tobjectdef(def).vmt_mangledname);
          if is_interface(def) then
            begin
              if assigned(tobjectdef(def).iidguid) then
                exportname(make_mangledname('IID',def.owner,def.objname^));
              exportname(make_mangledname('IIDSTR',def.owner,def.objname^));
            end;
        end;
    end;


  procedure export_typedef(def:tdef;symtable:tsymtable;global:boolean);
    begin
      if ([df_internal,df_generic]*def.defoptions<>[]) or
          { happens with type renaming declarations ("abc = xyz") }
          (def.owner<>symtable) then
        exit;
      if not (global or is_class(def)) then
        begin
          { Implementation-only types used to be skipped entirely, but an
            inline routine in the interface may expand into a consumer of
            the package and call methods of such a type -- e.g. the system
            unit's heap manager: SYSTEM$_$HEAPINC_$_THREADSTATE_$__$$_ORPHAN
            is referenced by every program built against an rtl package and
            was not exported, so the DLL failed to load. Walk record/object
            types so their methods reach exportprocsym, which only exports
            the ones the object file actually carries as globals
            (po_public / df_has_global_ref). }
          if not (def.typ in [recorddef,objectdef]) then
            exit;
        end
      else
        begin
          if ds_rtti_table_written in def.defstates then
            exportname(def.rtti_mangledname(fullrtti));
          if (ds_init_table_written in def.defstates) and
              def.needs_separate_initrtti then
            exportname(def.rtti_mangledname(initrtti));
        end;
      case def.typ of
        recorddef,
        objectdef:
          exportabstractrecorddef(tabstractrecorddef(def),symtable);
        else
          ;
      end;
    end;


  procedure insert_export(sym : TObject;arg:pointer);
    var
      isglobal,
      publiconly : boolean;
    begin
      publiconly:=tsymtable(arg).symtabletype=staticsymtable;
      isglobal:=tsymtable(arg).symtabletype=globalsymtable;
      case TSym(sym).typ of
        { ignore: }
        unitsym,
        syssym,
        namespacesym,
        propertysym,
        enumsym:
          ;
        constsym:
          begin
            { Both kinds must be checked. With a Unicode RTL a resourcestring
              is created as constwresourcestring (pdecl.pas); testing only
              constresourcestring here made a package export none of its
              individual resource strings, only the START/END markers. The rest
              of the compiler tests the set; these places in this unit were
              the exception. }
            if tconstsym(sym).consttyp in [constresourcestring,constwresourcestring] then
              varexport(make_mangledname('RESSTR',tsym(sym).owner,tsym(sym).name));
          end;
        typesym:
          begin
            export_typedef(ttypesym(sym).typedef,tsymtable(arg),isglobal);
          end;
        procsym:
          begin
            exportprocsym(tprocsym(sym),tsymtable(arg));
          end;
        staticvarsym:
          begin
            if publiconly and ([vo_is_public,vo_has_global_ref]*tstaticvarsym(sym).varoptions=[]) then
              exit;
            varexport(tsym(sym).mangledname);
          end;
        absolutevarsym:
          ;
        else
          begin
            //writeln('unknown: ',TSym(sym).typ);
            internalerror(2016080501);
          end;
      end;
    end;


  procedure export_unit(u: tmodule);
    var
      i : longint;
      sym : tasmsymbol;
    begin
      u.globalsymtable.symlist.ForEachCall(@insert_export,u.globalsymtable);
      { check localsymtable for exports too to get public symbols }
      u.localsymtable.symlist.ForEachCall(@insert_export,u.localsymtable);
      { neither walk reaches implementation-only overloads of interface names }
      exportimplementationonlyprocdefs(u);

      { create special exports }
      if mf_init in u.moduleflags then
        procexport(make_mangledname('INIT$',u.globalsymtable,''));
      if mf_finalize in u.moduleflags then
        procexport(make_mangledname('FINALIZE$',u.globalsymtable,''));
      if mf_threadvars in u.moduleflags then
        varexport(make_mangledname('THREADVARLIST',u.globalsymtable,''));
      if mf_has_resourcestrings in u.moduleflags then
        begin
          varexport(ctai_typedconstbuilder.get_vectorized_dead_strip_section_symbol_start('RESSTR',u.localsymtable,[]).name);
          varexport(ctai_typedconstbuilder.get_vectorized_dead_strip_section_symbol_end('RESSTR',u.localsymtable,[]).name);
        end;

      if not (target_info.system in systems_indirect_var_imports) then
        for i:=0 to u.publicasmsyms.count-1 do
          begin
            sym:=tasmsymbol(u.publicasmsyms[i]);
            if sym.bind=AB_INDIRECT then
              varexport(sym.name);
          end;
    end;


  procedure export_package_initfinal;
    begin
      { The table itself is emitted by tnodeutils.InsertInitFinalTable under
        the asm symbol INITFINAL. Publishing it lets a run-time loader find
        the package's units:

          GetProcAddress(handle, 'INITFINAL')

        yields a PInitFinalTable whose Procs[1..TableCount] hold the INIT$ /
        FINALIZE$ entry points of the units this package contains. The name is
        per-image, so it does not clash with the host program's own
        (unexported) INITFINAL. }
      varexport('INITFINAL');
    end;


  procedure export_package_packageflags;
    begin
      { Emitted by tnodeutils.InsertPackageFlags as the asm symbol
        PACKAGEFLAGS. A host that only ever sees the DLL -- it does not get
        the .pcp -- reads the package kind from here:

          bit 0  design-time only, must not be linked into a program
          bit 1  run-time only, must not be installed into an IDE

        Both clear means either use, which is Delphi's default. }
      varexport('PACKAGEFLAGS');
    end;


  procedure export_package_regprocs;
    begin
      { Emitted by tnodeutils.InsertRegProcsTable as the asm symbol REGPROCS.
        An IDE calls these at *install* time, never at link or load time --
        that is Delphi's contract, and it is why a run-time program never
        pays for the palette. The layout is

          TableCount : PtrUInt
          Procs      : array[1..TableCount] of record
                         Proc     : procedure;
                         UnitName : ^ShortString;
                       end;

        Not emitted at all for a RUNONLY package, so the absence of this
        export means "nothing here is installable", which is different from
        an export whose TableCount happens to be 0. }
      varexport('REGPROCS');
    end;

  Function RewritePPU(const PPUFn:String;OutStream:TCStream):Boolean;
    Var
      MakeStatic : Boolean;
    Var
      buffer : array[0..$1fff] of byte;
      inppu,
      outppu : tppufile;
      b,
      untilb : byte;
      l,m    : longint;
      ext,
      s      : string;
      ppuversion : dword;
    begin
      Result:=false;
      MakeStatic:=False;
      inppu:=tppufile.create(PPUFn);
      if not inppu.openfile then
       begin
         inppu.free;
         inppu := nil;
         Comment(V_Error,'Could not open : '+PPUFn);
         Exit;
       end;
    { Check the ppufile }
      if not inppu.CheckPPUId then
       begin
         inppu.free;
         inppu := nil;
         Comment(V_Error,'Not a PPU File : '+PPUFn);
         Exit;
       end;
      ppuversion:=inppu.getversion;
      if ppuversion<>CurrentPPUVersion then
       begin
         inppu.free;
         inppu := nil;
         Comment(V_Error,'Wrong PPU Version '+tostr(ppuversion)+' in '+PPUFn);
         Exit;
       end;
    { Already a lib? }
      if (inppu.header.common.flags and uf_in_library)<>0 then
       begin
         inppu.free;
         inppu := nil;
         Comment(V_Error,'PPU is already in a library : '+PPUFn);
         Exit;
       end;
    { We need a static linked unit, but we also accept those without .o file }
      if (inppu.header.common.flags and (uf_static_linked or uf_no_link))=0 then
       begin
         inppu.free;
         inppu := nil;
         Comment(V_Error,'PPU is not static linked : '+PPUFn);
         Exit;
       end;
    { Check if shared is allowed }
      if tsystem(inppu.header.common.target) in [system_i386_go32v2] then
       begin
         Comment(V_Error,'Shared library not supported for ppu target, switching to static library');
         MakeStatic:=true;
       end;
    { Create the new ppu }
      outppu:=tppufile.create(PPUFn);
      outppu.createstream(OutStream);
    { Create new header, with the new flags }
      outppu.header:=inppu.header;
      outppu.header.common.flags:=outppu.header.common.flags or uf_in_library;
      if MakeStatic then
       outppu.header.common.flags:=outppu.header.common.flags or uf_static_linked
      else
       outppu.header.common.flags:=outppu.header.common.flags or uf_shared_linked;
    { read until the object files are found }
      untilb:=iblinkunitofiles;
      repeat
        b:=inppu.readentry;
        if b in [ibendinterface,ibend] then
         begin
           inppu.free;
           inppu := nil;
           outppu.free;
           outppu := nil;
           Comment(V_Error,'No files to be linked found : '+PPUFn);
           Exit;
         end;
        if b<>untilb then
         begin
           repeat
             inppu.getdatabuf(buffer,sizeof(buffer),l);
             outppu.putdata(buffer,l);
           until l<sizeof(buffer);
           outppu.writeentry(b);
         end;
      until (b=untilb);
    { we have now reached the section for the files which need to be added,
      now add them to the list }
      case b of
        iblinkunitofiles :
          begin
            { add all o files, and save the entry when not creating a static
              library to keep staticlinking possible }
            while not inppu.endofentry do
             begin
               s:=inppu.getstring;
               m:=inppu.getlongint;
               if not MakeStatic then
                begin
                  outppu.putstring(s);
                  outppu.putlongint(m);
                end;
               current_module.linkotherofiles.add(s,link_always);
             end;
            if not MakeStatic then
             outppu.writeentry(b);
          end;
    {    iblinkunitstaticlibs :
          begin
            AddToLinkFiles(ExtractLib(inppu.getstring));
            if not inppu.endofentry then
             begin
               repeat
                 inppu.getdatabuf(buffer^,bufsize,l);
                 outppu.putdata(buffer^,l);
               until l<bufsize;
               outppu.writeentry(b);
             end;
           end; }
      end;
    { just add a new entry with the new lib }
      if MakeStatic then
       begin
         outppu.putstring('imp'+current_module.realmodulename^);
         outppu.putlongint(link_static);
         outppu.writeentry(iblinkunitstaticlibs)
       end
      else
       begin
         outppu.putstring('imp'+current_module.realmodulename^);
         outppu.putlongint(link_shared);
         outppu.writeentry(iblinkunitsharedlibs);
       end;
    { read all entries until the end and write them also to the new ppu }
      repeat
        b:=inppu.readentry;
      { don't write ibend, that's written automatically }
        if b<>ibend then
         begin
           if b=iblinkothersharedlibs then
             begin
               while not inppu.endofentry do
                 begin
                   s:=inppu.getstring;
                   m:=inppu.getlongint;

                   outppu.putstring(s);
                   outppu.putlongint(m);

                   { strip lib prefix }
                   if copy(s,1,3)='lib' then
                     delete(s,1,3);
                   ext:=ExtractFileExt(s);
                   if ext<>'' then
                     delete(s,length(s)-length(ext)+1,length(ext));

                   current_module.linkOtherSharedLibs.add(s,link_always);
                 end;
             end
           else
             repeat
               inppu.getdatabuf(buffer,sizeof(buffer),l);
               outppu.putdata(buffer,l);
             until l<sizeof(buffer);
           outppu.writeentry(b);
         end;
      until b=ibend;
    { write the last stuff and close }
      outppu.flush;
      outppu.writeheader;
      outppu.free;
      outppu := nil;
      inppu.free;
      inppu := nil;
      Result:=True;
    end;


  procedure load_packages;
    var
      i,j : longint;
      pcp: tpcppackage;
      entry,
      entryreq : ppackageentry;
      name,
      uname : string;
    begin
      if not (tf_supports_packages in target_info.flags) then
        exit;
      i:=0;
      while i<packagelist.count do
        begin
          entry:=ppackageentry(packagelist[i]);
          if assigned(entry^.package) then
            internalerror(2013053104);
          Comment(V_Info,'Loading package: '+entry^.realpkgname);
          pcp:=tpcppackage.create(entry^.realpkgname);
          pcp.loadpcp;
          entry^.package:=pcp;

          { add all required packages that are not yet part of packagelist }
          for j:=0 to pcp.requiredpackages.count-1 do
            begin
              name:=pcp.requiredpackages.NameOfIndex(j);
              uname:=upper(name);
              if not assigned(packagelist.Find(uname)) then
                begin
                  New(entryreq);
                  entryreq^.realpkgname:=name;
                  entryreq^.package:=nil;
                  entryreq^.usedunits:=0;
                  entryreq^.direct:=false;
                  packagelist.add(uname,entryreq);
                end;
            end;

          Inc(i);
        end;

      { all packages are now loaded, so we can fill in the links of the required packages }
      for i:=0 to packagelist.count-1 do
        begin
          entry:=ppackageentry(packagelist[i]);
          if not assigned(entry^.package) then
            internalerror(2015111301);
          for j:=0 to entry^.package.requiredpackages.count-1 do
            begin
              if assigned(entry^.package.requiredpackages[j]) then
                internalerror(2015111303);
              entryreq:=packagelist.find(upper(entry^.package.requiredpackages.NameOfIndex(j)));
              if not assigned(entryreq) then
                internalerror(2015111302);
              entry^.package.requiredpackages[j]:=entryreq^.package;
            end;
        end;
    end;


  procedure add_package(const name:string;ignoreduplicates:boolean;direct:boolean);
    var
      entry : ppackageentry;
      i : longint;
    begin
      for i:=0 to packagelist.count-1 do
        begin
          if packagelist.nameofindex(i)=name then
            begin
              if not ignoreduplicates then
                Message1(package_e_duplicate_package,name);
              exit;
            end;
        end;
      new(entry);
      entry^.package:=nil;
      entry^.realpkgname:=name;
      entry^.usedunits:=0;
      entry^.direct:=direct;
      packagelist.add(upper(name),entry);
    end;


  procedure add_package_unit_ref(package: tpackage);
    var
      pkgentry : ppackageentry;
    begin
      pkgentry:=ppackageentry(packagelist.find(package.packagename^));
      if not assigned(pkgentry) then
        internalerror(2015100302);
      inc(pkgentry^.usedunits);
    end;


  procedure add_package_libs(l:tlinker);
    var
      pkgentry : ppackageentry;
      i : longint;
      pkgname : tpathstr;
    begin
      if target_info.system in systems_indirect_var_imports then
        { we're using import libraries anyway }
        exit;
      for i:=0 to packagelist.count-1 do
        begin
          pkgentry:=ppackageentry(packagelist[i]);
          if pkgentry^.usedunits>0 then
            begin
              //writeln('package used: ',pkgentry^.realpkgname);
              pkgname:=pkgentry^.package.pplfilename;
              if copy(pkgname,1,length(target_info.sharedlibprefix))=target_info.sharedlibprefix then
                delete(pkgname,1,length(target_info.sharedlibprefix));
              if copy(pkgname,length(pkgname)-length(target_info.sharedlibext)+1,length(target_info.sharedlibext))=target_info.sharedlibext then
                delete(pkgname,length(pkgname)-length(target_info.sharedlibext)+1,length(target_info.sharedlibext));
              //writeln('adding library: ', pkgname);
              l.sharedlibfiles.concat(pkgname);
            end
          else
            {writeln('ignoring package: ',pkgentry^.realpkgname)};
        end;
    end;


  procedure check_for_indirect_package_usages(modules:tlinkedlist);
    var
      uu : tused_unit;
      pentry : ppackageentry;
    begin
      uu:=tused_unit(modules.first);
      while assigned(uu) do
        begin
          if assigned(uu.u.package) then
            begin
              pentry:=ppackageentry(packagelist.find(uu.u.package.packagename^));
              if not assigned(pentry) then
                internalerror(2015112304);
              if not pentry^.direct then
                Message2(package_w_unit_from_indirect_package,uu.u.realmodulename^,uu.u.package.realpackagename^);
            end;

          uu:=tused_unit(uu.Next);
        end;
    end;


  { Symbols referenced from an inlined body are not registered on the
    consumer side.

    addsymref -> tmodule.addimportedsym runs while call and load nodes are
    parsed, but an inlined body is expanded from a copy of the node tree
    already parsed in the original unit, so that registration never happens in
    the consuming module. The symbol is then missing from unitimportsyms and
    no import entry is made: the object file references it and the package
    exports it, yet the linker reports "Undefined symbol".

    Reproduction: TEncoding.GetUTF8 is inline and its body passes
    @CreateUTF8. In a consumer built against the RTL package, addsymref sees
    GETUTF8 but never CREATEUTF8 -> Undefined symbol: ...TENCODING_$__$$_CREATEUTF8...

    So when an inline routine is imported, the symbols its body reaches are
    collected as well. processimportedsyms below runs over a work list, so a
    collected symbol that is itself inline is followed into its body too.

    The fix stays inside the package machinery: addsymref and inline
    expansion on the ordinary compilation path are left unchanged. }
  function collect_inlined_refs(var n: tnode; arg: pointer): foreachnoderesult;
    var
      lst : tfpobjectlist;
      sym : tsym;
    begin
      result:=fen_true;
      lst:=tfpobjectlist(arg);
      sym:=nil;
      case n.nodetype of
        loadn:
          if assigned(tloadnode(n).symtableentry) and
             (tloadnode(n).symtableentry.typ in [procsym,staticvarsym,constsym]) then
            sym:=tsym(tloadnode(n).symtableentry);
        calln:
          if assigned(tcallnode(n).procdefinition) and
             (tcallnode(n).procdefinition.typ=procdef) and
             assigned(tprocdef(tcallnode(n).procdefinition).procsym) then
            sym:=tsym(tprocdef(tcallnode(n).procdefinition).procsym);
        else
          ;
      end;
      if assigned(sym) and (lst.indexof(sym)<0) then
        lst.add(sym);
    end;


  procedure collectinlinerefs(pd:tprocdef;work:tfpobjectlist);
    begin
      if not pd.has_inlininginfo or not assigned(pd.inlininginfo) then
        exit;
      if not assigned(pd.inlininginfo^.code) then
        exit;
      foreachnodestatic(pd.inlininginfo^.code,@collect_inlined_refs,work);
    end;


  procedure createimportlibfromexternals;
    type
      tcacheentry=record
        pkg:tpackage;
        sym:tasmsymbol;
      end;
      pcacheentry=^tcacheentry;
    var
      cache : tfphashlist;
      alreadyloaded : tfpobjectlist;
      { packaged units whose implementation-level cross-unit references have
        already been imported -- see importlocalrefprocdefs }
      handledpkgmodules : tfpobjectlist;


      function findpackagewithsym(symname:tsymstr):tcacheentry;
        var
          i,j : longint;
          pkgentry : ppackageentry;
          unitentry : pcontainedunit;
        begin
          result.sym:=nil;
          result.pkg:=nil;
          { A DLL import thunk (_$dll$kernel32$GetCurrentProcessId, see
            make_dllmangledname) belongs to the image that calls the DLL: every
            module imports the function from the DLL itself. A unit of a
            required package can list the same name among its public symbols,
            but the package does not export it, so resolving the thunk there
            made the module unloadable (STATUS_ENTRYPOINT_NOT_FOUND). }
          if (target_info.system in systems_all_windows+systems_nativent) and
             (copy(symname,1,6)='_$dll$') then
            exit;
          for i:=0 to packagelist.count-1 do
            begin
              pkgentry:=ppackageentry(packagelist[i]);
              for j:=0 to pkgentry^.package.containedmodules.count-1 do
                begin
                  unitentry:=pcontainedunit(pkgentry^.package.containedmodules[j]);
                  if not assigned(unitentry^.module) then
                    { the unit is not loaded }
                    continue;
                  result.sym:=tasmsymbol(tmodule(unitentry^.module).publicasmsyms.find(symname));
                  if assigned(result.sym) then
                    begin
                      { completely ignore other external symbols }
                      if result.sym.bind in [ab_external,ab_weak_external] then
                        begin
                          result.sym:=nil;
                          continue;
                        end;
                      { only accept global symbols of the used unit }
                      if result.sym.bind<>ab_global then
                        begin
                          result.sym:=nil;
                          result.pkg:=nil;
                        end
                      else
                        result.pkg:=pkgentry^.package;
                      exit;
                    end;
                end;
            end;
          result.sym:=nil;
          result.pkg:=nil;
        end;


    procedure processasmsyms(symlist:tfphashobjectlist);
      var
        i,j,k : longint;
        sym : tasmsymbol;
        cacheentry : pcacheentry;
        psym : tsymentry;
        pd : tprocdef;
        found : boolean;
        impname,symname : TSymStr;
        suffixidx : longint;
      begin
        for i:=0 to symlist.count-1 do
          begin
            sym:=tasmsymbol(symlist[i]);
            if not (sym.bind in [ab_external,ab_external_indirect]) then
              continue;

            { remove the indirect suffix }
            symname:=sym.name;
            if sym.bind=ab_external_indirect then
              begin
                suffixidx:=pos(suffix_indirect,symname);
                if suffixidx=length(symname)-length(suffix_indirect)+1 then
                  symname:=copy(symname,1,suffixidx-1)
                else
                  internalerror(2016062401);
              end;

            { did we already import the symbol? }
            cacheentry:=pcacheentry(cache.find(symname));
            if assigned(cacheentry) then
              continue;

            { was the symbol already imported in the previous pass? }
            found:=false;
            for j:=0 to alreadyloaded.count-1 do
              begin
                psym:=tsymentry(alreadyloaded[j]);
                case psym.typ of
                  procsym:
                    for k:=0 to tprocsym(psym).procdeflist.count-1 do
                      begin
                        pd:=tprocdef(tprocsym(psym).procdeflist[k]);
                        if pd.has_alias_name(symname) or
                            (
                              ([po_external,po_has_importdll]*pd.procoptions=[po_external,po_has_importdll]) and
                              (symname=proc_get_importname(pd))
                            ) then
                          begin
                            found:=true;
                            break;
                          end;
                      end;
                  staticvarsym:
                    if tstaticvarsym(psym).mangledname=symname then
                      found:=true;
                  constsym:
                    begin
                      if not (tconstsym(psym).consttyp in [constresourcestring,constwresourcestring]) then
                        internalerror(2016072202);
                      if make_mangledname('RESSTR',psym.owner,psym.name)=symname then
                        found:=true;
                    end;
                  else
                    internalerror(2014101003);
                end;
                if found then
                  break;
              end;
            if found then begin
              { add a dummy entry }
              new(cacheentry);
              cacheentry^.pkg:=nil;
              cacheentry^.sym:=sym;
              cache.add(symname,cacheentry);
              continue;
            end;

            new(cacheentry);
            cacheentry^:=findpackagewithsym(symname);
            cache.add(symname,cacheentry);

            { use cacheentry^.sym instead of sym, because for the later typ
              is always at_none in case of an external symbol }
            if assigned(cacheentry^.pkg) then
              begin
                impname:=symname;
                if cacheentry^.sym.typ=AT_DATA then
                  { import as the $indirect symbol if it as a variable }
                  impname:=symname+suffix_indirect;
                current_module.addexternalimport(cacheentry^.pkg.pplfilename,symname,impname,0,cacheentry^.sym.typ=at_data,false);
              end;
          end;
      end;


    procedure import_proc_symbol(pd:tprocdef;pkg:tpackage);
      var
        item : TCmdStrListItem;
      begin
        item := TCmdStrListItem(pd.aliasnames.first);
        if not assigned(item) then
          { at least import the mangled name }
          current_module.addexternalimport(pkg.pplfilename,pd.mangledname,pd.mangledname,0,false,false);
        while assigned(item) do
          begin
            current_module.addexternalimport(pkg.pplfilename,item.str,item.str,0,false,false);
            item := TCmdStrListItem(item.next);
          end;
       end;


    { processimportedsyms below reaches a packaged unit's routines through the
      procsym recorded at the use site, and walks that procsym's procdeflist.
      An overload declared only in the implementation is attached to the
      *interface* procsym, and symsym.tprocsym.buildderef persists only the
      procdefs owned by that procsym's own symtable -- so it is not in the list
      and no import entry is generated for it. The reference itself is real: it
      comes from expanding an inlined interface routine that calls it, which is
      also why the compiler marked the def df_has_global_ref and the package
      exports it.

      So once per packaged unit we reach, import its implementation-level
      procdefs that carry that mark. The set is small (a handful per unit) and
      is exactly what exportprocsym on the package side lets out, so this adds
      no import that the package cannot satisfy. }
    procedure importlocalrefprocdefs(m:tmodule;pkg:tpackage);
      var
        i : longint;
        def : tdef;
      begin
        if not assigned(m.localsymtable) then
          exit;
        for i:=0 to m.localsymtable.DefList.Count-1 do
          begin
            def:=tdef(m.localsymtable.DefList[i]);
            { deflist may hold NIL entries }
            if not assigned(def) or (def.typ<>procdef) then
              continue;
            if not (df_has_global_ref in def.defoptions) then
              continue;
            { a routine of a DLL (GetCurrentProcessId in the system unit's
              implementation): imported from the DLL by every module, as
              processimportedsyms does for interface ones. The package does
              not export the import thunk; importing it from there made the
              module unloadable (STATUS_ENTRYPOINT_NOT_FOUND). }
            if [po_external,po_has_importdll]*tprocdef(def).procoptions=[po_external,po_has_importdll] then
              import_external_proc(tprocdef(def))
            else
              import_proc_symbol(tprocdef(def),pkg);
          end;
      end;


    procedure processimportedsyms(syms:tfpobjectlist);
      { syms is a list of tunitimportsym }
      var
        i,j,k,l : longint;
        pkgentry : ppackageentry;
        sym : TSymEntry;
        srsymtable : tsymtable;
        module : tmodule;
        unitentry : pcontainedunit;
        name : tsymstr;
        pd : tprocdef;
        work : tfpobjectlist;
      begin
        { Run over a work list, so that symbols collected from inlined bodies
          can be appended and get the same treatment (see collect_inlined_refs). }
        work:=tfpobjectlist.create(false);
        try
        for i:=0 to syms.count-1 do
          work.add(tunitimportsym(syms[i]).sym);
        i:=0;
        while i<work.count do
          begin
            sym:=tsym(work[i]);
            inc(i);
            if not (sym.typ in [staticvarsym,procsym,constsym]) or
                (
                  (sym.typ=constsym) and
                  not (tconstsym(sym).consttyp in [constresourcestring,constwresourcestring])
                ) then
              continue;
            if alreadyloaded.indexof(sym)>=0 then
              continue;
            { determine the unit of the symbol }
            srsymtable:=sym.owner;
            while not (srsymtable.symtabletype in [staticsymtable,globalsymtable]) do
              srsymtable:=srsymtable.defowner.owner;
            module:=tmodule(loaded_units.first);
            while assigned(module) do
              begin
                if (module.globalsymtable=srsymtable) or (module.localsymtable=srsymtable) then
                  break;
                module:=tmodule(module.next);
              end;
            if not assigned(module) then
              internalerror(2014101001);
            if (uf_in_library and module.headerflags)=0 then
              { unit is not part of a package, so no need to handle it }
              continue;
            { loaded by a package? }
            for j:=0 to packagelist.count-1 do
              begin
                pkgentry:=ppackageentry(packagelist[j]);
                for k:=0 to pkgentry^.package.containedmodules.count-1 do
                  begin
                    unitentry:=pcontainedunit(pkgentry^.package.containedmodules[k]);
                    if unitentry^.module=module then
                      begin
                        if handledpkgmodules.indexof(module)<0 then
                          begin
                            handledpkgmodules.add(module);
                            importlocalrefprocdefs(module,pkgentry^.package);
                          end;
                        case sym.typ of
                          constsym:
                            begin
                              if not (tconstsym(sym).consttyp in [constresourcestring,constwresourcestring]) then
                                internalerror(2016072201);
                              name:=make_mangledname('RESSTR',sym.owner,sym.name);
                              current_module.addexternalimport(pkgentry^.package.pplfilename,name,name+suffix_indirect,0,true,false);
                            end;
                          staticvarsym:
                            begin
                              name:=tstaticvarsym(sym).mangledname;
                              current_module.addexternalimport(pkgentry^.package.pplfilename,name,name+suffix_indirect,0,true,false);
                            end;
                          procsym:
                            begin
                              for l:=0 to tprocsym(sym).procdeflist.count-1 do
                                begin
                                  pd:=tprocdef(tprocsym(sym).procdeflist[l]);
                                  if [po_external,po_has_importdll]*pd.procoptions=[po_external,po_has_importdll] then
                                    { if we use an external procedure of another unit we
                                      need to import it ourselves from the correct library }
                                    import_external_proc(pd)
                                  else
                                    import_proc_symbol(pd,pkgentry^.package);
                                  { for an inline routine, also collect what its body reaches }
                                  collectinlinerefs(pd,work);
                                end;
                            end;
                          else
                            internalerror(2014101002);
                        end;
                        alreadyloaded.add(sym);
                      end;
                  end;
              end;
          end;
        finally
          work.free;
        end;
      end;


    var
      module : tmodule;
      i : longint;
    begin
      cache:=tfphashlist.create;
      { check each external asm symbol of each unit of the package whether it is
        contained in the unit of a loaded package (and thus an import entry
        is needed) }
      alreadyloaded:=tfpobjectlist.create(false);
      handledpkgmodules:=tfpobjectlist.create(false);

      { first pass to find all symbols that were not loaded by asm name }
      module:=tmodule(loaded_units.first);
      while assigned(module) do
        begin
          if not assigned(module.package) then
            processimportedsyms(module.unitimportsyms);
          module:=tmodule(module.next);
        end;

      { second pass to find all symbols that were loaded by asm name }
      module:=tmodule(loaded_units.first);
      while assigned(module) do
        begin
          if not assigned(module.package) then
            processasmsyms(module.externasmsyms);
          module:=tmodule(module.next);
        end;

      alreadyloaded.free;
      alreadyloaded := nil;
      handledpkgmodules.free;
      handledpkgmodules := nil;
      for i:=0 to cache.count-1 do
        dispose(pcacheentry(cache[i]));
      cache.free;
      cache := nil;
    end;


end.

