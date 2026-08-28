{
    This file is part of the Free Pascal run time library.
    Copyright (c) 1999-2000 by Michael Van Canneyt
    member of the Free Pascal development team

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}

{ Run-Time type information routines }

function RTTIRecordInfoInit(typeInfo: Pointer): PRecordInfoInit; inline;
begin
  { find init table and management operators }
  result:=aligntoqword(typeInfo+2+PByte(typeInfo)[1]);

  { check terminator, maybe we are already in init table }
  if Assigned(result^.Terminator) then
  begin
    { point to more optimal initrtti }
    result:=PRecordInfoFull(result)^.InitTable;
    { and point to management operators in our init table }
    result:=aligntoqword(pointer(result)+2+PByte(result)[1]);
  end
end;

const
  RTTISpecialSize = 49;
  RTTIManagedSizes: array[TTypeKind] of uint8 = { 0 — unmanaged, RTTISpecialSize — special (array/record/object), otherwise manBuiltin of that size. }
  (
    {tkUnknown} 0, {tkInteger} 0, {tkChar} 0, {tkEnumeration} 0, {tkFloat} 0,
    {tkSet} 0, {tkMethod} 0, {tkSString} 0, {tkLString} 0, {tkAString} sizeof(pointer),
    {tkWString} sizeof(pointer), {tkVariant} {$ifdef FPC_HAS_FEATURE_VARIANTS} sizeof(TVarData) {$else} 0 {$endif}, {tkArray} RTTISpecialSize, {tkRecord} RTTISpecialSize, {tkInterface} sizeof(pointer),
    {tkClass} 0, {tkObject} RTTISpecialSize, {tkWChar} 0, {tkBool} 0, {tkInt64} 0, {tkQWord} 0,
    {tkDynArray} sizeof(pointer), {tkInterfaceRaw} 0, {tkProcVar} 0, {tkUString} sizeof(pointer), {tkUChar} 0,
    {tkHelper} 0, {tkFile} 0, {tkClassRef} 0, {tkPointer} 0
  );

{ onlyCustomOps = false: returns true if the type requires any management regarding op.
  onlyCustomOps = true: returns true if the type has custom op, used in dynarr.inc to avoid initialization of zeroed memory. }
function RTTIManagementAndSize(typeInfo: Pointer; op: TRTTIRecOpType; out size: SizeInt; onlyCustomOps: boolean): boolean;
var
  ri: PRecordInfoInit;
  elem: PRecordElement;
  elemCount,sample,_size: SizeInt;
begin
  sample:=RTTIManagedSizes[PTypeKind(typeinfo)^];
  size:=sample;
  if sample<>RTTISpecialSize then
    result:=not onlyCustomOps and (sample<>0)
  else if PTypeKind(typeinfo)^=tkArray then
    begin
      typeInfo:=aligntoqword(typeInfo+2+PByte(typeInfo)[1]);
      size:=PArrayInfo(typeInfo)^.Size;
      result:=RTTIManagementAndSize(PArrayInfo(typeInfo)^.ElInfo^, op, _size, onlyCustomOps);
    end
  else {tkObject, tkRecord}
    begin
      ri:=RTTIRecordInfoInit(typeInfo);
      size:=ri^.Size;
      result:=Assigned(ri^.RecordOp) and Assigned(ri^.RecordOp^.Ops[op]);
      if result then
        exit;
      elem:=AlignTypeData(Pointer(@ri^.Count)+SizeOf(ri^.Count));
      for elemCount:=ri^.Count downto 1 do
        begin
          sample:=RTTIManagedSizes[PTypeKind(elem^.TypeInfo^)^]; { Avoid recursive call for simple fields. }
          result:=not onlyCustomOps and (sample<>0); { And generally speculate simple field. }
          if sample=RTTISpecialSize then
            result:=RTTIManagementAndSize(elem^.TypeInfo^, op, _size, onlyCustomOps);
          if result then
            exit;
          inc(elem);
        end;
    end;
end;

procedure FinalizeRecordFields(Data:Pointer;Ri:PRecordInfoInit);
var
  i : longint;
  Re : PRecordElement;
begin
  Re:=AlignTypeData(Pointer(@Ri^.Count)+SizeOf(Ri^.Count));
  Inc(Re,Ri^.Count);
  for i:=Ri^.Count downto 1 Do
    begin
      Dec(Re);
      int_finalize(Data+Re^.Offset,Re^.TypeInfo^);
    end;
end;

procedure AddRefRecordFields(Data:Pointer;Ri:PRecordInfoInit);
var
  i : longint;
  Re : PRecordElement;
begin
  Re:=AlignTypeData(Pointer(@Ri^.Count)+SizeOf(Ri^.Count));
  for i:=Ri^.Count downto 1 Do
    begin
      int_addref(Data+Re^.Offset,Re^.TypeInfo^);
      Inc(Re);
    end;
end;

function RTTIRecordMopInitTable(ti: Pointer): PRTTIRecordOpOffsetTable;
begin
  ti:=aligntoqword(ti+2+PByte(ti)[1]);
  Result:=PRecordInfoInit(ti)^.InitRecordOpTable;
end;

procedure InitializeRecord(Data : pointer;Ri : PRecordInfoInit); forward;

const
  RTTIFlattenInitializePointer = 0;
  RTTIFlattenInitialize: array[TTypeKind] of uint8 =
  ( { 0: pointer, 1: record, 2: array, 3: variant, 255: unmanaged. }
    {tkUnknown} 255, {tkInteger} 255, {tkChar} 255, {tkEnumeration} 255, {tkFloat} 255,
    {tkSet} 255, {tkMethod} 255, {tkSString} 255, {tkLString} 255, {tkAString} 0,
    {tkWString} 0, {tkVariant} 3, {tkArray} 2, {tkRecord} 1, {tkInterface} 0,
    {tkClass} 255, {tkObject} 1, {tkWChar} 255, {tkBool} 255, {tkInt64} 255, {tkQWord} 255,
    {tkDynArray} 0, {tkInterfaceRaw} 255, {tkProcVar} 255, {tkUString} 0, {tkUChar} 255,
    {tkHelper} 255, {tkFile} 255, {tkClassRef} 255, {tkPointer} 255
  );

procedure InlinedInitialize(Data,TypeInfo : pointer); inline; { Should come before InitializeRecord for inlining. }
var
  ri: PRecordInfoInit;
begin
  case cardinal(RTTIFlattenInitialize[PTypeKind(TypeInfo)^]) of
    RTTIFlattenInitializePointer: { pointer }
      PPointer(Data)^:=Nil;
    1: { record }
      InitializeRecord(Data,RTTIRecordInfoInit(TypeInfo));
    2: { array }
      with PArrayInfo(aligntoqword(typeInfo+2+PByte(typeInfo)[1]))^ do
        int_InitializeArray(data,ElInfo^,ElCount);
{$ifdef FPC_HAS_FEATURE_VARIANTS}
    3: { variant }
      variant_init(PVarData(Data)^);
{$endif FPC_HAS_FEATURE_VARIANTS}
  end;
end;

procedure InitializeRecord(Data : pointer;Ri : PRecordInfoInit);
var
  initialized : SizeInt;
  first,re : PRecordElement;
begin
  first:=AlignTypeData(Pointer(@Ri^.Count)+SizeOf(Ri^.Count));
  re:=first;
  initialized:=0;
  try
    while initialized<Ri^.Count do
      begin
        InlinedInitialize(Data+re^.Offset,re^.TypeInfo^);
        inc(initialized);
        inc(re);
      end;
    if Assigned(Ri^.RecordOp) and Assigned(Ri^.RecordOp^.Initialize) then
      Ri^.RecordOp^.Initialize(Data);
  except
    { This initializer owns every automatically constructed field. Whether a
      later field's Initialize or the record's own custom Initialize raised,
      the fully constructed prefix is finalized in reverse order: a failing
      custom Initialize owns only its own partial state, never the fields
      built by the RTL before it ran. The field whose Initialize raised is
      not finalized, and the record's custom Finalize is not run - its
      Initialize never completed. The exception frame is table-driven on
      x86-64, so the fully initialized path pays no branch for this. }
    while initialized>0 do
      begin
        dec(initialized);
        int_finalize(Data+first[initialized].Offset,first[initialized].TypeInfo^);
      end;
    raise;
  end;
end;

Procedure fpc_Initialize (Data,TypeInfo : pointer);[Public,Alias : 'FPC_INITIALIZE'];  compilerproc;
begin
  InlinedInitialize(Data,TypeInfo);
end;


Procedure fpc_finalize (Data,TypeInfo: Pointer);[Public,Alias : 'FPC_FINALIZE'];  compilerproc;
var
  ri: PRecordInfoInit;
begin
  case PTypeKind(TypeInfo)^ of
{$ifdef FPC_HAS_FEATURE_ANSISTRINGS}
    tkAstring :
      fpc_AnsiStr_Decr_Ref(PPointer(Data)^);
{$endif FPC_HAS_FEATURE_ANSISTRINGS}
{$ifdef FPC_HAS_FEATURE_WIDESTRINGS}
    tkUstring :
      fpc_UnicodeStr_Decr_Ref(PPointer(Data)^);
  {$ifndef FPC_WIDESTRING_EQUAL_UNICODESTRING}
    tkWstring :
      fpc_WideStr_Decr_Ref(PPointer(Data)^);
  {$endif FPC_WIDESTRING_EQUAL_UNICODESTRING}
{$endif FPC_HAS_FEATURE_WIDESTRINGS}
    tkArray :
      with PArrayInfo(aligntoqword(typeInfo+2+PByte(typeInfo)[1]))^ do
        int_FinalizeArray(data,ElInfo^,ElCount);
{$ifdef FPC_HAS_FEATURE_OBJECTS}
    tkObject,
{$endif FPC_HAS_FEATURE_OBJECTS}
    tkRecord:
      begin
        ri:=RTTIRecordInfoInit(typeinfo);
        if Assigned(ri^.recordop) and Assigned(ri^.recordop^.Finalize) then
          ri^.recordop^.Finalize(data);
        FinalizeRecordFields(data,ri);
      end;
{$ifdef FPC_HAS_FEATURE_CLASSES}
    tkInterface:
      Intf_Decr_Ref(PPointer(Data)^);
{$endif FPC_HAS_FEATURE_CLASSES}
{$ifdef FPC_HAS_FEATURE_DYNARRAYS}
    tkDynArray:
      fpc_dynarray_clear(PPointer(Data)^,TypeInfo);
{$endif FPC_HAS_FEATURE_DYNARRAYS}
{$ifdef FPC_HAS_FEATURE_VARIANTS}
    tkVariant:
      variant_clear(PVarData(Data)^);
{$endif FPC_HAS_FEATURE_VARIANTS}
  end;
end;


Procedure fpc_Addref (Data,TypeInfo : Pointer); [Public,alias : 'FPC_ADDREF'];  compilerproc;
var
  ri: PRecordInfoInit;
begin
  case PTypeKind(TypeInfo)^ of
{$ifdef FPC_HAS_FEATURE_ANSISTRINGS}
    tkAstring :
      fpc_AnsiStr_Incr_Ref(PPointer(Data)^);
{$endif FPC_HAS_FEATURE_ANSISTRINGS}
{$ifdef FPC_HAS_FEATURE_WIDESTRINGS}
  {$ifndef FPC_WIDESTRING_EQUAL_UNICODESTRING}
    tkWstring :
      fpc_WideStr_Incr_Ref(PPointer(Data)^);
  {$endif FPC_WIDESTRING_EQUAL_UNICODESTRING}
    tkUstring :
      fpc_UnicodeStr_Incr_Ref(PPointer(Data)^);
{$endif FPC_HAS_FEATURE_WIDESTRINGS}
    tkArray :
      with PArrayInfo(aligntoqword(typeInfo+2+PByte(typeInfo)[1]))^ do
        int_AddRefArray(data,ElInfo^,ElCount);
{$ifdef FPC_HAS_FEATURE_OBJECTS}
    tkobject,
{$endif FPC_HAS_FEATURE_OBJECTS}
    tkrecord :
      begin
        ri:=RTTIRecordInfoInit(typeinfo);
        AddRefRecordFields(data,ri);
        if Assigned(ri^.recordop) and Assigned(ri^.recordop^.AddRef) then
          ri^.recordop^.AddRef(Data);
      end;
{$ifdef FPC_HAS_FEATURE_DYNARRAYS}
    tkDynArray:
      fpc_dynarray_incr_ref(PPointer(Data)^);
{$endif FPC_HAS_FEATURE_DYNARRAYS}
{$ifdef FPC_HAS_FEATURE_CLASSES}
    tkInterface:
      Intf_Incr_Ref(PPointer(Data)^);
{$endif FPC_HAS_FEATURE_CLASSES}
{$ifdef FPC_HAS_FEATURE_VARIANTS}
    tkVariant:
      variant_addref(pvardata(Data)^);
{$endif FPC_HAS_FEATURE_DYNARRAYS}
  end;
end;


Function fpc_Copy (Src, Dest, TypeInfo : Pointer) : SizeInt;[Public,alias : 'FPC_COPY']; compilerproc;
var
  copiedsize,
  expectedoffset,
  EleCount,
  offset,
  i: SizeInt;
  Temp,
  info: pointer;
begin
  result:=sizeof(pointer);
  case PTypeKind(TypeInfo)^ of
{$ifdef FPC_HAS_FEATURE_ANSISTRINGS}
    tkAstring:
      fpc_AnsiStr_Assign(PPointer(Dest)^,PPointer(Src)^);
{$endif FPC_HAS_FEATURE_ANSISTRINGS}
{$ifdef FPC_HAS_FEATURE_WIDESTRINGS}
  {$ifndef FPC_WIDESTRING_EQUAL_UNICODESTRING}
    tkWstring:
      fpc_WideStr_Assign(PPointer(Dest)^,PPointer(Src)^);
  {$endif FPC_WIDESTRING_EQUAL_UNICODESTRING}
    tkUstring:
      fpc_UnicodeStr_Assign(PPointer(Dest)^,PPointer(Src)^);
{$endif FPC_HAS_FEATURE_WIDESTRINGS}
    tkArray:
      begin
        Temp:=aligntoqword(typeInfo+2+PByte(typeInfo)[1]);
        Result:=PArrayInfo(Temp)^.Size;
        EleCount:=PArrayInfo(Temp)^.ElCount;
        { no elements to process => exit }
        if EleCount = 0 then
          Exit;
        Info:=PArrayInfo(Temp)^.ElInfo^;
        copiedsize:=Result div EleCount;
        Offset:=0;
        { Process elements }
        for I:=1 to EleCount do
          begin
            int_Copy(Src+Offset,Dest+Offset,Info);
            inc(Offset,copiedsize);
          end;
      end;
{$ifdef FPC_HAS_FEATURE_OBJECTS}
    tkobject,
{$endif FPC_HAS_FEATURE_OBJECTS}
    tkrecord:
      begin
        Temp:=RTTIRecordInfoInit(typeinfo);
        Result:=PRecordInfoInit(Temp)^.Size;
        if Assigned(PRecordInfoInit(Temp)^.recordop) and Assigned(PRecordInfoInit(Temp)^.recordop^.Copy) then
          PRecordInfoInit(Temp)^.recordop^.Copy(Src,Dest)
        else
          begin
            EleCount:=PRecordInfoInit(Temp)^.Count;
            { Get element info, hacky, but what else can we do? }
            Temp:=AlignTypeData(Pointer(@PRecordInfoInit(Temp)^.Count)+SizeOf(PRecordInfoInit(Temp)^.Count));
            expectedoffset:=0;
            { Process elements with rtti }
            for i:=1 to EleCount Do
              begin
                Offset:=PRecordElement(Temp)^.Offset;
                if Offset>expectedoffset then
                  move((Src+expectedoffset)^,(Dest+expectedoffset)^,Offset-expectedoffset);
                expectedoffset:=Offset+int_Copy(Src+Offset,Dest+Offset,PRecordElement(Temp)^.TypeInfo^);
                Inc(PRecordElement(Temp));
              end;
            { elements remaining? }
            if result>expectedoffset then
              move((Src+expectedoffset)^,(Dest+expectedoffset)^,Result-expectedoffset);
          end;
      end;
{$ifdef FPC_HAS_FEATURE_DYNARRAYS}
    tkDynArray:
      fpc_dynarray_assign(PPointer(Dest)^,PPointer(Src)^,typeinfo);
{$endif FPC_HAS_FEATURE_DYNARRAYS}
{$ifdef FPC_HAS_FEATURE_CLASSES}
    tkInterface:
      fpc_intf_assign(PPointer(Dest)^,PPointer(Src)^);
{$endif FPC_HAS_FEATURE_CLASSES}
{$ifdef FPC_HAS_FEATURE_VARIANTS}
    tkVariant:
      begin
        VarCopyProc(pvardata(dest)^,pvardata(src)^);
        result:=sizeof(tvardata);
      end;
{$endif FPC_HAS_FEATURE_VARIANTS}
  end;
end;


{ For internal use by the compiler, because otherwise $x- can cause trouble. }
{ Generally disabling extended syntax checking for all compilerprocs may     }
{ have unintended side-effects                                               }
procedure fpc_Copy_proc (Src, Dest, TypeInfo : Pointer);compilerproc; inline;
begin
  int_copy(src,dest,typeinfo);
end;


{$ifdef FPC_MANAGED_MOVE}
function fpc_Copy_with_move_semantics (Src, Dest, TypeInfo : Pointer) : SizeInt;[Public,alias : 'FPC_COPY_WITH_MOVE_SEMANTICS']; compilerproc;
var
  tki : pointer;
begin
  tki:=aligntoqword(typeInfo+2+PByte(typeInfo)[1]);
  if PTypeKind(TypeInfo)^=tkArray then { Only tkArray, tkObject, tkRecord are possible, search for 'fpc_copy_proc' in compiler/nld.pas. }
    result:=PArrayInfo(tki)^.Size
  else
    result:=PRecordInfoInit(tki)^.Size;
  int_finalize(Dest,TypeInfo);
  move(src^,dest^,result);
  int_initialize(Src,TypeInfo);
end;

procedure fpc_Copy_with_move_semantics_proc (Src, Dest, TypeInfo : Pointer);compilerproc; inline;
begin
  int_Copy_with_move_semantics(src,dest,typeinfo);
end;
{$endif FPC_MANAGED_MOVE}


procedure InitializeArrayElements(data,typeinfo : pointer;count : SizeInt);
  var
    sample,size,initialized : SizeInt;
    ri : PRecordInfoInit;
  begin
    sample:=RTTIManagedSizes[PTypeKind(typeinfo)^];
    if sample<>RTTISpecialSize then
      FillChar(data^,sample*count,0)
    else if PTypeKind(typeinfo)^=tkArray then
      with PArrayInfo(aligntoqword(typeInfo+2+PByte(typeInfo)[1]))^ do
        InitializeArrayElements(data,ElInfo^,count*ElCount)
    else
      begin
        ri:=RTTIRecordInfoInit(typeinfo);
        size:=ri^.size;
        initialized:=0;
        try
          while initialized<count do
            begin
              InitializeRecord(data+size*initialized,ri);
              inc(initialized);
            end;
        except
          while initialized>0 do
            begin
              dec(initialized);
              int_finalize(data+size*initialized,typeinfo);
            end;
          raise;
        end;
      end;
  end;


procedure fpc_initialize_array(data,typeinfo : pointer;count : SizeInt); [public,alias:'FPC_INITIALIZE_ARRAY']; compilerproc;
  var
    sample,size,i : SizeInt;
    ri : PRecordInfoInit;
  begin
    sample:=RTTIManagedSizes[PTypeKind(typeinfo)^];
    if sample<>RTTISpecialSize then
      FillChar(data^,sample*count,0)
    else if PTypeKind(typeinfo)^=tkArray then
      with PArrayInfo(aligntoqword(typeInfo+2+PByte(typeInfo)[1]))^ do
        int_InitializeArray(data,ElInfo^,count*ElCount)
    else
      begin { tkRecord/tkObject. }
        ri:=RTTIRecordInfoInit(typeinfo);
        size:=ri^.size;
        if (ri^.Count>0) or Assigned(Ri^.RecordOp) then { Heuristically replaces the more expensive RTTIManagementAndSize. Can have false positives but they are harmless and won’t occur in practice. }
          if RTTIManagementAndSize(typeinfo,rotInitialize,sample,true) then
            InitializeArrayElements(data,typeinfo,count)
          else
            for i:=0 to count-1 do
              InitializeRecord(data+size*i,ri);
      end;
  end;


function SkipTrailingNils(data : PPointer;count : SizeInt) : SizeInt;
  var
    pd: PPointer;
  begin
    pd:=data+count;
    while (pd<>data) and not Assigned(pd[-1]) do
      dec(pd);
    result:=SizeUint(pointer(pd)-pointer(data)) div sizeof(pointer);
  end;


procedure fpc_finalize_array(data,typeinfo : pointer;count : SizeInt); [Public,Alias:'FPC_FINALIZE_ARRAY'];  compilerproc;
  var
    size,i : SizeInt;
  begin
    case PTypeKind(typeinfo)^ of
{$ifdef FPC_HAS_FEATURE_ANSISTRINGS}
      tkAString:
        fpc_AnsiStr_Finalize_Many(data,SkipTrailingNils(data,count));
{$endif FPC_HAS_FEATURE_ANSISTRINGS}
{$ifdef FPC_HAS_FEATURE_WIDESTRINGS}
      tkUString:
        fpc_UnicodeStr_Finalize_Many(data,SkipTrailingNils(data,count));
  {$ifndef FPC_WIDESTRING_EQUAL_UNICODESTRING}
      tkWString:
        for i:=0 to SkipTrailingNils(data,count)-1 do
          fpc_WideStr_Decr_Ref(PPointer(data)[i]);
  {$endif FPC_WIDESTRING_EQUAL_UNICODESTRING}
{$endif FPC_HAS_FEATURE_WIDESTRINGS}
{$ifdef FPC_HAS_FEATURE_DYNARRAYS}
      tkDynArray:
        for i:=0 to SkipTrailingNils(data,count)-1 do
          fpc_dynarray_clear(PPointer(data)[i],typeinfo);
{$endif FPC_HAS_FEATURE_DYNARRAYS}
{$ifdef FPC_HAS_FEATURE_CLASSES}
      tkInterface:
        for i:=0 to SkipTrailingNils(data,count)-1 do
          Intf_Decr_Ref(PPointer(data)[i]);
{$endif FPC_HAS_FEATURE_CLASSES}
    else
      if RTTIManagementAndSize(typeinfo,rotFinalize,size,false) then
        for i:=0 to count-1 do
          int_finalize(data+size*i,typeinfo);
    end;
  end;


procedure fpc_addref_array(data,typeinfo: pointer; count: SizeInt); [public,alias:'FPC_ADDREF_ARRAY']; compilerproc;
  var
    size,i : SizeInt;
  begin
    case PTypeKind(typeinfo)^ of
{$ifdef FPC_HAS_FEATURE_ANSISTRINGS}
      tkAString:
        fpc_AnsiStr_Incr_Ref_Many(data,SkipTrailingNils(data,count));
{$endif FPC_HAS_FEATURE_ANSISTRINGS}
{$ifdef FPC_HAS_FEATURE_WIDESTRINGS}
      tkUString:
        fpc_UnicodeStr_Incr_Ref_Many(data,SkipTrailingNils(data,count));
  {$ifndef FPC_WIDESTRING_EQUAL_UNICODESTRING}
      tkWString:
        for i:=0 to SkipTrailingNils(data,count)-1 do
          fpc_WideStr_Incr_Ref(PPointer(data)[i]);
  {$endif FPC_WIDESTRING_EQUAL_UNICODESTRING}
{$endif FPC_HAS_FEATURE_WIDESTRINGS}
{$ifdef FPC_HAS_FEATURE_DYNARRAYS}
      tkDynArray:
        for i:=0 to SkipTrailingNils(data,count)-1 do
          fpc_dynarray_incr_ref(PPointer(data)[i]);
{$endif FPC_HAS_FEATURE_DYNARRAYS}
{$ifdef FPC_HAS_FEATURE_CLASSES}
      tkInterface:
        for i:=0 to SkipTrailingNils(data,count)-1 do
          Intf_Incr_Ref(PPointer(data)[i]);
{$endif FPC_HAS_FEATURE_CLASSES}
    else
      if RTTIManagementAndSize(typeinfo,rotAddRef,size,false) then
        for i:=0 to count-1 do
          int_addref(data+size*i,typeinfo);
    end;
  end;

class operator TDelphiCopyGuard.Initialize(var g: TDelphiCopyGuard);
begin
  g.Data:=nil;
  g.Flag:=nil;
  g.TI:=nil;
end;

class operator TDelphiCopyGuard.Finalize(var g: TDelphiCopyGuard);
begin
  if Assigned(g.Flag) and (PSizeUInt(g.Flag)^<>0) then
    begin
      PSizeUInt(g.Flag)^:=0;
      { self-disarm before the user's Finalize: the guard slot may be
        reused by the temp allocator, and its reuse-finalize must not see
        stale pointers }
      g.Flag:=nil;
      int_finalize(g.Data,g.TI);
    end
  else
    g.Flag:=nil;
end;

{ Finalizes a compiler-constructed value that carries an ownership flag
  word behind its data (a Delphi-Assign parameter copy, or an inlined
  custom-Initialize local), and clears the flag. The flag makes ownership
  exact between several potential finalizers - the callee's epilogue and
  unwind funclet, the caller's guard, an inline frame's cleanup block: the
  first one to run finalizes, every later one skips, and a value whose
  Initialize never completed (flag still 0) is not touched at all. The
  flag offset is the value's size aligned up to a flag word - every side
  derives it from the same RTTI. }
procedure fpc_delphi_finalize_copy(data,typeinfo : pointer); [public,alias:'FPC_DELPHI_FINALIZE_COPY']; compilerproc;
  var
    size : SizeInt;
    flag : PSizeUInt;
  begin
    if PTypeKind(typeinfo)^=tkArray then
      size:=PArrayInfo(aligntoqword(typeinfo+2+PByte(typeinfo)[1]))^.Size
    else
      size:=PRecordInfoInit(RTTIRecordInfoInit(typeinfo))^.Size;
    flag:=PSizeUInt(data+((size+sizeof(SizeUInt)-1) and not(sizeof(SizeUInt)-1)));
    if flag^<>0 then
      begin
        flag^:=0;
        int_finalize(data,typeinfo);
      end;
  end;

{ Callee-side copy of an open array of records with a Delphi Assign (Copy)
  operator. The helper owns the whole construction: it allocates the raw
  buffer, initializes every destination element (a mid-phase raise
  finalizes the initialized prefix - int_InitializeArray owns that
  contract) and runs the user's operator element by element. On any raise
  the constructed content is finalized and the raw buffer is released, so
  no resource is left without an owner; ownership transfers to the callee
  only through a successful return. This is a deliberate stronger contract
  than DCC64, which finalizes nothing of the copy. }
function fpc_delphi_copy_openarray(src,typeinfo : pointer;count : SizeInt;alignment : SizeUInt) : pointer; [public,alias:'FPC_DELPHI_COPY_OPENARRAY']; compilerproc;
  var
    size,i : SizeInt;
    allocsize : SizeUInt;
    constructed : boolean;
  begin
    { Only tkArray (a static-array aggregate) and tkRecord/tkObject reach
      this helper, see is_delphi_assign_record in the compiler. }
    if PTypeKind(typeinfo)^=tkArray then
      size:=PArrayInfo(aligntoqword(typeinfo+2+PByte(typeinfo)[1]))^.Size
    else
      size:=PRecordInfoInit(RTTIRecordInfoInit(typeinfo))^.Size;
    if count<=0 then
      exit(nil);
    if (size<=0) or (SizeUInt(count)>High(SizeUInt) div SizeUInt(size)) then
      RunError(203);
    allocsize:=SizeUInt(size)*SizeUInt(count);
    if alignment<sizeof(pointer) then
      alignment:=sizeof(pointer);
    if (alignment and (alignment-1))<>0 then
      RunError(203);
    result:=AllocMemAligned(allocsize,alignment);
    if not assigned(result) then
      RunError(203);
    constructed:=false;
    try
      int_InitializeArray(result,typeinfo,count);
      constructed:=true;
      for i:=0 to count-1 do
        int_copy(src+size*i,result+size*i,typeinfo);
    except
      try
        if constructed then
          int_FinalizeArray(result,typeinfo,count);
      finally
        FreeMemAligned(result);
      end;
      raise;
    end;
  end;


{ Successful fpc_delphi_copy_openarray calls transfer an explicitly aligned
  carrier to the callee.  Keep its release paired with the allocator above;
  ordinary open-array value copies continue to use fpc_freemem. }
procedure fpc_delphi_free_openarray(data : pointer); [public,alias:'FPC_DELPHI_FREE_OPENARRAY']; compilerproc;
  begin
    FreeMemAligned(data);
  end;

{$ifdef FPC_HAS_FEATURE_HEAP}
{ Replace an initialized static array with a fresh Default(T) value.

  The temporary lives on the heap rather than the caller's stack: a static
  array can be arbitrarily large, and its element type may require stricter
  alignment than a byte-array compiler temp provides.  Initialize the whole
  temporary before touching Dest.  Ownership then moves element by element:
  even if an old element's Finalize raises after destroying itself, its fresh
  replacement is installed by the surrounding finally.  The untransferred
  temporary tail remains owned by this helper and is finalized before storage
  is released. }
procedure fpc_assign_default_array(dest,typeinfo : pointer;size,alignment : SizeUInt); [public,alias:'FPC_ASSIGN_DEFAULT_ARRAY']; compilerproc;
  var
    ainfo : PArrayInfo;
    temp,eltype : pointer;
    allocsize : SizeUInt;
    count,elsize,done : SizeInt;
  begin
    if alignment<sizeof(pointer) then
      alignment:=sizeof(pointer);
    allocsize:=size+alignment+sizeof(pointer);
    if ((alignment and (alignment-1))<>0) or
       (allocsize<size) or
       (allocsize<alignment) then
      RunError(203);
    ainfo:=PArrayInfo(aligntoqword(typeInfo+2+PByte(typeInfo)[1]));
    count:=ainfo^.ElCount;
    if (count<=0) or (ainfo^.Size<=0) or (SizeUInt(ainfo^.Size)<>size) then
      RunError(203);
    if ainfo^.Size mod count<>0 then
      RunError(203);
    elsize:=ainfo^.Size div count;
    eltype:=ainfo^.ElInfo^;
    { Default(T) starts as an all-zero value.  This matters even when the
      element has Assign but no Initialize: int_initialize then has nothing
      to call, so an uninitialised heap block would leak allocator contents
      into the language-level Default value. }
    temp:=AllocMemAligned(size,alignment);
    if not assigned(temp) then
      RunError(203);
    try
      int_initialize(temp,typeinfo);
      done:=0;
      try
        while done<count do
          begin
            try
              int_finalize(dest+done*elsize,eltype);
            finally
              move(PByte(temp+done*elsize)^,
                PByte(dest+done*elsize)^,elsize);
              inc(done);
            end;
          end;
      finally
        if done<count then
          int_FinalizeArray(temp+done*elsize,eltype,count-done);
      end;
    finally
      FreeMemAligned(temp);
    end;
  end;
{$endif FPC_HAS_FEATURE_HEAP}

{ The following two procedures are now obsolete, needed only for bootstrapping }
procedure fpc_decref (Data, TypeInfo : Pointer);[Public,alias : 'FPC_DECREF'];  compilerproc;
  begin
    int_finalize(Data,TypeInfo);
  end;

procedure fpc_decref_array(data,typeinfo: pointer; count: SizeInt); [public,alias:'FPC_DECREF_ARRAY']; compilerproc;
  begin
    int_finalizeArray(data,typeinfo,count);
  end;

procedure InitializeArray(p, typeInfo: Pointer; count: SizeInt);
  external name 'FPC_INITIALIZE_ARRAY';

procedure FinalizeArray(p, typeInfo: Pointer; count: SizeInt);
  external name 'FPC_FINALIZE_ARRAY';

procedure AddRefArray(p, typeInfo: Pointer; count: SizeInt);
  external name 'FPC_ADDREF_ARRAY';

procedure CopyArray(dest, source, typeInfo: Pointer; count: SizeInt);
  var
    i, size: SizeInt;
  begin
    if RTTIManagementAndSize(typeinfo, rotCopy, size, false) then
      for i:=0 to count-1 do
        int_Copy(source+size*i, dest+size*i, typeInfo);
  end;
