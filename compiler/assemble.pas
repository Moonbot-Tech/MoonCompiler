{
    Copyright (c) 1998-2004 by Peter Vreman

    This unit handles the assemblerfile write and assembler calls of FPC

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
{# @abstract(This unit handles the assembler file write and assembler calls of FPC)
   Handles the calls to the actual external assemblers, as well as the generation
   of object files for smart linking. Also contains the base class for writing
   the assembler statements to file.
}
unit assemble;

{$i fpcdefs.inc}

interface


    uses
      SysUtils,
      systems,globtype,globals,aasmbase,aasmtai,aasmdata,ogbase,owbase,finput;

    const
       { maximum of aasmoutput lists there will be }
       maxoutputlists = ord(high(tasmlisttype))+1;
       { buffer size for writing the .s file }
       AsmOutSize=32768*4;

    type
      TAssembler=class(TObject)
      public
      {assembler info}
        asminfo     : pasminfo;
      {filenames}
        path        : TPathStr;
        name        : string;
        AsmFileName,         { current .s and .o file }
        ObjFileName,
        ppufilename  : TPathStr;
        asmprefix    : string;
        SmartAsm     : boolean;
        SmartFilesCount,
        SmartHeaderCount : longint;
        Constructor Create(info: pasminfo; smart:boolean);virtual;
        Destructor Destroy;override;
        procedure NextSmartName(place:tcutplace);
        procedure MakeObject;virtual;abstract;
      end;

      TExternalAssembler = class;

      IExternalAssemblerOutputFileDecorator=interface
        function LinePrefix: AnsiString;
        function LinePostfix: AnsiString;
        function LineFilter(const s: AnsiString): AnsiString;
        function LineEnding(const deflineending: ShortString): ShortString;
      end;

      TExternalAssemblerOutputFile=class
      private
        fdecorator: IExternalAssemblerOutputFileDecorator;
      protected
        owner: TExternalAssembler;
      {outfile}
        AsmSize,
        AsmStartSize,
        outcnt   : longint;
        outbuf   : array[0..AsmOutSize-1] of ansichar;
        outfile  : file;
        fioerror : boolean;
        linestart: boolean;

        Procedure AsmClear;
        Procedure MaybeAddLinePrefix;
        Procedure MaybeAddLinePostfix;

        Procedure AsmWriteAnsiStringUnfiltered(const s: ansistring);
      public
        Constructor Create(_owner: TExternalAssembler);

        Procedure RemoveAsm;virtual;
        Procedure AsmFlush;

        { mark the current output as the "empty" state (i.e., it only contains
          headers/directives etc }
        Procedure MarkEmpty;
        { clears the assembler output if nothing was added since it was marked
          as empty, and returns whether it was empty }
        function ClearIfEmpty: boolean;
        { these routines will write the filtered version of their argument
          according to the current decorator }
        procedure AsmWriteFiltered(const c:ansichar);
        procedure AsmWriteFiltered(const s:string);
        procedure AsmWriteFiltered(const s:ansistring);
        procedure AsmWriteFiltered(p:pansichar; len: longint);

        {# Write a string to the assembler file }
        Procedure AsmWrite(const c:ansichar);
        Procedure AsmWrite(const s:string);
        Procedure AsmWrite(const s:ansistring);

        {# Write a string to the assembler file }
        Procedure AsmWritePChar(p:pansichar);

        {# Write a string to the assembler file followed by a new line }
        Procedure AsmWriteLn(const c:ansichar);
        Procedure AsmWriteLn(const s:string);
        Procedure AsmWriteLn(const s:ansistring);

        {# Write a new line to the assembler file }
        Procedure AsmLn; virtual;

        procedure AsmCreate(Aplace:tcutplace);
        procedure AsmClose;

        property ioerror: boolean read fioerror;
        property decorator: IExternalAssemblerOutputFileDecorator read fdecorator write fdecorator;
      end;

      {# This is the base class which should be overridden for each each
         assembler writer. It is used to actually assembler a file,
         and write the output to the assembler file.
      }
      TExternalAssembler=class(TAssembler)
      private
       { output writer }
        fwriter: TExternalAssemblerOutputFile;
        ffreewriter: boolean;

        procedure CreateSmartLinkPath(const s:TPathStr);
      protected
      {input source info}
        lastfileinfo : tfileposinfo;
        infile,
        lastinfile   : tinputfile;
      {last section type written}
        lastsectype : TAsmSectionType;
        procedure ResetSourceLines;
        procedure WriteSourceLine(hp: tailineinfo);
        procedure WriteTempalloc(hp: tai_tempalloc);
        procedure WriteRealConstAsBytes(hp: tai_realconst; const dbdir: string; do_line: boolean);
        function WriteComments(var hp: tai): boolean;
        function single2str(d : single) : string; virtual;
        function double2str(d : double) : string; virtual;
        function extended2str(e : extended) : string; virtual;
        function sleb128tostr(a : int64) : string;
        function uleb128tostr(a : qword) : string;
        Function DoPipe:boolean; virtual;

        function CreateNewAsmWriter: TExternalAssemblerOutputFile; virtual;

        {# Return true if the external assembler should run again }
        function RerunAssembler: boolean; virtual;
      public

        {# Returns the complete path and executable name of the assembler
           program.

           It first tries looking in the UTIL directory if specified,
           otherwise it searches in the free pascal binary directory, in
           the current working directory and then in the  directories
           in the $PATH environment.}
        Function  FindAssembler:string;

        {# Actually does the call to the assembler file. Returns false
           if the assembling of the file failed.}
        Function  CallAssembler(const command:string; const para:TCmdStr):Boolean;

        Function  DoAssemble:boolean;virtual;

        {# This routine should be overridden for each assembler, it is used
           to actually write the abstract assembler stream to file.}
        procedure WriteTree(p:TAsmList);virtual;

        {# This routine should be overridden for each assembler, it is used
           to actually write all the different abstract assembler streams
           by calling for each stream type, the @var(WriteTree) method.}
        procedure WriteAsmList;virtual;

        {# Constructs the command line for calling the assembler }
        function MakeCmdLine: TCmdStr; virtual;
      public
        Constructor Create(info: pasminfo; smart: boolean); override; final;
        Constructor CreateWithWriter(info: pasminfo; wr: TExternalAssemblerOutputFile; freewriter, smart: boolean); virtual;
        procedure MakeObject;override;
        destructor Destroy; override;

        property writer: TExternalAssemblerOutputFile read fwriter;
      end;
      TExternalAssemblerClass = class of TExternalAssembler;

      { TInternalAssembler }

      TInternalAssembler=class(TAssembler)
      private
{$ifdef ARM}
        { true, if thumb instructions are generated }
        Code16 : Boolean;
{$endif ARM}
        FCObjOutput : TObjOutputclass;
        FCInternalAr : TObjectWriterClass;
        { the aasmoutput lists that need to be processed }
        lists        : byte;
        list         : array[1..maxoutputlists] of TAsmList;
        { current processing }
        currlistidx  : byte;
        currlist     : TAsmList;
        { code placement: branch padding and span alignment need extra
          layout passes; layoutchanged records that a pass moved code,
          relaxfrozen stops pad changes after the pass limit }
        relaxenabled : boolean;
        relaxfrozen  : boolean;
        layoutchanged: boolean;
        { number of the layout pass before the current one (0 = none):
          span alignment reads sizes measured in that pass }
        prevlayoutpass,
        lastlayoutpass : byte;
        { statistics, reported with -vd }
        relaxpads    : longint;
        relaxforced  : longint;
        relaxpasses  : longint;
        relaxspans   : longint;
        relaxprefixes,relaxnops,relaxdeadnops,relaxtargets,relaxtargetnops : longint;
        { per pass, for the -vd trace of the relaxation }
        passpads,passchanges,passforced,passspans : longint;
        asmblockdepth: longint;
        procedure TracePass(passno:byte);
        function  FindBranchPad(padstart:tai):tai_align_abstract;
        function  BranchPadHome(padstart:tai;out loc:tai):tai_align_abstract;
        procedure ApplyBranchPad(hp:tai);
        function  PadIsDead(pad:tai):boolean;
        procedure ShiftFrom(p,upto:tai;delta:longint);
        procedure RealizePad(existing:tai_align_abstract;loc,padstart,hp:tai;total:longint);
        procedure TakeBackPrefixes(existing:tai_align_abstract;padstart,hp:tai;const window:array of tai_cpu_abstract;count:longint);
        procedure TargetPad(hp:tai_align_abstract);
        function  PrefixCapacity(padstart:tai;total:longint;owner:tai_align_abstract):longint;
        function  CollectWindow(padstart:tai;total:longint;var window:array of tai_cpu_abstract;owner:tai_align_abstract):longint;
        function  EmptyAlign(p:tai):boolean;
        function  TargetPadSize(hp:tai_align_abstract;pos:longint):longint;
        function  TargetBlock(hp:tai_align_abstract;out blocklen,pairofs,carriers:longint):boolean;
        function  BranchNopsBefore(hp:tai):longint;
        function  SimulateLoop(head:tai;loopend:int64;delta:longint;out prefixend:longint;notargets:boolean=false):longint;
        function  LoopPadBytes(head:tai;loopend:int64):longint;
        procedure MarkLoopTargets(head:tai;loopend:int64;inline:boolean);
        procedure SpanAlign(hp:tai_align_abstract);
        function  VerifyShortJumps(hp:Tai;chunk:boolean):boolean;
        procedure WriteStab(p:pansichar);
        function  MaybeNextList(var hp:Tai):boolean;
        function  SetIndirectToSymbol(hp: Tai; const indirectname: string): Boolean;
        function  TreePass0(hp:Tai):Tai;
        function  TreePass1(hp:Tai):Tai;
        function  TreePass2(hp:Tai):Tai;
        procedure writetree;
        procedure writetreesmart;
      protected
        ObjData   : TObjData;
        ObjOutput : tObjOutput;
        property CObjOutput:TObjOutputclass read FCObjOutput write FCObjOutput;
        property CInternalAr : TObjectWriterClass read FCInternalAr write FCInternalAr;
      public
        constructor Create(info: pasminfo; smart: boolean);override;
        destructor  destroy;override;
        procedure MakeObject;override;
      end;

    TAssemblerClass = class of TAssembler;

    Procedure GenerateAsm(smart:boolean);

    { get an instance of an external GNU-style assembler that is compatible
      with the current target, reusing an existing writer. Used by the LLVM
      target to write inline assembler }
    function GetExternalGnuAssemblerWithAsmInfoWriter(info: pasminfo; wr: TExternalAssemblerOutputFile): TExternalAssembler;

    procedure RegisterAssembler(const r:tasminfo;c:TAssemblerClass);


Implementation

    uses
{$ifdef hasunix}
      unix,
{$endif}
      cutils,cfileutl,
{$ifdef memdebug}
      cclasses,
{$endif memdebug}
{$ifdef OMFOBJSUPPORT}
      omfbase,
      ogomf,
{$endif OMFOBJSUPPORT}
{$if defined(cpuextended) and defined(FPC_HAS_TYPE_EXTENDED)}
{$else}
{$ifdef FPC_SOFT_FPUX80}
      sfpux80,
{$endif FPC_SOFT_FPUX80}
{$endif}
{$ifdef WASM}
      ogwasm,
{$endif WASM}
      cscript,fmodule,verbose,
      cpubase,cpuinfo,triplet,
      aasmcpu;

    var
      CAssembler : array[tasm] of TAssemblerClass;

    function fixline(const s:string):string;
     {
       return s with all leading and ending spaces and tabs removed
     }
      var
        i,j,k : integer;
      begin
        i:=length(s);
        while (i>0) and (s[i] in [#9,' ']) do
          dec(i);
        j:=1;
        while (j<i) and (s[j] in [#9,' ']) do
          inc(j);
        result := Copy(s, j, i - j + 1);
        for k:=1 to length(result) do
          if result[k] in [#0..#31,#127..#255] then
            result[k]:='.';
      end;

{*****************************************************************************
                                   TAssembler
*****************************************************************************}

    Constructor TAssembler.Create(info: pasminfo; smart: boolean);
      begin
        asminfo:=info;
      { load start values }
        AsmFileName:=current_module.AsmFilename;
        ObjFileName:=current_module.ObjFileName;
        name:=Lower(current_module.modulename^);
        path:=current_module.outputpath;
        asmprefix := current_module.asmprefix^;
        if current_module.outputpath = '' then
          ppufilename := ''
        else
          ppufilename := current_module.ppufilename;
        SmartAsm:=smart;
        SmartFilesCount:=0;
        SmartHeaderCount:=0;
        SmartLinkOFiles.Clear;
      end;


    Destructor TAssembler.Destroy;
      begin
      end;


    procedure TAssembler.NextSmartName(place:tcutplace);
      var
        s : string;
      begin
        inc(SmartFilesCount);
        if SmartFilesCount>999999 then
         Message(asmw_f_too_many_asm_files);
        case place of
          cut_begin :
            begin
              inc(SmartHeaderCount);
              s:=asmprefix+tostr(SmartHeaderCount)+'h';
            end;
          cut_normal :
            s:=asmprefix+tostr(SmartHeaderCount)+'s';
          cut_end :
            s:=asmprefix+tostr(SmartHeaderCount)+'t';
        end;
        AsmFileName:=Path+FixFileName(s+tostr(SmartFilesCount)+target_info.asmext);
        ObjFileName:=Path+FixFileName(s+tostr(SmartFilesCount)+target_info.objext);
        { insert in container so it can be cleared after the linking }
        SmartLinkOFiles.Insert(ObjFileName);
      end;




{*****************************************************************************
                                 TAssemblerOutputFile
*****************************************************************************}

    procedure TExternalAssemblerOutputFile.RemoveAsm;
      var
        g : file;
      begin
        if cs_asm_leave in current_settings.globalswitches then
         exit;
        if cs_asm_extern in current_settings.globalswitches then
         AsmRes.AddDeleteCommand(owner.AsmFileName)
        else
         begin
           assign(g,owner.AsmFileName);
           {$push} {$I-}
            erase(g);
           {$pop}
           if ioresult<>0 then;
         end;
      end;


    Procedure TExternalAssemblerOutputFile.AsmFlush;
      begin
        if outcnt>0 then
         begin
           { suppress i/o error }
           {$push} {$I-}
           BlockWrite(outfile,outbuf,outcnt);
           {$pop}
           fioerror:=fioerror or (ioresult<>0);
           outcnt:=0;
         end;
      end;

    procedure TExternalAssemblerOutputFile.MarkEmpty;
      begin
        AsmStartSize:=AsmSize
      end;


    function TExternalAssemblerOutputFile.ClearIfEmpty: boolean;
      begin
        result:=AsmSize=AsmStartSize;
        if result then
         AsmClear;
      end;


    procedure TExternalAssemblerOutputFile.AsmWriteFiltered(const c: ansichar);
      begin
        MaybeAddLinePrefix;
        AsmWriteAnsiStringUnfiltered(decorator.LineFilter(c));
      end;


    procedure TExternalAssemblerOutputFile.AsmWriteFiltered(const s: string);
      begin
        MaybeAddLinePrefix;
        AsmWriteAnsiStringUnfiltered(decorator.LineFilter(s));
      end;


    procedure TExternalAssemblerOutputFile.AsmWriteFiltered(const s: ansistring);
      begin
        MaybeAddLinePrefix;
        AsmWriteAnsiStringUnfiltered(decorator.LineFilter(s));
      end;


    procedure TExternalAssemblerOutputFile.AsmWriteFiltered(p: pansichar; len: longint);
      var
        s: ansistring;
      begin
        MaybeAddLinePrefix;
        s:='';
        setlength(s,len);
        move(p^,s[1],len);
        AsmWriteAnsiStringUnfiltered(decorator.LineFilter(s));
      end;


    Procedure TExternalAssemblerOutputFile.AsmClear;
      begin
        outcnt:=0;
      end;


    procedure TExternalAssemblerOutputFile.MaybeAddLinePrefix;
      begin
        if assigned(decorator) and
           linestart then
          begin
            AsmWriteAnsiStringUnfiltered(decorator.LinePrefix);
            linestart:=false;
          end;
      end;


    procedure TExternalAssemblerOutputFile.MaybeAddLinePostfix;
      begin
        if assigned(decorator) and
           not linestart then
          begin
            AsmWriteAnsiStringUnfiltered(decorator.LinePostfix);
            linestart:=true;
          end;
      end;


    procedure TExternalAssemblerOutputFile.AsmWriteAnsiStringUnfiltered(const s: ansistring);
      var
        StartIndex, ToWrite: longint;
      begin
        if s='' then
          exit;
        if OutCnt+length(s)>=AsmOutSize then
         AsmFlush;
        StartIndex:=1;
        ToWrite:=length(s);
        while ToWrite>AsmOutSize do
          begin
            Move(s[StartIndex],OutBuf[OutCnt],AsmOutSize);
            inc(OutCnt,AsmOutSize);
            inc(AsmSize,AsmOutSize);
            AsmFlush;
            inc(StartIndex,AsmOutSize);
            dec(ToWrite,AsmOutSize);
          end;
        Move(s[StartIndex],OutBuf[OutCnt],ToWrite);
        inc(OutCnt,ToWrite);
        inc(AsmSize,ToWrite);
      end;


    constructor TExternalAssemblerOutputFile.Create(_owner: TExternalAssembler);
      begin
        owner:=_owner;
        linestart:=true;
      end;


    Procedure TExternalAssemblerOutputFile.AsmWrite(const c: ansichar);
      begin
        if assigned(decorator) then
          AsmWriteFiltered(c)
        else
          begin
            if OutCnt+1>=AsmOutSize then
             AsmFlush;
            OutBuf[OutCnt]:=c;
            inc(OutCnt);
            inc(AsmSize);
          end;
      end;


    Procedure TExternalAssemblerOutputFile.AsmWrite(const s:string);
      begin
        if s='' then
          exit;
        if assigned(decorator) then
          AsmWriteFiltered(s)
        else
          begin
            if OutCnt+length(s)>=AsmOutSize then
             AsmFlush;
            Move(s[1],OutBuf[OutCnt],length(s));
            inc(OutCnt,length(s));
            inc(AsmSize,length(s));
          end;
      end;


    Procedure TExternalAssemblerOutputFile.AsmWrite(const s:ansistring);
      begin
        if s='' then
          exit;
        if assigned(decorator) then
          AsmWriteFiltered(s)
        else
         AsmWriteAnsiStringUnfiltered(s);
      end;


    procedure TExternalAssemblerOutputFile.AsmWriteLn(const c: ansichar);
      begin
        AsmWrite(c);
        AsmLn;
      end;


    Procedure TExternalAssemblerOutputFile.AsmWriteLn(const s:string);
      begin
        AsmWrite(s);
        AsmLn;
      end;


    Procedure TExternalAssemblerOutputFile.AsmWriteLn(const s: ansistring);
      begin
        AsmWrite(s);
        AsmLn;
      end;


    Procedure TExternalAssemblerOutputFile.AsmWritePChar(p:pansichar);
      var
        i,j : longint;
      begin
        i:=StrLen(p);
        if i=0 then
          exit;
        if assigned(decorator) then
          AsmWriteFiltered(p,i)
        else
          begin
            j:=i;
            while j>0 do
             begin
               i:=min(j,AsmOutSize);
               if OutCnt+i>=AsmOutSize then
                AsmFlush;
               Move(p[0],OutBuf[OutCnt],i);
               inc(OutCnt,i);
               inc(AsmSize,i);
               dec(j,i);
                p:=pansichar(@p[i]);
             end;
          end;
      end;


    Procedure TExternalAssemblerOutputFile.AsmLn;
      var
        newline: pshortstring;
        newlineres: shortstring;
        index: longint;
      begin
        MaybeAddLinePostfix;
        if (cs_assemble_on_target in current_settings.globalswitches) then
          newline:=@target_info.newline
        else
          newline:=@source_info.newline;
        if assigned(decorator) then
          begin
            newlineres:=decorator.LineEnding(newline^);
            newline:=@newlineres;
          end;
        if OutCnt>=AsmOutSize-length(newline^) then
         AsmFlush;
        index:=1;
        repeat
          OutBuf[OutCnt]:=newline^[index];
          inc(OutCnt);
          inc(AsmSize);
          inc(index);
        until index>length(newline^);
      end;


    procedure TExternalAssemblerOutputFile.AsmCreate(Aplace:tcutplace);
{$ifdef hasamiga}
      var
        tempFileName: TPathStr;
{$endif}
      begin
        if owner.SmartAsm then
         owner.NextSmartName(Aplace);
{$ifdef hasamiga}
        { on Amiga/MorphOS try to redirect .s files to the T: assign, which is
          for temp files, and usually (default setting) located in the RAM: drive.
          This highly improves assembling speed for complex projects like the
          compiler itself, especially on hardware with slow disk I/O.
          Consider this as a poor man's pipe on Amiga, because real pipe handling
          would be much more complex and error prone to implement. (KB) }
        if (([cs_asm_extern,cs_asm_leave,cs_assemble_on_target] * current_settings.globalswitches) = []) then
         begin
          { try to have an unique name for the .s file }
          tempFileName:=HexStr(GetProcessID shr 4,7)+ExtractFileName(owner.AsmFileName);
{$ifndef morphos}
          { old Amiga RAM: handler only allows filenames up to 30 char }
          if Length(tempFileName) < 30 then
{$endif}
          owner.AsmFileName:='T:'+tempFileName;
         end;
{$endif}
{$ifdef hasunix}
        if owner.DoPipe then
         begin
           if owner.SmartAsm then
            begin
              if (owner.SmartFilesCount<=1) then
               Message1(exec_i_assembling_smart,owner.name);
            end
           else
             Message1(exec_i_assembling_pipe,owner.AsmFileName);
           if checkverbosity(V_Executable) then
             comment(V_Executable,'Executing "'+maybequoted(owner.FindAssembler)+'" with command line "'+
               owner.MakeCmdLine+'"');
           POpen(outfile,maybequoted(owner.FindAssembler)+' '+owner.MakeCmdLine,'W');
         end
        else
{$endif}
         begin
           Assign(outfile,owner.AsmFileName);
           {$push} {$I-}
           Rewrite(outfile,1);
           {$pop}
           if ioresult<>0 then
             begin
               fioerror:=true;
               Message1(exec_d_cant_create_asmfile,owner.AsmFileName);
             end;
         end;
        outcnt:=0;
        AsmSize:=0;
        AsmStartSize:=0;
      end;


    procedure TExternalAssemblerOutputFile.AsmClose;
      var
        f : file;
        FileAge : longint;
      begin
        AsmFlush;
{$ifdef hasunix}
        if owner.DoPipe then
          begin
            if PClose(outfile) <> 0 then
              GenerateError;
          end
        else
{$endif}
         begin
         {Touch Assembler time to ppu time is there is a ppufilename}
           if owner.ppufilename<>'' then
            begin
              Assign(f,owner.ppufilename);
              {$push} {$I-}
              reset(f,1);
              {$pop}
              if ioresult=0 then
               begin
                 FileAge := FileGetDate(GetFileHandle(f));
                 close(f);
                 reset(outfile,1);
                 FileSetDate(GetFileHandle(outFile),FileAge);
               end;
            end;
           close(outfile);
         end;
      end;

{*****************************************************************************
                                 TExternalAssembler
*****************************************************************************}


    function TExternalAssembler.single2str(d : single) : string;
      var
         hs : string;
      begin
         str(d,hs);
      { replace space with + }
         if hs[1]=' ' then
          hs[1]:='+';
         single2str:='0d'+hs
      end;

    function TExternalAssembler.double2str(d : double) : string;
      var
         hs : string;
      begin
         str(d,hs);
      { replace space with + }
         if hs[1]=' ' then
          hs[1]:='+';
         double2str:='0d'+hs
      end;

    function TExternalAssembler.extended2str(e : extended) : string;
      var
         hs : string;
      begin
         str(e,hs);
      { replace space with + }
         if hs[1]=' ' then
          hs[1]:='+';
         extended2str:='0d'+hs
      end;

    function TExternalAssembler.sleb128tostr(a: int64): string;
      var
        i,len : longint;
        buf   : array[0..31] of byte;
      begin
        result:='';
        len:=EncodeSleb128(a,buf,0);
        for i:=0 to len-1 do
          begin
            if (i > 0) then
              result:=result+',';
            result:=result+tostr(buf[i]);
          end;
      end;

    function TExternalAssembler.uleb128tostr(a: qword): string;
    var
      i,len : longint;
      buf   : array[0..31] of byte;
    begin
      result:='';
      len:=EncodeUleb128(a,buf,0);
      for i:=0 to len-1 do
        begin
          if (i > 0) then
            result:=result+',';
          result:=result+tostr(buf[i]);
        end;
    end;


    Function TExternalAssembler.DoPipe:boolean;
      begin
{$ifdef hasunix}
        DoPipe:=(cs_asm_pipe in current_settings.globalswitches) and
                (([cs_asm_extern,cs_asm_leave,cs_assemble_on_target] * current_settings.globalswitches) = []) and
                ((asminfo^.id in [as_gas,as_ggas,as_darwin,as_powerpc_xcoff,as_clang_gas,as_clang_llvm,as_clang_llvm_darwin,as_solaris_as,as_clang_asdarwin]));
{$else hasunix}
        DoPipe:=false;
{$endif}
      end;


    function TExternalAssembler.CreateNewAsmWriter: TExternalAssemblerOutputFile;
      begin
        result:=TExternalAssemblerOutputFile.Create(self);
      end;


    Constructor TExternalAssembler.Create(info: pasminfo; smart: boolean);
      begin
        CreateWithWriter(info,CreateNewAsmWriter,true,smart);
      end;


    constructor TExternalAssembler.CreateWithWriter(info: pasminfo; wr: TExternalAssemblerOutputFile; freewriter,smart: boolean);
      begin
        inherited Create(info,smart);
        fwriter:=wr;
        ffreewriter:=freewriter;
        if SmartAsm then
          begin
            path:=FixPath(ChangeFileExt(AsmFileName,target_info.smartext),false);
            CreateSmartLinkPath(path);
          end;
      end;


    procedure TExternalAssembler.CreateSmartLinkPath(const s:TPathStr);

        procedure DeleteFilesWithExt(const AExt:string);
        var
          dir : TRawByteSearchRec;
        begin
          if findfirst(FixPath(s,false)+'*'+AExt,faAnyFile,dir) = 0 then
            begin
              repeat
                DeleteFile(s+source_info.dirsep+dir.name);
              until findnext(dir) <> 0;
            end;
          findclose(dir);
        end;

      var
        hs  : TPathStr;
      begin
        if PathExists(s,false) then
         begin
           { the path exists, now we clean only all the .o and .s files }
           DeleteFilesWithExt(target_info.objext);
           DeleteFilesWithExt(target_info.asmext);
         end
        else
         begin
           hs:=s;
           if hs[length(hs)] in ['/','\'] then
            delete(hs,length(hs),1);
           {$push} {$I-}
            mkdir(hs);
           {$pop}
           if ioresult<>0 then;
         end;
      end;


    var
      lastas  : byte=255;
      LastASBin : TCmdStr;
    Function TExternalAssembler.FindAssembler:string;
      var
        asfound : boolean;
        UtilExe  : string;
        asmbin : TCmdStr;
      begin
        asfound:=false;
        asmbin:=asminfo^.asmbin;
        if (af_llvm in asminfo^.flags) then
          asmbin:=asmbin+llvmutilssuffix;
        if cs_assemble_on_target in current_settings.globalswitches then
         begin
           { If assembling on target, don't add any path PM }
           FindAssembler:=utilsprefix+ChangeFileExt(asmbin,target_info.exeext);
           exit;
         end
        else
         UtilExe:=utilsprefix+ChangeFileExt(asmbin,source_info.exeext);
        if lastas<>ord(asminfo^.id) then
         begin
           lastas:=ord(asminfo^.id);
           { is an assembler passed ? }
           if utilsdirectory<>'' then
             asfound:=FindFile(UtilExe,utilsdirectory,false,LastASBin);
           if not AsFound then
             asfound:=FindExe(UtilExe,false,LastASBin);
           if (not asfound) and not(cs_asm_extern in current_settings.globalswitches) then
            begin
              Message1(exec_e_assembler_not_found,LastASBin);
              current_settings.globalswitches:=current_settings.globalswitches+[cs_asm_extern];
            end;
           if asfound then
            Message1(exec_t_using_assembler,LastASBin);
         end;
        FindAssembler:=LastASBin;
      end;


    Function TExternalAssembler.CallAssembler(const command:string; const para:TCmdStr):Boolean;
      var
        DosExitCode : Integer;
      begin
        result:=true;
        if (cs_asm_extern in current_settings.globalswitches) then
          begin
            if SmartAsm then
              AsmRes.AddAsmCommand(command,para,Name+'('+TosTr(SmartFilesCount)+')')
            else
              AsmRes.AddAsmCommand(command,para,name);
            exit;
          end;
        try
          FlushOutput;
          DosExitCode:=RequotedExecuteProcess(command,para);
          if DosExitCode<>0
          then begin
            Message1(exec_e_error_while_assembling,tostr(dosexitcode));
            result:=false;
          end;
        except on E:EOSError do
          begin
            Message1(exec_e_cant_call_assembler,tostr(E.ErrorCode));
            current_settings.globalswitches:=current_settings.globalswitches+[cs_asm_extern];
            result:=false;
          end;
        end;
      end;


    Function TExternalAssembler.DoAssemble:boolean;
      begin
        result:=true;
        if DoPipe then
         exit;
        if not(cs_asm_extern in current_settings.globalswitches) then
         begin
           if SmartAsm then
            begin
              if (SmartFilesCount<=1) then
               Message1(exec_i_assembling_smart,name);
            end
           else
           Message1(exec_i_assembling,name);
         end;

        repeat
          result:=CallAssembler(FindAssembler,MakeCmdLine)
        until not(result) or not RerunAssembler;
        if result then
          writer.RemoveAsm
        else
          GenerateError;
      end;


    function TExternalAssembler.MakeCmdLine: TCmdStr;

      function section_high_bound:longint;
        var
          alt : tasmlisttype;
        begin
          result:=0;
          for alt:=low(tasmlisttype) to high(tasmlisttype) do
            result:=result+current_asmdata.asmlists[alt].section_count;
        end;

      const
        min_big_obj_section_count = $7fff;

      begin
        result:=asminfo^.asmcmd;
        if af_llvm in target_asm.flags then
          Replace(result,'$TRIPLET',targettriplet(triplet_llvm))
{$ifdef arm}
        else if (target_info.system=system_arm_ios) then
          Replace(result,'$ARCH',lower(cputypestr[current_settings.cputype]))
{$endif arm}
        ;
        if (cs_assemble_on_target in current_settings.globalswitches) then
         begin
           Replace(result,'$ASM',maybequoted(ScriptFixFileName(AsmFileName)));
           Replace(result,'$OBJ',maybequoted(ScriptFixFileName(ObjFileName)));
         end
        else
         begin
{$ifdef hasunix}
          if DoPipe then
            if not(asminfo^.id in [as_clang_gas,as_clang_asdarwin,as_clang_llvm,as_clang_llvm_darwin]) then
              Replace(result,'$ASM','')
            else
              Replace(result,'$ASM','-')
          else
{$endif}
             Replace(result,'$ASM',maybequoted(AsmFileName));
           Replace(result,'$OBJ',maybequoted(ObjFileName));
         end;

         if (cs_create_pic in current_settings.moduleswitches) then
           Replace(result,'$PIC','-KPIC')
         else
           Replace(result,'$PIC','');

         if (cs_asm_source in current_settings.globalswitches) then
           Replace(result,'$NOWARN','')
         else
           Replace(result,'$NOWARN','-W');

         if target_info.endian=endian_little then
           Replace(result,'$ENDIAN','-mlittle')
         else
           Replace(result,'$ENDIAN','-mbig');

         { as we don't keep track of the amount of sections we created we simply
           enable Big Obj COFF files always for targets that need them }
         if (cs_asm_pre_binutils_2_25 in current_settings.globalswitches) or
            not (target_info.system in systems_all_windows+systems_nativent-[system_i8086_win16]) or
            (section_high_bound<min_big_obj_section_count) then
           Replace(result,'$BIGOBJ','')
         else
           Replace(result,'$BIGOBJ','-mbig-obj');

         Replace(result,'$EXTRAOPT',asmextraopt);
      end;


    function TExternalAssembler.RerunAssembler: boolean;
      begin
        result:=false;
      end;


    procedure TExternalAssembler.ResetSourceLines;

      procedure DoReset(f:tinputfile);
        var
          i : longint;
        begin
          if not assigned(f) then
            exit;
          for i:=0 to f.maxlinebuf-1 do
            if f.linebuf[i]<0 then
              f.linebuf[i]:=-f.linebuf[i]-1;
        end;

      begin
        DoReset(infile);
        DoReset(lastinfile);
      end;


    procedure TExternalAssembler.WriteSourceLine(hp: tailineinfo);
      var
        module : tmodule;
      begin
        { load infile }
        if (lastfileinfo.moduleindex<>hp.fileinfo.moduleindex) or
            (lastfileinfo.fileindex<>hp.fileinfo.fileindex) then
          begin
            { in case of a generic the module can be different }
            if current_module.moduleid=hp.fileinfo.moduleindex then
              module:=current_module
            else
              module:=get_module(hp.fileinfo.moduleindex);
            { during the compilation of the system unit there are cases when
              the fileinfo contains just zeros => invalid }
            if assigned(module) then
              infile:=module.sourcefiles.get_file(hp.fileinfo.fileindex)
            else
              infile:=nil;
            if assigned(infile) then
              begin
                { open only if needed !! }
                if (cs_asm_source in current_settings.globalswitches) then
                  infile.open;
              end;
            { avoid unnecessary reopens of the same file !! }
            lastfileinfo.fileindex:=hp.fileinfo.fileindex;
            lastfileinfo.moduleindex:=hp.fileinfo.moduleindex;
            { be sure to change line !! }
            lastfileinfo.line:=-1;
          end;
        { write source }
        if (cs_asm_source in current_settings.globalswitches) and
          assigned(infile) then
          begin
            if (infile<>lastinfile) then
              begin
                writer.AsmWriteLn(asminfo^.comment+'['+infile.name+']');
                if assigned(lastinfile) then
                  lastinfile.close;
              end;
            if (hp.fileinfo.line<>lastfileinfo.line) and
              (hp.fileinfo.line<infile.maxlinebuf) then
              begin
                if (hp.fileinfo.line<>0) and
                  (infile.linebuf[hp.fileinfo.line]>=0) then
                  writer.AsmWriteLn(asminfo^.comment+'['+tostr(hp.fileinfo.line)+'] '+
                  fixline(infile.GetLineStr(hp.fileinfo.line)));
                { set it to a negative value !
                  to make that is has been read already !! PM }
                if (infile.linebuf[hp.fileinfo.line]>=0) then
                  infile.linebuf[hp.fileinfo.line]:=-infile.linebuf[hp.fileinfo.line]-1;
              end;
          end;
        lastfileinfo:=hp.fileinfo;
        lastinfile:=infile;
      end;

    procedure TExternalAssembler.WriteTempalloc(hp: tai_tempalloc);
      begin
{$ifdef EXTDEBUG}
        if assigned(hp.problem) then
          writer.AsmWriteLn(asminfo^.comment+'Temp '+tostr(hp.temppos)+','+
          tostr(hp.tempsize)+' '+hp.problem^)
        else
{$endif EXTDEBUG}
          writer.AsmWriteLn(asminfo^.comment+'Temp '+tostr(hp.temppos)+','+
            tostr(hp.tempsize)+' '+tempallocstr[hp.allocation]);
      end;


    procedure TExternalAssembler.WriteRealConstAsBytes(hp: tai_realconst; const dbdir: string; do_line: boolean);
      var
        pdata: pbyte;
        index, step, swapmask, real_byte_count: longint;
        ssingle: single;
        ddouble: double;
{$ifdef FPC_COMP_IS_INT64}
        ccomp: int64;
{$else}
        ccomp: comp;
{$endif}
        comp_data_size : byte;
{$if defined(cpuextended) and defined(FPC_HAS_TYPE_EXTENDED)}
        eextended: extended;
{$else}
{$ifdef FPC_SOFT_FPUX80}
{$define USE_SOFT_FLOATX80}
        f32 : float32;
        f64 : float64;
        eextended: floatx80;
        gap_ofs_low,gap_ofs_high : byte;
        gap_index, gap_size : byte;
        has_gap : boolean;
{$endif}
{$endif cpuextended}
      begin
{$ifdef USE_SOFT_FLOATX80}
        has_gap:=false;
        gap_index:=0;
        gap_size:=0;
{$endif USE_SOFT_FLOATX80}
        if do_line then
          begin
            case tai_realconst(hp).realtyp of
              aitrealconst_s32bit:
                writer.AsmWriteLn(asminfo^.comment+'s32bit real value: '+single2str(tai_realconst(hp).value.s32val));
              aitrealconst_s64bit:
                writer.AsmWriteLn(asminfo^.comment+'s64bit real value: '+double2str(tai_realconst(hp).value.s64val));
{$if defined(cpuextended) and defined(FPC_HAS_TYPE_EXTENDED)}
              { can't write full 80 bit floating point constants yet on non-x86 }
              aitrealconst_s80bit:
                writer.AsmWriteLn(asminfo^.comment+'s80bit real value: '+extended2str(tai_realconst(hp).value.s80val));
{$else}
{$ifdef USE_SOFT_FLOATX80}
{$push}{$warn 6018 off} { Unreachable code due to compile time evaluation }
             aitrealconst_s80bit:
               begin
                      if sizeof(tai_realconst(hp).value.s80val) = sizeof(double) then
                   writer.AsmWriteLn(asminfo^.comment+'Emulated s80bit real value (on s64bit): '+double2str(tai_realconst(hp).value.s80val))
                      else if sizeof(tai_realconst(hp).value.s80val) = sizeof(single) then
                   writer.AsmWriteLn(asminfo^.comment+'Emulated s80bit real value (on s32bit): '+single2str(tai_realconst(hp).value.s80val))
                else
                      internalerror(2017091901);
                     end;
{$pop}
{$endif}
{$endif cpuextended}
              aitrealconst_s64comp:
                begin
                  writer.AsmWriteLn(asminfo^.comment+'s64comp real value: '+extended2str(tai_realconst(hp).value.s64compval));
                  comp_data_size:=sizeof(comp);
                  if (comp_data_size<>tai_realconst(hp).datasize) then
                    writer.AsmWriteLn(asminfo^.comment+'s64comp value type size is '+tostr(comp_data_size)+' but datasize is '+tostr(tai_realconst(hp).datasize));
                end
              else
                internalerror(2014050604);
            end;
          end;
        writer.AsmWrite(dbdir);
        { generic float writing code: get start address of value, then write
          byte by byte. Can't use fields directly, because e.g ts64comp is
          defined as extended on x86 }
        case tai_realconst(hp).realtyp of
          aitrealconst_s32bit:
            begin
              ssingle:=single(tai_realconst(hp).value.s32val);
              pdata:=@ssingle;
            end;
          aitrealconst_s64bit:
            begin
              ddouble:=double(tai_realconst(hp).value.s64val);
              pdata:=@ddouble;
            end;
{$if defined(cpuextended) and defined(FPC_HAS_TYPE_EXTENDED)}
          { can't write full 80 bit floating point constants yet on non-x86 }
          aitrealconst_s80bit:
            begin
              eextended:=extended(tai_realconst(hp).value.s80val);
              pdata:=@eextended;
            end;
{$else}
{$ifdef USE_SOFT_FLOATX80}
{$push}{$warn 6018 off} { Unreachable code due to compile time evaluation }
          aitrealconst_s80bit:
            begin
              if sizeof(tai_realconst(hp).value.s80val) = sizeof(double) then
                begin
                  f64:=float64(double(tai_realconst(hp).value.s80val));
                  if float64_is_signaling_nan(f64)<>0 then
                    begin
                      f64.low := 0;
                      f64.high := longword($fff80000);
                    end;
                  eextended:=float64_to_floatx80(f64);
                end
              else if sizeof(tai_realconst(hp).value.s80val) = sizeof(single) then
                begin
                  f32:=float32(single(tai_realconst(hp).value.s80val));
                  if float32_is_signaling_nan(f32)<>0 then
                    begin
                      f32 := longword($ffc00000);
                    end;
                  eextended:=float32_to_floatx80(f32);
                end
              else
                internalerror(2017091902);
              pdata:=@eextended;
              if sizeof(eextended)>10 then
                begin
                  gap_ofs_high:=(pbyte(@eextended.high) - pbyte(@eextended));
                  gap_ofs_low:=(pbyte(@eextended.low) - pbyte(@eextended));
                  if (gap_ofs_low<gap_ofs_high) then
                    begin
                      gap_index:=gap_ofs_low+sizeof(eextended.low);
                      gap_size:=gap_ofs_high-gap_index;
                    end
                  else
                    begin
                      gap_index:=gap_ofs_high+sizeof(eextended.high);
                      gap_size:=gap_ofs_low-gap_index;
                    end;
                  if source_info.endian<>target_info.endian then
                      gap_index:=gap_index+gap_size-1;
                  has_gap:=gap_size <> 0;
                end
              else
                has_gap:=false;
            end;
{$pop}
{$endif}
{$endif cpuextended}
          aitrealconst_s64comp:
            begin
{$ifdef FPC_COMP_IS_INT64}
              ccomp:=system.trunc(tai_realconst(hp).value.s64compval);
{$else}
              ccomp:=comp(tai_realconst(hp).value.s64compval);
{$endif}
              pdata:=@ccomp;
            end;
          else
            internalerror(2014051001);
        end;
        real_byte_count:=tai_realconst(hp).datasize;
        { write bytes in inverse order if source and target endianess don't
          match }
        if source_info.endian<>target_info.endian then
          begin
            { go from back to front }
{$ifdef USE_SOFT_FLOATX80}
            if has_gap then
              index:=sizeof(eextended)-1
            else
{$endif USE_SOFT_FLOATX80}
              index:=real_byte_count-1;
            step:=-1;
          end
        else
          begin
            index:=0;
            step:=1;
          end;
{$ifdef ARM}
        { ARM-specific: low and high dwords of a double may be swapped }
        if tai_realconst(hp).formatoptions=fo_hiloswapped then
          begin
            { only supported for double }
            if tai_realconst(hp).datasize<>8 then
              internalerror(2014050605);
            { switch bit of the index so that the words are written in
              the opposite order }
            swapmask:=4;
          end
        else
{$endif ARM}
          swapmask:=0;
        repeat
{$ifdef USE_SOFT_FLOATX80}
          if has_gap and (index=gap_index) then
            index:=index+step*gap_size;
{$endif USE_SOFT_FLOATX80}
          writer.AsmWrite(tostr(pdata[index xor swapmask]));
          inc(index,step);
          dec(real_byte_count);
          if real_byte_count<>0 then
            writer.AsmWrite(ansistring(','));
        until real_byte_count=0;
        { padding }
        for real_byte_count:=tai_realconst(hp).datasize+1 to tai_realconst(hp).savesize do
          writer.AsmWrite(',0');
        writer.AsmLn;
      end;


    function TExternalAssembler.WriteComments(var hp: tai): boolean;
      begin
        result:=true;
        case hp.typ of
          ait_comment :
            Begin
              writer.AsmWrite(asminfo^.comment);
              writer.AsmWritePChar(tai_comment(hp).str);
              writer.AsmLn;
            End;

          ait_regalloc :
            begin
              if (cs_asm_regalloc in current_settings.globalswitches) then
                begin
                  writer.AsmWrite(#9+asminfo^.comment+'Register ');
                  repeat
                    writer.AsmWrite(std_regname(Tai_regalloc(hp).reg));
                    if (hp.next=nil) or
                       (tai(hp.next).typ<>ait_regalloc) or
                       (tai_regalloc(hp.next).ratype<>tai_regalloc(hp).ratype) then
                      break;
                    hp:=tai(hp.next);
                    writer.AsmWrite(ansistring(','));
                  until false;
                  writer.AsmWrite(ansistring(' '));
                  writer.AsmWriteLn(regallocstr[tai_regalloc(hp).ratype]);
                end;
            end;

          ait_tempalloc :
            begin
              if (cs_asm_tempalloc in current_settings.globalswitches) then
                WriteTempalloc(tai_tempalloc(hp));
            end;

          ait_varloc:
            begin
              { ait_varloc is present here only when register allocation is not done ( -sr option ) }
              if tai_varloc(hp).newlocationhi<>NR_NO then
                writer.AsmWriteLn(asminfo^.comment+'Var '+tai_varloc(hp).varsym.realname+' located in register '+
                  std_regname(tai_varloc(hp).newlocationhi)+':'+std_regname(tai_varloc(hp).newlocation))
              else
                writer.AsmWriteLn(asminfo^.comment+'Var '+tai_varloc(hp).varsym.realname+' located in register '+
                  std_regname(tai_varloc(hp).newlocation));
            end;
          else
            result:=false;
        end;
      end;


    procedure TExternalAssembler.WriteTree(p:TAsmList);
      begin
      end;


    procedure TExternalAssembler.WriteAsmList;
      begin
      end;


    procedure TExternalAssembler.MakeObject;
      begin
        writer.AsmCreate(cut_normal);
        FillChar(lastfileinfo, sizeof(lastfileinfo), 0);
        lastfileinfo.line := -1;
        lastinfile := nil;
        lastsectype := sec_none;
        WriteAsmList;
        writer.AsmClose;
        if not(writer.ioerror) then
          DoAssemble;
      end;


    destructor TExternalAssembler.Destroy;
      begin
        if ffreewriter then
          writer.Free; // no nil needed
        inherited;
      end;


{*****************************************************************************
                                  TInternalAssembler
*****************************************************************************}

    constructor TInternalAssembler.Create(info: pasminfo; smart: boolean);
      begin
        inherited;
        { the code placement of the internal assembler is a draft, off by
          default: code keeps the plain CODEALIGN alignment (doc/OPTIMIZER.md,
          "Code placement").  MOONCOMPILER_PLACEMENT=1 switches the draft on,
          MOONCOMPILER_NO_PLACEMENT=1 (the earlier off switch) keeps it off }
        relaxenabled:=(cs_opt_codealign in current_settings.optimizerswitches) and
                      (GetEnvironmentVariable('MOONCOMPILER_PLACEMENT')='1') and
                      (GetEnvironmentVariable('MOONCOMPILER_NO_PLACEMENT')='');
        ObjOutput:=nil;
        ObjData:=nil;
        SmartAsm:=smart;
{$ifdef ARM}
        Code16:=current_settings.instructionset=is_thumb;
{$endif ARM}
      end;


   destructor TInternalAssembler.destroy;
      begin
        if assigned(ObjData) then
          ObjData.free;
          ObjData := nil;
        if assigned(ObjOutput) then
          ObjOutput.free;
          ObjOutput := nil;
      end;


    procedure TInternalAssembler.WriteStab(p:pansichar);

        function consumecomma(var p:pansichar):boolean;
        begin
          while (p^=' ') do
            inc(p);
          result:=(p^=',');
          inc(p);
        end;

        function consumenumber(var p:pansichar;out value:longint):boolean;
        var
          hs : string;
          len,
          code : integer;
        begin
          value:=0;
          while (p^=' ') do
            inc(p);
          len:=0;
          while (p^ in ['0'..'9']) do
            begin
              inc(len);
              hs[len]:=p^;
              inc(p);
            end;
          if len>0 then
            begin
              hs[0]:=chr(len);
              val(hs,value,code);
            end
          else
            code:=-1;
          result:=(code=0);
        end;

        function consumeoffset(var p:pansichar;out relocsym:tobjsymbol;out value:longint):boolean;
        var
          hs        : string;
          len,
          code      : integer;
          pstart    : pansichar;
          sym       : tobjsymbol;
          exprvalue : longint;
          gotmin,
          have_first_symbol,
          have_second_symbol,
          dosub     : boolean;
        begin
          result:=false;
          value:=0;
          relocsym:=nil;
          gotmin:=false;
          have_first_symbol:=false;
          have_second_symbol:=false;
          repeat
            dosub:=false;
            exprvalue:=0;
            if gotmin then
              begin
                dosub:=true;
                gotmin:=false;
              end;
            while (p^=' ') do
              inc(p);
            case p^ of
              #0 :
                break;
              ' ' :
                inc(p);
              '0'..'9' :
                begin
                  len:=0;
                  while (p^ in ['0'..'9']) do
                    begin
                      inc(len);
                      hs[len]:=p^;
                      inc(p);
                    end;
                  hs[0]:=chr(len);
                  val(hs,exprvalue,code);
                  if code<>0 then
                    internalerror(200702251);
                end;
              '.','_',
              'A'..'Z',
              'a'..'z' :
                begin
                  pstart:=p;
                  while not(p^ in [#0,' ','-','+']) do
                    inc(p);
                  len:=p-pstart;
                  if len>255 then
                    internalerror(200509187);
                  hs[0]:=chr(len);
                  move(pstart^,hs[1],len);
                  sym:=objdata.symbolref(hs);
                  { Second symbol? }
                  if assigned(relocsym) then
                    begin
                      if have_second_symbol then
                        internalerror(2007032201);
                      have_second_symbol:=true;
                      if not have_first_symbol then
                        internalerror(2007032202);
                      { second symbol should subtracted to first }
                      if not dosub then
                        internalerror(2007032203);
                      if (relocsym.objsection<>sym.objsection) then
                        internalerror(2005091810);
                      exprvalue:=relocsym.address-sym.address;
                      relocsym:=nil;
                      dosub:=false;
                    end
                  else
                    begin
                      relocsym:=sym;
                      if assigned(sym.objsection) then
                        begin
                          { first symbol should be + }
                          if not have_first_symbol and dosub then
                            internalerror(2007032204);
                          have_first_symbol:=true;
                        end;
                    end;
                end;
              '+' :
                begin
                  { nothing, by default addition is done }
                  inc(p);
                end;
              '-' :
                begin
                  gotmin:=true;
                  inc(p);
                end;
              else
                internalerror(200509189);
            end;
            if dosub then
              dec(value,exprvalue)
            else
              inc(value,exprvalue);
          until false;
          result:=true;
        end;

      var
        stabstrlen,
        ofs,
        nline,
        nidx,
        nother,
        i         : longint;
        stab      : TObjStabEntry;
        relocsym  : TObjSymbol;
        pstr,
        pcurr,
         pendquote : pansichar;
        oldsec    : TObjSection;
      begin
        pcurr:=nil;
        pstr:=nil;
        pendquote:=nil;
        relocsym:=nil;
        ofs:=0;

        { Parse string part }
        if (p[0]='"') then
          begin
            pstr:=@p[1];
            { Ignore \" inside the string }
            i:=1;
            while not((p[i]='"') and (p[i-1]<>'\')) and
                  (p[i]<>#0) do
              inc(i);
            pendquote:=@p[i];
            pendquote^:=#0;
            pcurr:=@p[i+1];
            if not consumecomma(pcurr) then
              internalerror(200509181);
          end
        else
          pcurr:=p;

        { In every layout pass (pass 1 and the code placement relaxation
          passes) only alloc and leave }
        if ObjData.currpass<>2 then
          begin
            ObjData.StabsSec.Alloc(sizeof(TObjStabEntry));
            if assigned(pstr) and (pstr[0]<>#0) then
              ObjData.StabStrSec.Alloc(strlen(pstr)+1);
          end
        else
          begin
            { Stabs format: nidx,nother,nline[,offset] }
            if not consumenumber(pcurr,nidx) then
              internalerror(200509182);
            if not consumecomma(pcurr) then
              internalerror(200509183);
            if not consumenumber(pcurr,nother) then
              internalerror(200509184);
            if not consumecomma(pcurr) then
              internalerror(200509185);
            if not consumenumber(pcurr,nline) then
              internalerror(200509186);
            if consumecomma(pcurr) then
              consumeoffset(pcurr,relocsym,ofs);

            { Generate stab entry }
            if assigned(pstr) and (pstr[0]<>#0) then
              begin
                stabstrlen:=strlen(pstr);
{$ifdef optimizestabs}
                StabStrEntry:=nil;
                if (nidx=N_SourceFile) or (nidx=N_IncludeFile) then
                  begin
                    hs:=strpas(pstr);
                    StabstrEntry:=StabStrDict.Find(hs);
                    if not assigned(StabstrEntry) then
                      begin
                        StabstrEntry:=TStabStrEntry.Create(hs);
                        StabstrEntry:=StabStrSec.Size;
                        StabStrDict.Insert(StabstrEntry);
                        { generate new stab }
                        StabstrEntry:=nil;
                      end;
                  end;
                if assigned(StabstrEntry) then
                  stab.strpos:=StabstrEntry.strpos
                else
{$endif optimizestabs}
                  begin
                    stab.strpos:=ObjData.StabStrSec.Size;
                    ObjData.StabStrSec.write(pstr^,stabstrlen+1);
                  end;
              end
            else
              stab.strpos:=0;
            stab.ntype:=byte(nidx);
            stab.ndesc:=word(nline);
            stab.nother:=byte(nother);
            stab.nvalue:=ofs;

            { Write the stab first without the value field. Then
              write a the value field with relocation }
            oldsec:=ObjData.CurrObjSec;
            ObjData.SetSection(ObjData.StabsSec);
            MaybeSwapStab(stab);
            ObjData.Writebytes(stab,sizeof(TObjStabEntry)-4);
            ObjData.Writereloc(stab.nvalue,4,relocsym,RELOC_ABSOLUTE32);
            ObjData.setsection(oldsec);
          end;
        if assigned(pendquote) then
          pendquote^:='"';
      end;


    function TInternalAssembler.MaybeNextList(var hp:Tai):boolean;
      begin
        { maybe end of list }
        while not assigned(hp) do
         begin
           if currlistidx<lists then
            begin
              inc(currlistidx);
              currlist:=list[currlistidx];
              hp:=Tai(currList.first);
            end
           else
            begin
              MaybeNextList:=false;
              exit;
            end;
         end;
        MaybeNextList:=true;
      end;


    function TInternalAssembler.SetIndirectToSymbol(hp: Tai; const indirectname: string): Boolean;
      var
        objsym  : TObjSymbol;
        indsym  : TObjSymbol;
      begin
        Result:=
          Assigned(hp) and
          (hp.typ=ait_symbol);
        if not Result then
          Exit;
        objsym:=Objdata.SymbolRef(tai_symbol(hp).sym);
        objsym.size:=0;

        indsym := TObjSymbol(ObjData.ObjSymbolList.Find(indirectname));
        if not Assigned(indsym) then
          begin
            { it's possible that indirect symbol is not present in the list,
              so we must create it as undefined }
            indsym:=ObjData.CObjSymbol.Create(ObjData.ObjSymbolList, indirectname);
            indsym.typ:=AT_NONE;
            indsym.bind:=AB_NONE;
          end;
        objsym.indsymbol:=indsym;
        Result:=true;
      end;


    function TInternalAssembler.TreePass0(hp:Tai):Tai;
      var
        objsym,
        objsymend : TObjSymbol;
        cpu: tcputype;
        eabi_section, TmpSection: TObjSection;
      begin
        while assigned(hp) do
         begin
{$ifdef DEBUG}
           if not(hp.typ in SkipLineInfo) then
             current_filepos:=tailineinfo(hp).fileinfo;
{$endif DEBUG}
            case hp.typ of
             ait_align :
               begin
                 if tai_align_abstract(hp).fixedfill then
                   begin
                     { the prefix part of the pad sits on the instructions }
                     Tai_align_abstract(hp).fillsize:=Tai_align_abstract(hp).padbytes-Tai_align_abstract(hp).prefixbytes;
                     ObjData.alloc(Tai_align_abstract(hp).fillsize);
                   end
                 else if relaxenabled and (tai_align_abstract(hp).purpose in [ap_proc,ap_loop]) and
                         (oso_executable in ObjData.CurrObjSec.secoptions) then
                   begin
                     { placed by size in the layout passes; up to 63 bytes }
                     Tai_align_abstract(hp).fillsize:=63;
                     ObjData.alloc(63);
                   end
                 else if relaxenabled and (asmblockdepth=0) and
                         (oso_executable in ObjData.CurrObjSec.secoptions) then
                   begin
                     { an ordinary jump-target alignment inside placed code
                       becomes a target pad (up to 12 bytes, decided in the
                       layout passes); a 1-byte alignment stays empty }
                     if tai_align_abstract(hp).aligntype>1 then
                       begin
                         Tai_align_abstract(hp).purpose:=ap_target;
                         Tai_align_abstract(hp).fillsize:=12;
                         ObjData.alloc(12);
                       end
                     else
                       Tai_align_abstract(hp).fillsize:=0;
                   end
                 else if tai_align_abstract(hp).aligntype>1 then
                   begin
                     { always use the maximum fillsize in this pass to avoid possible
                       short jumps to become out of range }
                     Tai_align_abstract(hp).fillsize:=Tai_align_abstract(hp).aligntype;
                     ObjData.alloc(Tai_align_abstract(hp).fillsize);
                     { may need to increase alignment of section }
                     if tai_align_abstract(hp).aligntype>ObjData.CurrObjSec.secalign then
                       ObjData.CurrObjSec.secalign:=tai_align_abstract(hp).aligntype;
                   end
                 else
                   Tai_align_abstract(hp).fillsize:=0;
               end;
             ait_datablock :
               begin
{$ifdef USE_COMM_IN_BSS}
                 if writingpackages and
                    Tai_datablock(hp).is_global then
                   ObjData.SymbolDefine(Tai_datablock(hp).sym)
                 else
{$endif USE_COMM_IN_BSS}
                   begin
                     ObjData.allocalign(used_align(size_2_align(Tai_datablock(hp).size),0,ObjData.CurrObjSec.secalign));
                     ObjData.SymbolDefine(Tai_datablock(hp).sym);
                     ObjData.alloc(Tai_datablock(hp).size);
                   end;
               end;
             ait_realconst:
               ObjData.alloc(tai_realconst(hp).savesize);
             ait_const:
               begin
                 { if symbols are provided we can calculate the value for relative symbols.
                   This is required for length calculation of leb128 constants }
                 if assigned(tai_const(hp).sym) then
                   begin
                     objsym:=Objdata.SymbolRef(tai_const(hp).sym);
                     { objsym already defined and there is endsym? }
                     if assigned(objsym.objsection) and assigned(tai_const(hp).endsym) then
                       begin
                         objsymend:=Objdata.SymbolRef(tai_const(hp).endsym);
                         { objsymend already defined? }
                         if assigned(objsymend.objsection) then
                           begin
                             if objsymend.objsection<>objsym.objsection then
                               begin
                                 { leb128 relative constants are not relocatable, but other types are,
                                   given that objsym belongs to the current section. }
                                 if (Tai_const(hp).consttype in [aitconst_uleb128bit,aitconst_sleb128bit]) or
                                    (objsym.objsection<>ObjData.CurrObjSec) then
                                   InternalError(200404124);
                               end
{$push} {$R-}{$Q-}
                             else
                               Tai_const(hp).value:=objsymend.address-objsym.address+Tai_const(hp).symofs;
                           end;
{$pop}
                       end;
                   end;
                 ObjData.alloc(tai_const(hp).size);
               end;
             ait_directive:
               begin
                 case tai_directive(hp).directive of
                   asd_indirect_symbol:
                     { handled in TreePass1 }
                     ;
                   asd_lazy_reference:
                     begin
                       if tai_directive(hp).name='' then
                         Internalerror(2009112101);
                       objsym:=ObjData.symbolref(tai_directive(hp).name);
                       objsym.bind:=AB_LAZY;
                     end;
                   asd_reference:
                     { ignore for now, but should be added}
                     ;
                   asd_cpu:
                     begin
                       ObjData.CPUType:=cpu_none;
                       for cpu:=low(tcputype) to high(tcputype) do
                         if cputypestr[cpu]=tai_directive(hp).name then
                           begin
                             ObjData.CPUType:=cpu;
                             break;
                           end;
                     end;
                   asd_weak_definition:
                     begin
                       if tai_directive(hp).name='' then
                         Internalerror(2022040901);
                       objsym:=ObjData.symbolref(tai_directive(hp).name);
                       objsym.bind:=AB_WEAK;
                     end;
{$ifdef OMFOBJSUPPORT}
                   asd_omf_linnum_line:
                     { ignore for now, but should be added}
                     ;
{$endif OMFOBJSUPPORT}
{$ifdef ARM}
                   asd_thumb_func:
                     ObjData.ThumbFunc:=true;
                   asd_force_thumb:
                     begin
                       ObjData.ThumbFunc:=true;
                       Code16:=true;
                     end;
                   asd_code:
                     begin
                       { ai_directive(hp).name can be only 16 or 32, this is checked by the reader }
                       ObjData.ThumbFunc:=tai_directive(hp).name='16';
                       Code16:=tai_directive(hp).name='16';
                     end
{$endif ARM}
{$ifdef RISCV}
                   asd_option:
                     internalerror(2019031701);
{$endif RISCV}
                   else
                     internalerror(2010011101);
                 end;
               end;
             ait_section:
               begin
                 if Tai_section(hp).sectype=sec_user then
                   ObjData.CreateSection(Tai_section(hp).sectype,Tai_section(hp).secflags,Tai_section(hp).secprogbits,Tai_section(hp).name^,Tai_section(hp).secorder)
                 else
                   ObjData.CreateSection(Tai_section(hp).sectype,Tai_section(hp).name^,Tai_section(hp).secorder);
                 Tai_section(hp).sec:=ObjData.CurrObjSec;
               end;
             ait_symbol :
               begin
                 { needs extra support in the internal assembler }
                 { the value is just ignored }
                 {if tai_symbol(hp).has_value then
                      internalerror(2009090804); ;}
                 ObjData.SymbolDefine(Tai_symbol(hp).sym);
               end;
             ait_symbolpair :
               with tai_symbolpair(hp) do
                 ObjData.SymbolPairDefine(kind,sym^,value^);
             ait_label :
               ObjData.SymbolDefine(Tai_label(hp).labsym);
             ait_string :
               ObjData.alloc(Tai_string(hp).len);
             ait_instruction :
               begin
{$ifdef arm}
                 if code16 then
                   include(taicpu(hp).flags,cf_thumb)
                 else
                   exclude(taicpu(hp).flags,cf_thumb);
{$endif arm}
                 { reset instructions which could change in pass 2 }
                 Taicpu(hp).resetpass2;
                 ObjData.alloc(Taicpu(hp).Pass1(ObjData));
               end;
             ait_marker :
               case tai_marker(hp).Kind of
                 mark_AsmBlockStart:
                   inc(asmblockdepth);
                 mark_AsmBlockEnd:
                   dec(asmblockdepth);
                 else
                   ;
               end;
             ait_cutobject :
               if SmartAsm then
                break;
             ait_eabi_attribute :
               begin
                 eabi_section:=ObjData.findsection('.ARM.attributes');
                 if not(assigned(eabi_section)) then
                   begin
                     TmpSection:=ObjData.CurrObjSec;
                     ObjData.CreateSection(sec_arm_attribute,[],SPB_ARM_ATTRIBUTES,'',secorder_default);
                     eabi_section:=ObjData.CurrObjSec;
                     ObjData.setsection(TmpSection);
                   end;
                 if eabi_section.Size=0 then
                   eabi_section.alloc(16);
                 eabi_section.alloc(LengthUleb128(tai_attribute(hp).tag));
                 case tai_attribute(hp).eattr_typ of
                   eattrtype_dword:
                     eabi_section.alloc(LengthUleb128(tai_attribute(hp).value));
                   eattrtype_ntbs:
                     if assigned(tai_attribute(hp).valuestr) then
                       eabi_section.alloc(Length(tai_attribute(hp).valuestr^)+1)
                     else
                       eabi_section.alloc(1);
                   else
                     Internalerror(2019100701);
                 end;
               end;
{$ifdef WASM}
             ait_globaltype:
               TWasmObjData(ObjData).DeclareGlobalType(tai_globaltype(hp));
             ait_functype:
               TWasmObjData(ObjData).DeclareFuncType_Pass0(tai_functype(hp));
             ait_tagtype:
               TWasmObjData(ObjData).DeclareTagType(tai_tagtype(hp));
             ait_export_name:
               TWasmObjData(ObjData).DeclareExportName(tai_export_name(hp));
             ait_import_module:
               TWasmObjData(ObjData).DeclareImportModule(tai_import_module(hp));
             ait_import_name:
               TWasmObjData(ObjData).DeclareImportName(tai_import_name(hp));
             ait_local:
               TWasmObjData(ObjData).DeclareLocals_Pass0(tai_local(hp));
{$endif WASM}
             else
               ;
           end;
           hp:=Tai(hp.next);
         end;
        TreePass0:=hp;
      end;


    procedure TInternalAssembler.TracePass(passno:byte);
      begin
        Comment(V_Debug,'Code placement pass '+tostr(passno)+': new pads '+tostr(passpads)+
          ', changed pads '+tostr(passchanges)+', jumps forced near '+tostr(passforced)+
          ', span fills changed '+tostr(passspans));
        passpads:=0;
        passchanges:=0;
        passforced:=0;
        passspans:=0;
      end;


    { Code placement: after a layout pass, re-check every short jump with
      the addresses of that pass (see tai_cpu_abstract.verify_short_jump).
      Walks the current list(s) from hp; in smart-linking mode a chunk ends
      at the next cut object. }
    function TInternalAssembler.VerifyShortJumps(hp:Tai;chunk:boolean):boolean;
      begin
        result:=false;
        while assigned(hp) do
          begin
            if chunk and (hp.typ=ait_cutobject) then
              break;
            case hp.typ of
              ait_section:
                ObjData.setsection(Tai_section(hp).sec);
              ait_instruction:
                if tai_cpu_abstract(hp).verify_short_jump(ObjData,false) then
                  begin
                    inc(relaxforced);
                    inc(passforced);
                    result:=true;
                  end;
              else
                ;
            end;
            hp:=Tai(hp.next);
            if not chunk then
              MaybeNextList(hp);
          end;
      end;


    { Code placement rules 1-3: the fill in front of a procedure entry or a
      loop head is chosen from the size measured in the previous layout
      pass.  A procedure of at most 64 bytes starts on a 64-byte line; a
      longer one on 32 bytes (never in the last 16 bytes of a line).  A
      loop (head label to the end of its farthest backward jump) is placed
      by its length, following the loop maps of 2026-09-15
      (doc-int/experiments/tiny-loop-map) and the stand: at most 64 bytes
      - inside one line with the least fill, but its back-edge must not
      end on byte 29-31 or 62-63 of the line (Zen 3: +25% / +66% even
      inside a line); longer - the head on 32 bytes.  The end-of-line
      target for long loops (byte 62) put the head into the tail of the
      previous line for loops just over a line and fixed the position of
      the others on the wrong side of a coin; a zone for the end measured
      on one 66-byte loop did not transfer to other lengths (the 85-byte
      map has the opposite zones, and the stand lost on containstext and
      move-16).  The head on 32 is what the old CODEALIGN did and what
      the rule-4-only stand had, and that stand won on every case the
      later rules lost.  Sections with 64-byte decisions (a short procedure
      or loop, a target pad) become 64-byte aligned; the others stay
      32-byte aligned.  Sizes are unknown
      in the first pass: the ordinary alignment is used and a relaxation
      pass is forced. }
    const
      { code placement: how often one pad may change before it is kept }
      PadChangeLimit = 8;


    procedure TInternalAssembler.SpanAlign(hp:tai_align_abstract);
      const
        SpanChangeLimit = 12;
      var
        p : tai;
        objsym : TObjSymbol;
        pos,fill,len,innerlen,cand,chosen,shift,endbyte,fitcand,head,bestfill,bestlines,lines,prevlines : longint;
        loopend : int64;
        want64,want32,known : boolean;

      { Zen 3 map: a back-edge ending on these bytes of a line costs, even
        when the loop lies inside the line (the milder spots 53-54 of the
        map are not avoided: moving ustr-pos-str off them cost 10%) }
      function badend(b:longint):boolean;
        begin
          result:=(b>=29) and (b<=31) or (b>=62);
        end;

      function regularfill:longint;
        begin
          result:=align(pos,hp.aligntype)-pos;
        end;

      begin
        pos:=ObjData.CurrObjSec.Size;
        fill:=regularfill;
        objsym:=nil;
        want64:=false;
        want32:=false;
        known:=false;
        shift:=0;
        p:=tai(hp.next);
        while assigned(p) and (p.typ in TransparentInstr+[ait_function_name]) do
          p:=tai(p.next);
        case hp.purpose of
          ap_proc:
            if assigned(p) and (p.typ=ait_symbol) and (tai_symbol(p).sym.typ=AT_FUNCTION) then
              begin
                objsym:=ObjData.symbolref(tai_symbol(p).sym);
                len:=longint(objsym.size);
                if (len>0) and (prevlayoutpass<>0) then
                  begin
                    { Every procedure starts on a 64-byte line.  A longer
                      procedure used to start on 32 bytes, which left it on
                      byte 0 or 32 of a line as the linker placed its
                      section: for compiled code the target pads inside
                      already forced byte 0, for a hand-written assembler
                      routine (Move, CompareByte, FillChar) nothing did, and
                      its body - laid out by its author counting bytes from
                      the entry - moved by half a line from one link to the
                      next.  The bytes in front of an entry are never
                      executed (the previous routine ended with a return),
                      so the fill costs size only. }
                    known:=true;
                    fill:=(64-(pos and 63)) and 63;
                    want64:=true;
                    { A procedure that lies in one line needs no target
                      pads either (the line is fetched whole, as for a
                      loop inside one line): the 7 prefix bytes that
                      moved a join off byte 57 pushed a 61-byte leaf
                      over the line - two fetch blocks per call instead
                      of one (managed-static-array +19% on the Ryzen
                      stand).  The length is the procedure's own bytes,
                      without the pads of the previous pass. }
                    MarkLoopTargets(p,int64(objsym.offset)+len,len-LoopPadBytes(p,int64(objsym.offset)+len)<=64);
                  end;
              end;
          ap_loop:
            if assigned(p) and (p.typ=ait_label) then
              begin
                objsym:=ObjData.symbolref(tai_label(p).labsym);
                if (prevlayoutpass<>0) and (objsym.looppass=prevlayoutpass) and (objsym.looplen>0) then
                  begin
                    known:=true;
                    len:=objsym.looplen;
                    loopend:=int64(objsym.offset)+len;
                    { The branch pads inside the loop depend on where the
                      loop lies, so its length depends on the fill in
                      front of it.  Try every fill from 0 up and take the
                      first one whose simulated layout satisfies the rule:
                      a loop of at most 64 bytes inside one line, a longer
                      one ending one byte before a line boundary (its last
                      byte at offset 62: the same fetch block as offset 63,
                      but the back-edge does not end on a 32-byte boundary,
                      which rule 4 forbids and would pad away).  A loop that contains
                      another loop alignment cannot control its own end
                      (the inner loop pins it): only the prefix up to the
                      inner loop is kept inside one line. }
                    chosen:=-1;
                    fitcand:=-1;
                    { The class comes from the loop's own bytes, without the
                      pads the previous pass put inside it: the first sized
                      pass still carries the regular fill of an inner loop
                      head and the widest target pads, and with them a
                      43-byte nest of two loops measured as 70 bytes, became
                      long for good, moved its head to 32 and pushed the
                      inner loop into the next line with 27 bytes of nops
                      (Pos, ManagedStaticLength and CompareText callers on
                      the stand: +6..19%).  A loop that fitted a line once
                      stays short until it really cannot fit; a longer loop
                      is long for good. }
                    if hp.spanclass=0 then
                      begin
                        { The total span says nothing useful about an outer
                          loop that contains another loop alignment: the
                          inner loop places its own hot body.  Classify that
                          shape by the prefix up to the inner alignment even
                          when the whole nest is longer than one line.  The
                          old order only looked for an inner loop after the
                          whole nest had been classified as short, so the
                          nested-loop class was unreachable for every real
                          long nest. }
                        shift:=SimulateLoop(p,loopend,pos-longint(objsym.offset),innerlen,true);
                        if innerlen>=0 then
                          hp.spanclass:=3
                        else if len-LoopPadBytes(p,loopend)<=64 then
                          hp.spanclass:=1
                        else
                          hp.spanclass:=2;
                      end;
                    if hp.spanclass in [1,3] then
                      begin
                        if hp.spanclass=3 then
                          begin
                            bestfill:=-1;
                            bestlines:=maxlongint;
                          end;
                        for cand:=0 to 63 do
                          begin
                            { a loop inside one line needs no target pads:
                              the whole line is fetched anyway, and a pad
                              inside pushed such loops out of their line
                              (48 bytes of fill in front of the
                              incr_ref_many loop of every managed copy) }
                            shift:=SimulateLoop(p,loopend,pos+cand-longint(objsym.offset),innerlen,true);
                            if hp.spanclass=3 then
                              begin
                                if (innerlen>64) or (((pos+cand) and 63)+innerlen<=64) then
                                  begin
                                    lines:=(((pos+cand) and 63)+len+shift-1) div 64+1;
                                    if (lines<bestlines) or
                                       ((lines=bestlines) and (cand<bestfill)) then
                                      begin
                                        bestlines:=lines;
                                        bestfill:=cand;
                                        chosen:=cand;
                                      end;
                                  end;
                              end
                            else if ((pos+cand) and 63)+len+shift<=64 then
                              begin
                                { inside one line: the first fill whose
                                  back-edge avoids the bad bytes, else a
                                  plain fit }
                                endbyte:=(pos+cand+len+shift-1) and 63;
                                if not badend(endbyte) then
                                  begin
                                    chosen:=cand;
                                    break;
                                  end;
                                if fitcand<0 then
                                  fitcand:=cand;
                              end;
                          end;
                        if (chosen<0) and (fitcand>=0) then
                          chosen:=fitcand;
                        if (chosen<0) and (hp.spanclass=1) then
                          { does not fit in a line at any position: long }
                          hp.spanclass:=2;
                        MarkLoopTargets(p,loopend,hp.spanclass=1);
                      end;
                    if hp.spanclass=3 then
                      begin
                        { the prefix of a loop with a loop inside: found by
                          the simulation above }
                        if chosen<0 then
                          fill:=0
                        else
                          fill:=chosen;
                        want64:=true;
                      end
                    else if hp.spanclass=2 then
                      begin
                        { Longer than a line: the head on byte 0, 16 or 32
                          of a line (a 16-byte boundary in the first half:
                          never in the tail of a line, and inside the fast
                          head zones of both maps), from where the loop
                          touches the fewest lines, with the least fill
                          among those.  A loop of 65..128 bytes touches two
                          lines from byte 0, but three from byte 32 once it
                          is longer than 96 (Pos on the stand: 98 bytes,
                          +8%; UTF8Encode: 120 bytes, +6% on the Xeon); and
                          the fill in front of the head is executed on
                          every entry, so a 101-byte loop reached once per
                          call took byte 16 with 7 bytes of fill rather
                          than byte 0 with 55 (CompareText on one-character
                          strings: +9% with the fill to byte 0). }
                        bestfill:=-1;
                        bestlines:=maxlongint;
                        prevlines:=maxlongint;
                        for head:=0 to 2 do
                          begin
                            fill:=(head*16-(pos and 63)) and 63;
                            shift:=SimulateLoop(p,loopend,pos+fill-longint(objsym.offset),innerlen);
                            lines:=(((pos+fill) and 63)+len+shift-1) div 64+1;
                            if fill=hp.fillsize then
                              prevlines:=lines;
                            if (lines<bestlines) or ((lines=bestlines) and (fill<bestfill)) then
                              begin
                                bestlines:=lines;
                                bestfill:=fill;
                              end;
                          end;
                        { Keep a previous minimum-line placement stable while
                          target pads and branch sizes settle. }
                        if (hp.spanchanges>1) and (prevlines=bestlines) then
                          bestfill:=hp.fillsize;
                        fill:=bestfill;
                        want64:=true;
                      end
                    else
                      begin
                        if chosen<0 then
                          fill:=0
                        else
                          fill:=chosen;
                        want64:=true;
                      end;
                  end;
              end;
          else
            ;
        end;
        if not known then
          begin
            { sizes come from the previous pass: make sure there is one;
              a size that stays unknown (an empty symbol) changes nothing;
              a loop label that no backward jump targets is a plain jump
              target and gets no fill }
            if prevlayoutpass=0 then
              layoutchanged:=true
            else if hp.purpose=ap_loop then
              begin
                { no backward jump reaches this label (a goto label, a
                  continue label): from now on a plain jump target, kept
                  out of the tail of a line like every other target }
                hp.purpose:=ap_target;
                hp.fillsize:=0;
                hp.padbytes:=0;
                TargetPad(hp);
                exit;
              end;
          end
        else
          begin
            inc(relaxspans);
            if fill<>hp.fillsize then
              begin
                { The simulation predicts the next pass from the sizes of
                  the previous one; jump encodings that still change can
                  move the answer a few more times.  A node that keeps
                  moving after SpanChangeLimit changes is frozen. }
                if (hp.spanchanges>=SpanChangeLimit) or relaxfrozen then
                  begin
                    { What is kept is the byte of the line the head stood
                      on in the previous pass, not the number of fill bytes:
                      the code in front still moves after this node is
                      frozen (pads that settle later), and the kept byte
                      count then left the head wherever that put it - four
                      long loops of the Win64 RTL off byte 0/16/32, an
                      entry could have left its line the same way.  The
                      fill to a fixed byte depends on nothing but the
                      position, so it cannot keep the passes going. }
                    fill:=(longint(objsym.offset and 63)-pos) and 63;
                    if fill<>hp.fillsize then
                      layoutchanged:=true;
                  end
                else
                  begin
                    inc(hp.spanchanges);
                    inc(passspans);
                    layoutchanged:=true;
                  end;
              end;
          end;
        if want64 and (ObjData.CurrObjSec.secalign<64) then
          ObjData.CurrObjSec.secalign:=64
        else if want32 and (ObjData.CurrObjSec.secalign<32) then
          ObjData.CurrObjSec.secalign:=32;
        hp.fillsize:=fill;
        ObjData.alloc(fill);
      end;


    { Code placement: the branch pad in front of padstart (through
      bookkeeping items and labels), nil when there is none. }
    function TInternalAssembler.FindBranchPad(padstart:tai):tai_align_abstract;
      var
        loc : tai;
      begin
        result:=BranchPadHome(padstart,loc);
      end;


    { Code placement: where the pad node of the pair starting at padstart
      stands - the node when it exists, and loc, the item a new node goes in
      front of (and from which the pad's nops move the code).

      The node stands directly in front of the pair, or in front of the
      labels the pair's block starts with.  Bookkeeping items without code
      bytes are looked through.  A new node goes in front of the labels,
      unless they are an aligned target (a loop head, an entry): then
      directly in front of the pair, never between the alignment and its
      label.

      The block may have plain instructions between its labels and the pair.
      What the pad cannot put on them as prefixes is nops, and between the
      label and the pair every path into the block executes them: the
      back-edge block of the UTF-8 encoder's loop, "L: add; cmp; ja" with L
      reached by a jump from every case, got six bytes of nops behind the
      add, executed in every iteration.  In front of L only the path that
      falls into L executes them, and none at all when that place is dead
      (139 nop pads of the Win64 Pulse program stood behind a jump target
      this way, 47 of them inside loops).  The walk back stops at a
      branch, a call and a hand-written block, so a block has one such pair
      at most and its node is found again the same way. }
    function TInternalAssembler.BranchPadHome(padstart:tai;out loc:tai):tai_align_abstract;
      var
        prev,scan,dummy : tai;
      begin
        result:=nil;
        loc:=padstart;
        prev:=tai(padstart.previous);
        while assigned(prev) and (prev.typ in TransparentInstr) do
          prev:=tai(prev.previous);
        if assigned(prev) and (prev.typ=ait_align) and tai_align_abstract(prev).fixedfill then
          begin
            result:=tai_align_abstract(prev);
            exit;
          end;
        { back over the plain instructions of the pair's block }
        scan:=prev;
        while assigned(scan) do
          begin
            case scan.typ of
              ait_instruction:
                if tai_cpu_abstract(scan).branch_pad_before(ObjData,0,dummy)>=0 then
                  break;
              ait_marker:
                if tai_marker(scan).Kind in [mark_AsmBlockStart,mark_AsmBlockEnd] then
                  break;
              ait_label:
                if not (tai_label(scan).labsym.labeltype in [alt_dbgline,alt_dbgfile,alt_dbgtype,alt_dbgframe]) then
                  break;
              ait_align:
                if not EmptyAlign(scan) then
                  break;
              else
                if not (scan.typ in TransparentInstr) then
                  break;
            end;
            scan:=tai(scan.previous);
          end;
        if not (assigned(scan) and (scan.typ=ait_label)) then
          exit;
        prev:=scan;
        { the code generator's empty alignment in front of a join label is
          not an aligned target: it emits nothing (EmptyAlign).  Taken for
          one, it kept the pad of every such block directly in front of its
          pair: the node is made in the first pass, when the label has no
          target pad node yet, and is found there ever after. }
        while assigned(prev) and ((prev.typ in TransparentInstr+[ait_label]) or EmptyAlign(prev)) do
          begin
            if prev.typ=ait_label then
              loc:=prev;
            prev:=tai(prev.previous);
          end;
        if assigned(prev) and (prev.typ=ait_align) then
          begin
            if tai_align_abstract(prev).fixedfill then
              result:=tai_align_abstract(prev)
            else if tai_align_abstract(prev).purpose=ap_target then
              begin
                { the labels are a target with its own pad: the branch
                  pad goes in front of that pad, so that the target
                  keeps pointing at code and not at the pad's nops }
                loc:=prev;
                prev:=tai(prev.previous);
                while assigned(prev) and ((prev.typ in TransparentInstr) or EmptyAlign(prev)) do
                  prev:=tai(prev.previous);
                if assigned(prev) and (prev.typ=ait_align) and tai_align_abstract(prev).fixedfill then
                  result:=tai_align_abstract(prev);
              end
            else
              loc:=padstart;
          end;
      end;


    { Code placement: how the code after a loop head moves when the head
      itself moves by delta bytes.  Walks the previous pass's layout from
      the head to loopend, re-deciding every branch pad and ordinary
      alignment inside for the new positions (jump encodings are taken as
      they are).  Returns the shift of the loop end; when the loop contains
      another loop alignment the walk stops there and prefixend receives
      the new length of the prefix, otherwise -1. }
    { The pad bytes inside a loop as the previous pass laid it out: the
      nops and prefixes of the branch and target pads, the fills of the
      alignment nodes (an inner loop head among them).  The loop's length
      minus this is what the loop is made of. }
    function TInternalAssembler.LoopPadBytes(head:tai;loopend:int64):longint;
      var
        q : tai;
        endofs : longint;
      begin
        result:=0;
        q:=tai(head.next);
        while assigned(q) do
          begin
            case q.typ of
              ait_section,ait_symbol_end,ait_cutobject:
                break;
              ait_instruction:
                begin
                  tai_cpu_abstract(q).jump_target(ObjData,endofs);
                  if endofs>=loopend then
                    break;
                end;
              ait_align:
                if tai_align_abstract(q).fixedfill or (tai_align_abstract(q).purpose=ap_target) then
                  inc(result,tai_align_abstract(q).padbytes)
                else
                  inc(result,tai_align_abstract(q).fillsize);
              else
                ;
            end;
            q:=tai(q.next);
          end;
      end;


    { The target pad nodes inside a loop remember whether the loop lies
      inside one line (spanclass 1 on the target node): such a target
      gets no pad. }
    procedure TInternalAssembler.MarkLoopTargets(head:tai;loopend:int64;inline:boolean);
      var
        q : tai;
        endofs : longint;
      begin
        q:=tai(head.next);
        while assigned(q) do
          begin
            case q.typ of
              ait_section,ait_symbol_end,ait_cutobject:
                break;
              ait_instruction:
                begin
                  tai_cpu_abstract(q).jump_target(ObjData,endofs);
                  if endofs>=loopend then
                    break;
                end;
              ait_align:
                if tai_align_abstract(q).purpose=ap_target then
                  begin
                    if inline then
                      tai_align_abstract(q).spanclass:=1
                    else
                      tai_align_abstract(q).spanclass:=0;
                  end;
              else
                ;
            end;
            q:=tai(q.next);
          end;
      end;


    function TInternalAssembler.SimulateLoop(head:tai;loopend:int64;delta:longint;out prefixend:longint;notargets:boolean):longint;
      var
        q,r,padstart : tai;
        existing : tai_align_abstract;
        d,pold,pnew,endofs,fnew,apos,asmdepth,extrafill : longint;
        headofs : longint;
      begin
        prefixend:=-1;
        d:=delta;
        asmdepth:=0;
        headofs:=longint(ObjData.symbolref(tai_label(head).labsym).offset);
        q:=tai(head.next);
        while assigned(q) do
          begin
            case q.typ of
              ait_section,ait_symbol_end,ait_cutobject:
                break;
              ait_marker:
                case tai_marker(q).Kind of
                  mark_AsmBlockStart:
                    inc(asmdepth);
                  mark_AsmBlockEnd:
                    dec(asmdepth);
                  else
                    ;
                end;
              ait_instruction:
                begin
                  tai_cpu_abstract(q).jump_target(ObjData,endofs);
                  if (asmdepth=0) and
                     (tai_cpu_abstract(q).branch_pad_before(ObjData,0,padstart,d)>=0) then
                    begin
                      existing:=FindBranchPad(padstart);
                      if assigned(existing) then
                        pold:=existing.padbytes
                      else
                        pold:=0;
                      pnew:=tai_cpu_abstract(q).branch_pad_before(ObjData,pold,padstart,d);
                      if (pnew<0) or (pnew>=32) then
                        pnew:=pold;
                      inc(d,pnew-pold);
                    end;
                  if endofs>=loopend then
                    break;
                end;
              ait_align:
                if tai_align_abstract(q).fixedfill then
                  { counted with its pair }
                else if tai_align_abstract(q).purpose=ap_loop then
                  begin
                    { a nested loop: the prefix ends here }
                    r:=tai(q.next);
                    while assigned(r) and (r.typ in TransparentInstr) do
                      r:=tai(r.next);
                    if assigned(r) and (r.typ=ait_label) then
                      prefixend:=longint(ObjData.symbolref(tai_label(r).labsym).offset)-
                        tai_align_abstract(q).fillsize-headofs+d-delta;
                    break;
                  end
                else if tai_align_abstract(q).purpose=ap_target then
                  begin
                    { a target pad: re-decided from the position of the
                      label behind it, without the old pad (its nops sit in
                      the node, its prefixes on the instructions before) }
                    r:=tai(q.next);
                    extrafill:=0;
                    while assigned(r) and ((r.typ in TransparentInstr) or (r.typ=ait_align)) do
                      begin
                        if r.typ=ait_align then
                          inc(extrafill,tai_align_abstract(r).fillsize);
                        r:=tai(r.next);
                      end;
                    if assigned(r) and (r.typ=ait_label) then
                      begin
                        apos:=longint(ObjData.symbolref(tai_label(r).labsym).offset)-
                          tai_align_abstract(q).fillsize-extrafill+d-tai_align_abstract(q).prefixbytes-
                          BranchNopsBefore(q);
                        if notargets then
                          fnew:=0
                        else
                          fnew:=TargetPadSize(tai_align_abstract(q),apos);
                        inc(d,fnew-tai_align_abstract(q).padbytes);
                      end;
                  end
                else if (tai_align_abstract(q).aligntype>1) and (tai_align_abstract(q).fillsize<>0) then
                  begin
                    { an ordinary alignment (jump target) that still has a
                      fill: it follows the position of the label behind it;
                      further (empty) alignment nodes may sit between them }
                    r:=tai(q.next);
                    extrafill:=0;
                    while assigned(r) and ((r.typ in TransparentInstr) or (r.typ=ait_align)) do
                      begin
                        if r.typ=ait_align then
                          inc(extrafill,tai_align_abstract(r).fillsize);
                        r:=tai(r.next);
                      end;
                    if assigned(r) and (r.typ=ait_label) then
                      begin
                        apos:=longint(ObjData.symbolref(tai_label(r).labsym).offset)-
                          tai_align_abstract(q).fillsize-extrafill+d;
                        fnew:=align(apos,tai_align_abstract(q).aligntype)-apos;
                        if (tai_align_abstract(q).aligntype<>tai_align_abstract(q).maxbytes) and
                           (fnew>tai_align_abstract(q).maxbytes) then
                          fnew:=align(apos,Byte(tai_align_abstract(q).aligntype div 2))-apos;
                        inc(d,fnew-tai_align_abstract(q).fillsize);
                      end;
                  end;
              else
                ;
            end;
            q:=tai(q.next);
          end;
        { only the growth of the pads, not the displacement itself }
        result:=d-delta;
      end;


    { Code placement: keep every branch (or macro-fused ALU+branch pair) away
      from 32-byte boundaries by inserting a fixed nop pad in front of it.
      The pad is created on demand during pass 1 and recomputed in every
      relaxation pass from the position the pair would have without it, so
      it can grow, shrink or disappear until the layout is stable. }
    procedure TInternalAssembler.ApplyBranchPad(hp:tai);
      var
        padstart,loc : tai;
        existing : tai_align_abstract;
        pad,nops : longint;
      begin
        pad:=tai_cpu_abstract(hp).branch_pad_before(ObjData,0,padstart);
        { not a branch: the pad in front of it, if any, belongs to a
          branch that is fused with it and is handled there }
        if pad<0 then
          exit;
        existing:=BranchPadHome(padstart,loc);
        { Pads whose prefixes reach in front of other branches move each
          other; a pad that has changed PadChangeLimit times (every pad,
          once the passes reach their limit) keeps its prefixes where they
          are, so that the passes end.  Its branch still has to keep the
          rule: the pads in front of it go on settling after it is kept,
          and the kept byte count then left the branch wherever that put it
          (25 branches of the Win64 RTL on a boundary, the first compare of
          UnicodeCompareStr's loop with one prefix of the four it needed).
          What is missing, or too much, goes as nops directly in front of
          the pair: they move nothing in front of it, so every kept pad
          depends on the code before it only and one pass settles them
          all.  A nop in the path is an executed uop; a branch across the
          boundary is refetched from the legacy decoder every time. }
        if relaxfrozen or
           (assigned(existing) and (existing.spanchanges>=PadChangeLimit)) then
          begin
            nops:=0;
            if assigned(existing) then
              nops:=existing.padbytes-existing.prefixbytes;
            pad:=tai_cpu_abstract(hp).branch_pad_before(ObjData,nops,padstart);
            if (pad=nops) or (pad>=32) then
              exit;
            if not assigned(existing) then
              begin
                existing:=cai_align.create_fixedpad(pad);
                existing.fillsize:=0;
                existing.padbytes:=0;
                currlist.InsertBefore(existing,loc);
                inc(relaxpads);
                inc(passpads);
              end;
            inc(passchanges);
            existing.fillsize:=pad;
            existing.padbytes:=byte(existing.prefixbytes+pad);
            ShiftFrom(loc,hp,pad-nops);
            exit;
          end;
        if assigned(existing) then
          begin
            pad:=tai_cpu_abstract(hp).branch_pad_before(ObjData,existing.padbytes,padstart);
            if pad<>existing.padbytes then
              begin
                inc(existing.spanchanges);
                inc(passchanges);
              end;
            RealizePad(existing,loc,padstart,hp,pad);
            exit;
          end;
        if (pad>0) and (pad<32) then
          begin
            existing:=cai_align.create_fixedpad(pad);
            existing.fillsize:=0;
            existing.padbytes:=0;
            currlist.InsertBefore(existing,loc);
            inc(relaxpads);
            inc(passpads);
            RealizePad(existing,loc,padstart,hp,pad);
          end;
      end;


    { Code placement: the bytes in front of pad are never executed when the
      code before it ends with an unconditional jump or a return (a label
      in between would make them reachable). }
    { An alignment node that emits nothing: the code generator's 1-byte
      alignment in front of a join label.  It separated a target pad from
      the block in front of it, so that every such pad became nops (the
      block was not seen) and no place behind a jump was seen as dead. }
    function TInternalAssembler.EmptyAlign(p:tai):boolean;
      begin
        result:=(p.typ=ait_align) and not tai_align_abstract(p).fixedfill and
                (tai_align_abstract(p).purpose=ap_none) and (tai_align_abstract(p).fillsize=0);
      end;


    function TInternalAssembler.PadIsDead(pad:tai):boolean;
      var
        prev : tai;
      begin
        prev:=tai(pad.previous);
        { a target pad looks through the branch pad that stands in front of
          it (BranchPadHome): behind a jump both are dead }
        while assigned(prev) and ((prev.typ in TransparentInstr) or EmptyAlign(prev) or
              ((prev.typ=ait_align) and tai_align_abstract(prev).fixedfill)) do
          prev:=tai(prev.previous);
        result:=assigned(prev) and (prev.typ=ait_instruction) and
                tai_cpu_abstract(prev).ends_flow;
      end;


    { Code placement: move the labels and instructions from p up to and
      including upto by delta bytes and grow or shrink the section, so that
      the rest of this pass already sees the final positions.  Without this
      every pass could only settle the first changed pad of a chain and
      large units never converged. }
    procedure TInternalAssembler.ShiftFrom(p,upto:tai;delta:longint);
      begin
        if delta=0 then
          exit;
        ObjData.CurrObjSec.Size:=TObjSectionOfs(int64(ObjData.CurrObjSec.Size)+delta);
        while assigned(p) do
          begin
            case p.typ of
              ait_label:
                with ObjData.symbolref(tai_label(p).labsym) do
                  offset:=TObjSectionOfs(int64(offset)+delta);
              ait_instruction:
                tai_cpu_abstract(p).shift_offset(delta);
              else
                ;
            end;
            if p=upto then
              break;
            p:=tai(p.next);
          end;
        layoutchanged:=true;
      end;


    { Code placement: realize a pad of total bytes in front of the pair
      padstart..hp whose pad node existing sits before loc.  A pad costs
      nothing where it is never executed, so dead space (after an
      unconditional jump or a return) and the space in front of a loop head
      (off the loop's own path) stay nops.  Elsewhere the bytes go as DS
      prefixes onto the instructions of the pair's own basic block, nearest
      first, at most three per instruction: a prefix is a free byte for the
      decoder, a nop is an executed uop.  What the block cannot carry stays
      a nop in the pad node. }
    procedure TInternalAssembler.RealizePad(existing:tai_align_abstract;loc,padstart,hp:tai;total:longint);
      var
        q : tai;
        window : array[0..31] of tai_cpu_abstract;
        share : array[0..31] of byte;
        count,i,remaining,delta,prefixes,nops,capacity : longint;
        wantprefix : boolean;
        objsym : TObjSymbol;
      begin
        wantprefix:=(total>0) and not PadIsDead(existing);
        if wantprefix and (loc<>padstart) then
          begin
            q:=loc;
            while assigned(q) and (q<>padstart) do
              begin
                if q.typ=ait_label then
                  begin
                    objsym:=ObjData.symbolref(tai_label(q).labsym);
                    if (prevlayoutpass<>0) and (objsym.looppass=prevlayoutpass) and (objsym.looplen>0) then
                      wantprefix:=false;
                  end;
                q:=tai(q.next);
              end;
          end;
        count:=CollectWindow(padstart,total,window,existing);
        remaining:=0;
        if wantprefix then
          remaining:=total;
        prefixes:=0;
        for i:=0 to count-1 do
          begin
            capacity:=window[i].pad_prefix_capacity;
            if remaining>capacity then
              share[i]:=capacity
            else
              share[i]:=byte(remaining);
            dec(remaining,share[i]);
            inc(prefixes,share[i]);
          end;
        nops:=total-prefixes;
        { The window of a smaller pad is shorter than the window of the
          larger pad it replaces: the walk looks through a forward jump
          only for the bytes still wanted.  Prefixes the pad put behind
          such a jump in an earlier pass would stay where they are, as
          code of their own (the incr_ref_many loop kept 3 of them, grew
          from 44 to 47 bytes, no longer fitted its line from its natural
          place and moved a line down behind 48 nops: managed-static-array
          +19% on the stand).  Take them back first. }
        TakeBackPrefixes(existing,padstart,hp,window,count);
        { apply from the farthest instruction on, moving what follows it }
        for i:=count-1 downto 0 do
          begin
            delta:=window[i].pad_prefix_set(share[i]);
            if share[i]<>0 then
              window[i].padowner:=existing
            else if window[i].padowner=existing then
              window[i].padowner:=nil;
            if delta<>0 then
              ShiftFrom(tai(window[i].next),hp,delta);
          end;
        delta:=nops-existing.fillsize;
        existing.fillsize:=nops;
        existing.padbytes:=byte(total);
        existing.prefixbytes:=byte(prefixes);
        if delta<>0 then
          ShiftFrom(loc,hp,delta);
      end;


    { Code placement: a jump target must not sit in the last 12 bytes of a
      64-byte line (a taken branch into the tail of a line gets a
      shortened fetch block; the UTF-8, Format and Val loops lost 11-22%
      when the first rules dropped every target alignment).  The pad is
      decided every layout pass from the unpadded position of the label
      and realized like a branch pad: prefixes on the block in front,
      nops only where nothing executes them. }
    { Code placement: clear the prefixes the pad existing put on
      instructions that its current window does not reach.  The walk is
      the one of CollectWindow, but every call and forward jump is looked
      through (only the bytes wanted decide that there, and now none are
      wanted behind the window). }
    procedure TInternalAssembler.TakeBackPrefixes(existing:tai_align_abstract;padstart,hp:tai;const window:array of tai_cpu_abstract;count:longint);
      var
        q,pairstart : tai;
        objsym : TObjSymbol;
        i,endofs,delta : longint;
        inwindow : boolean;
      begin
        q:=tai(padstart.previous);
        while assigned(q) do
          begin
            case q.typ of
              ait_instruction:
                begin
                  if tai_cpu_abstract(q).branch_pad_before(ObjData,0,pairstart)>=0 then
                    begin
                      objsym:=tai_cpu_abstract(q).jump_target(ObjData,endofs);
                      if not (tai_cpu_abstract(q).is_call or
                              ((asmblockdepth=0) and assigned(objsym) and (objsym.pass<>ObjData.currpass))) then
                        break;
                    end
                  else if (tai_cpu_abstract(q).padowner=existing) and (tai_cpu_abstract(q).pad_prefix_count<>0) then
                    begin
                      inwindow:=false;
                      for i:=0 to count-1 do
                        if window[i]=q then
                          begin
                            inwindow:=true;
                            break;
                          end;
                      if not inwindow then
                        begin
                          delta:=tai_cpu_abstract(q).pad_prefix_set(0);
                          tai_cpu_abstract(q).padowner:=nil;
                          if delta<>0 then
                            ShiftFrom(tai(q.next),hp,delta);
                        end;
                    end;
                end;
              ait_align:
                if not tai_align_abstract(q).fixedfill and not EmptyAlign(q) then
                  break;
              ait_marker:
                if tai_marker(q).Kind in [mark_AsmBlockStart,mark_AsmBlockEnd] then
                  break;
              ait_label:
                if not (tai_label(q).labsym.labeltype in [alt_dbgline,alt_dbgfile,alt_dbgtype,alt_dbgframe]) then
                  break;
              else
                if not (q.typ in TransparentInstr) then
                  break;
            end;
            q:=tai(q.previous);
          end;
      end;


    { The instructions in front of a pad that can carry its prefixes,
      nearest first: the pad's own basic block - the pad node itself and
      bookkeeping items are looked through, a branch, a jump target or a
      hand-written block ends it.  A call does not end it: the call
      returns to the block, so prefixes in front of the call are on the
      same path; they move the call, which must then still keep to its
      own rule (neither crossing nor ending on a 32-byte boundary) with
      the bytes the block behind the call cannot carry - otherwise the
      window stops at the call as before.  Without this every pad behind
      a call (call; test; jcc, a join after a call) was nops in the path:
      44% of the pad bytes of the compiler, the TList.Exchange loop on the
      stand. }
    function TInternalAssembler.CollectWindow(padstart:tai;total:longint;var window:array of tai_cpu_abstract;owner:tai_align_abstract):longint;
      var
        q,pairstart,skip : tai;
        objsym : TObjSymbol;
        otherpad : tai_align_abstract;
        count,capacity,need,endofs,beyond,i : longint;
      begin
        count:=0;
        capacity:=0;
        skip:=nil;
        q:=tai(padstart.previous);
        while assigned(q) and (count<=high(window)) do
          begin
            case q.typ of
              ait_instruction:
                begin
                  if tai_cpu_abstract(q).branch_pad_before(ObjData,0,pairstart)>=0 then
                    begin
                      { A branch.  A call returns to the block, and a
                        forward jump leaves it only for code behind the
                        pad - either way the bytes in front of the branch
                        are on the path to the pad, so prefixes there cost
                        nothing; they move the branch, which must then
                        still keep to its own rule with what the block
                        behind it cannot carry.  A backward jump (a loop's
                        back-edge) ends the window: prefixes in front of
                        it would grow the loop.  A return or an indirect
                        jump ends it too. }
                      need:=total-capacity;
                      objsym:=tai_cpu_abstract(q).jump_target(ObjData,endofs);
                      { The branch already sits behind the prefixes this
                        pad put in front of it in an earlier pass (the
                        pad's prefix bytes less what the carriers behind
                        the branch carry): its rule is checked for where
                        the new pad would leave it, not for a branch moved
                        twice.  Judged from its moved position, a branch
                        that was fine failed the check in the next pass,
                        the pad lost its window, went to zero, and came
                        back the pass after: an endless alternation. }
                      beyond:=0;
                      if assigned(owner) then
                        begin
                          beyond:=owner.prefixbytes;
                          for i:=0 to count-1 do
                            if window[i].padowner=owner then
                              dec(beyond,window[i].pad_prefix_count);
                        end;
                      { inside a hand-written block only a call is looked
                        through: the bytes in front of its branches belong
                        to the author's layout }
                      { A branch with a pad of its own is not looked
                        through.  That pad is decided from where the branch
                        would stand without it, and prefixes of this pad in
                        front of the branch are part of that place: they
                        take over a part of the branch's pad, the branch's
                        pad shrinks, the place this pad is decided from
                        falls back by as much and this pad grows - the two
                        trade bytes from pass to pass, and when the block
                        cannot carry the last step, this pad drops to zero
                        and the trade starts over.  Each pad then depends
                        on the code in front of it only. }
                      otherpad:=FindBranchPad(pairstart);
                      if (need>0) and
                         (tai_cpu_abstract(q).is_call or
                          ((asmblockdepth=0) and assigned(objsym) and (objsym.pass<>ObjData.currpass))) and
                         not (assigned(otherpad) and (otherpad<>owner) and (otherpad.padbytes>0)) and
                         (tai_cpu_abstract(q).branch_pad_before(ObjData,0,pairstart,need-beyond)=0) then
                        begin
                          { the ALU instruction fused with the jump stays
                            bare: a prefix between the two is not known to
                            keep the fusion }
                          if pairstart<>q then
                            skip:=pairstart;
                        end
                      else
                        break;
                    end
                  { An instruction that carries the prefixes of another pad
                    is not a carrier of this one.  The window of a target
                    pad reaches through a forward jump into the block of
                    that jump, and the jump's own pad - processed first in
                    every pass, zero or not - set the prefixes of its block
                    again and wiped the target pad's: the label fell back
                    by as much, the target pad asked for more in the next
                    pass, and so on until the block could not carry it, the
                    pad went to zero and everything started over (six
                    passes of that in the 16-bit loop of CompareText, until
                    the change limit froze the target pad with 3 of its 5
                    bytes and the target on byte 62 of its line). }
                  else if (q<>skip) and tai_cpu_abstract(q).pad_prefix_ok and
                          ((tai_cpu_abstract(q).padowner=nil) or (tai_cpu_abstract(q).padowner=owner) or
                           (tai_cpu_abstract(q).pad_prefix_count=0)) then
                    begin
                      window[count]:=tai_cpu_abstract(q);
                      inc(capacity,tai_cpu_abstract(q).pad_prefix_capacity);
                      inc(count);
                    end;
                end;
              ait_align:
                if not tai_align_abstract(q).fixedfill and not EmptyAlign(q) then
                  break;
              ait_marker:
                if tai_marker(q).Kind in [mark_AsmBlockStart,mark_AsmBlockEnd] then
                  break;
              ait_label:
                { a debug line label (-gw3 puts one at every source line)
                  is not a jump target and does not end the block }
                if not (tai_label(q).labsym.labeltype in [alt_dbgline,alt_dbgfile,alt_dbgtype,alt_dbgframe]) then
                  break;
              else
                if not (q.typ in TransparentInstr) then
                  break;
            end;
            q:=tai(q.previous);
          end;
        result:=count;
      end;


    { The prefix bytes the block in front of a pad can carry for a pad of
      total bytes: the same window RealizePad fills, bounded per instruction
      by the architectural 15-byte instruction limit. }
    function TInternalAssembler.PrefixCapacity(padstart:tai;total:longint;owner:tai_align_abstract):longint;
      var
        window : array[0..31] of tai_cpu_abstract;
        count,i : longint;
      begin
        count:=CollectWindow(padstart,total,window,owner);
        result:=0;
        for i:=0 to count-1 do
          inc(result,window[i].pad_prefix_capacity);
      end;


    { Code placement: the nops of the branch pad that stands in front of the
      target pad node hp (BranchPadHome puts the pad of the first pair of
      the target's block there). }
    function TInternalAssembler.BranchNopsBefore(hp:tai):longint;
      var
        prev : tai;
      begin
        result:=0;
        prev:=tai(hp.previous);
        while assigned(prev) and ((prev.typ in TransparentInstr) or EmptyAlign(prev)) do
          prev:=tai(prev.previous);
        if assigned(prev) and (prev.typ=ait_align) and tai_align_abstract(prev).fixedfill then
          result:=tai_align_abstract(prev).fillsize;
      end;


    { Code placement: the block that the label behind the target pad node hp
      starts - the plain instructions behind the label and the first branch
      with the instruction fused to it - by the offsets of the previous
      layout pass, without the prefixes the pad of that branch put on it:
      its length, where the pair starts in it, and how many of its
      instructions in front of the pair can carry prefixes.  False when the
      block is not known yet or is no such block (an alignment, a
      hand-written block, more than TargetBlockLimit bytes). }
    function TInternalAssembler.TargetBlock(hp:tai_align_abstract;out blocklen,pairofs,carriers:longint):boolean;
      const
        TargetBlockLimit = 32;
      var
        q,padstart,loc : tai;
        existing : tai_align_abstract;
        objsym : TObjSymbol;
        startofs,endofs,prevend,prevprevend,padprefixes,lastcarrier : longint;
      begin
        result:=false;
        blocklen:=0;
        pairofs:=0;
        carriers:=0;
        lastcarrier:=0;
        startofs:=-1;
        prevend:=0;
        prevprevend:=0;
        q:=tai(hp.next);
        while assigned(q) do
          begin
            case q.typ of
              ait_label:
                if startofs<0 then
                  begin
                    objsym:=ObjData.symbolref(tai_label(q).labsym);
                    if objsym.pass=0 then
                      exit;
                    startofs:=longint(objsym.offset);
                    prevend:=startofs;
                    prevprevend:=startofs;
                  end;
              ait_instruction:
                begin
                  if startofs<0 then
                    exit;
                  { an instruction tells where it ended; it started where
                    the one in front of it ended }
                  tai_cpu_abstract(q).jump_target(ObjData,endofs);
                  if endofs<=prevend then
                    exit;
                  if tai_cpu_abstract(q).branch_pad_before(ObjData,0,padstart)>=0 then
                    begin
                      padprefixes:=0;
                      existing:=BranchPadHome(padstart,loc);
                      if assigned(existing) then
                        begin
                          padprefixes:=existing.prefixbytes;
                          { a pad directly in front of the pair has its
                            nops inside the block }
                          if loc=padstart then
                            dec(endofs,existing.fillsize);
                        end;
                      if padstart=q then
                        pairofs:=prevend-startofs-padprefixes
                      else
                        begin
                          { the fused instruction carries no prefixes }
                          pairofs:=prevprevend-startofs-padprefixes;
                          dec(carriers,lastcarrier);
                        end;
                      blocklen:=endofs-startofs-padprefixes;
                      result:=(pairofs>=0) and (blocklen>pairofs) and (blocklen<=TargetBlockLimit);
                      exit;
                    end;
                  if endofs-startofs>2*TargetBlockLimit then
                    exit;
                  lastcarrier:=tai_cpu_abstract(q).pad_prefix_capacity;
                  inc(carriers,lastcarrier);
                  prevprevend:=prevend;
                  prevend:=endofs;
                end;
              ait_marker:
                if tai_marker(q).Kind in [mark_AsmBlockStart,mark_AsmBlockEnd] then
                  exit;
              ait_align:
                if not tai_align_abstract(q).fixedfill and not EmptyAlign(q) and
                   (tai_align_abstract(q).purpose<>ap_target) then
                  exit;
              else
                if not (q.typ in TransparentInstr) then
                  exit;
            end;
            q:=tai(q.next);
          end;
      end;


    { The pad of a jump target whose label would start at pos without any
      pad - the natural position: without the target pad's own prefixes and
      without the nops of a branch pad in front of the label.  It is the
      bytes up to the next line, and it is taken only when the block in
      front carries all of them as prefixes, or nothing executes the place
      (after a jump or return): a target pad realized as nops in the path
      costs every iteration (the TList.Exchange and CompareText loops on the
      stand: their blocks are a call and a test, and the nops ate what the
      pad gained).

      The pad is wanted
      - when the label sits in the last 12 bytes of a line (the UTF-8,
        Format and Val loops lost 11-22% without it), and
      - when the short block the label starts - up to its first branch,
        with the pad that branch needs from there - would end behind the
        line, or the nops of that pad would push the label into the last 12
        bytes.  The pad of the block's branch stands in front of the label
        (BranchPadHome), so the two decisions meet at the label: taken
        apart, the branch pad moved the label into the last 12 bytes, the
        target pad then moved label and branch to the next line, where the
        branch needed no pad, the label fell back, and the two went on
        until the change limit froze them wherever they were (the back-edge
        block of UnicodeToUtf8Buffer's loop, "L: add; cmp; ja" with L
        reached from every case branch, ended on byte 57 of its line,
        across it, where the RTL at -O2 has it on bytes 0..12:
        TEncoding.GetBytes 1.09 against -O2 on the Ryzen; targets in the
        last 12 bytes of a line in the Win64 Pulse program: 24 before the
        branch pads went in front of their labels, 54 after).  From the
        natural position the answer is the same whatever the branch pad
        currently is. }
    function TInternalAssembler.TargetPadSize(hp:tai_align_abstract;pos:longint):longint;
      var
        blocklen,pairofs,carriers,s,e,need,front : longint;
      begin
        { inside a loop that lies in one line: no pad (MarkLoopTargets) }
        if hp.spanclass=1 then
          begin
            result:=0;
            exit;
          end;
        if (pos and 63)>=52 then
          result:=64-(pos and 63)
        else
          result:=0;
        if (result=0) and TargetBlock(hp,blocklen,pairofs,carriers) then
          begin
            { the pad the block's branch needs with the label at pos }
            s:=pos+pairofs;
            e:=pos+blocklen;
            need:=0;
            if ((s div 32)<>((e-1) div 32)) or ((e mod 32)=0) then
              need:=32-(s mod 32);
            { what the block cannot carry as prefixes stands in front of the label }
            front:=need-carriers;
            if front<0 then
              front:=0;
            if (((pos+blocklen+need-1) div 64)<>(pos div 64)) or
               (((pos+front) and 63)>=52) then
              result:=64-(pos and 63);
          end;
        if (result>0) and not PadIsDead(hp) and (PrefixCapacity(hp,result,hp)<result) then
          result:=0;
      end;


    procedure TInternalAssembler.TargetPad(hp:tai_align_abstract);
      var
        pos,pad : longint;
      begin
        { the old prefixes already sit inside the instructions in front; the
          nops of a branch pad in front of the label are not part of the
          label's natural position (TargetPadSize) }
        pos:=longint(ObjData.CurrObjSec.Size)-hp.prefixbytes-BranchNopsBefore(hp);
        { the decision is taken on 64-byte lines: a section holding a target
          pad must start on a line (a 32-byte aligned section put half of
          the pads on the wrong side of the line) }
        if ObjData.CurrObjSec.secalign<64 then
          ObjData.CurrObjSec.secalign:=64;
        { the old nops first, as every pass allocates them; RealizePad then
          moves by the difference }
        ObjData.alloc(hp.fillsize);
        { A pad that has changed PadChangeLimit times keeps what it has,
          bytes included: realizing the kept size again still moved bytes
          when the window came out differently from pass to pass (the
          prefixes taken back and put again), and the passes never ended
          (system.pp hit the pass limit).

          A pad in dead space is not kept: it is nops behind a jump or
          return, moves nothing in front of itself and so depends on the
          code before it only - it goes on following its label until the
          pass limit.  Kept, it stayed at whatever the eighth change left,
          and that was zero as often as not: the else-branch of an if
          inside a loop, entered by a jump every time, on byte 54 of its
          line behind a jmp (TObject.GetInterfaceEntry, the format and time
          parsers of SysUtils on Linux). }
        if relaxfrozen or
           ((hp.spanchanges>=PadChangeLimit) and not PadIsDead(hp)) then
          exit;
        pad:=TargetPadSize(hp,pos);
        if pad<>hp.padbytes then
          begin
            inc(hp.spanchanges);
            inc(passchanges);
          end;
        RealizePad(hp,hp,hp,hp,pad);
      end;


    function TInternalAssembler.TreePass1(hp:Tai):Tai;
      var
        objsym,
        objsymend : TObjSymbol;
        cpu: tcputype;
        eabi_section: TObjSection;
        inssz : longint;
        runstart,prevtai : tai;
        targetnode : tai_align_abstract;
      begin
        while assigned(hp) do
         begin
{$ifdef DEBUG}
           if not(hp.typ in SkipLineInfo) then
             current_filepos:=tailineinfo(hp).fileinfo;
{$endif DEBUG}
           case hp.typ of
             ait_align :
               begin
                 if tai_align_abstract(hp).fixedfill then
                   begin
                     { the prefix part of the pad sits on the instructions }
                     Tai_align_abstract(hp).fillsize:=Tai_align_abstract(hp).padbytes-Tai_align_abstract(hp).prefixbytes;
                     ObjData.alloc(Tai_align_abstract(hp).fillsize);
                   end
                 else if relaxenabled and (tai_align_abstract(hp).purpose in [ap_proc,ap_loop]) and
                         (oso_executable in ObjData.CurrObjSec.secoptions) then
                   SpanAlign(tai_align_abstract(hp))
                 else if relaxenabled and (tai_align_abstract(hp).purpose=ap_target) and
                         (oso_executable in ObjData.CurrObjSec.secoptions) then
                   TargetPad(tai_align_abstract(hp))
                 else if relaxenabled and (asmblockdepth=0) and
                         (oso_executable in ObjData.CurrObjSec.secoptions) then
                   { an ordinary alignment inside placed code that pass 0
                     did not take over (1-byte alignment); alignments in
                     hand-written assembler blocks are kept as written }
                   Tai_align_abstract(hp).fillsize:=0
                 else if tai_align_abstract(hp).aligntype>1 then
                   begin
                     { here we must determine the fillsize which is used in pass2 }
                     Tai_align_abstract(hp).fillsize:=align(ObjData.CurrObjSec.Size,Tai_align_abstract(hp).aligntype)-
                       ObjData.CurrObjSec.Size;

                     { maximum number of bytes for alignment exceeded? }
                     if (Tai_align_abstract(hp).aligntype<>Tai_align_abstract(hp).maxbytes) and
                       (Tai_align_abstract(hp).fillsize>Tai_align_abstract(hp).maxbytes) then
                       Tai_align_abstract(hp).fillsize:=align(ObjData.CurrObjSec.Size,Byte(Tai_align_abstract(hp).aligntype div 2))-
                         ObjData.CurrObjSec.Size;

                     ObjData.alloc(Tai_align_abstract(hp).fillsize);
                   end;
               end;
             ait_datablock :
               begin
                 if (oso_data in ObjData.CurrObjSec.secoptions) and
                    not (oso_sparse_data in ObjData.CurrObjSec.secoptions) then
                   Message(asmw_e_alloc_data_only_in_bss);
{$ifdef USE_COMM_IN_BSS}
                 if writingpackages and
                    Tai_datablock(hp).is_global then
                   begin
                     objsym:=ObjData.SymbolDefine(Tai_datablock(hp).sym);
                     objsym.size:=Tai_datablock(hp).size;
                     objsym.bind:=AB_COMMON;
                     objsym.alignment:=needtowritealignmentalsoforELF;
                   end
                 else
{$endif USE_COMM_IN_BSS}
                   begin
                     ObjData.allocalign(used_align(size_2_align(Tai_datablock(hp).size),0,ObjData.CurrObjSec.secalign));
                     objsym:=ObjData.SymbolDefine(Tai_datablock(hp).sym);
                     objsym.size:=Tai_datablock(hp).size;
                     ObjData.alloc(Tai_datablock(hp).size);
                   end;
               end;
             ait_realconst:
               ObjData.alloc(tai_realconst(hp).savesize);
             ait_const:
               begin
                 { Recalculate relative symbols }
                 if assigned(tai_const(hp).sym) and
                    assigned(tai_const(hp).endsym) then
                   begin
                     objsym:=Objdata.SymbolRef(tai_const(hp).sym);
                     objsymend:=Objdata.SymbolRef(tai_const(hp).endsym);
                     if Tai_const(hp).consttype in [aitconst_gottpoff,aitconst_tlsgd,aitconst_tlsdesc] then
                       begin
                         if objsymend.objsection<>ObjData.CurrObjSec then
                           Internalerror(2019092801);
                         Tai_const(hp).value:=objsymend.address-ObjData.CurrObjSec.Size+Tai_const(hp).symofs;
                       end
                     else if objsymend.objsection<>objsym.objsection then
                       begin
                         if (Tai_const(hp).consttype in [aitconst_uleb128bit,aitconst_sleb128bit]) or
                            (objsym.objsection<>ObjData.CurrObjSec) then
                           internalerror(200905042);
                       end
{$push} {$R-}{$Q-}
                     else
                       Tai_const(hp).value:=objsymend.address-objsym.address+Tai_const(hp).symofs;
                   end;
{$pop}
                 if (Tai_const(hp).consttype in [aitconst_uleb128bit,aitconst_sleb128bit]) then
                   Tai_const(hp).fixsize;
                 ObjData.alloc(tai_const(hp).size);
               end;
             ait_section:
               begin
                 { use cached value }
                 ObjData.setsection(Tai_section(hp).sec);
               end;
             ait_stab :
               begin
                 if assigned(Tai_stab(hp).str) then
                   WriteStab(Tai_stab(hp).str);
               end;
             ait_symbol :
               ObjData.SymbolDefine(Tai_symbol(hp).sym);
             ait_symbol_end :
               begin
                 objsym:=ObjData.SymbolRef(Tai_symbol_end(hp).sym);
                 objsym.size:=ObjData.CurrObjSec.Size-objsym.offset;
               end;
             ait_symbolpair:
               with tai_symbolpair(hp) do
                 ObjData.SymbolPairDefine(kind,sym^,value^);
             ait_label :
               begin
                 if relaxenabled and (asmblockdepth=0) and (prevlayoutpass<>0) and
                    (oso_executable in ObjData.CurrObjSec.secoptions) and
                    (Tai_label(hp).labsym.labeltype=alt_jump) then
                   begin
                     { a label that a jump reached in the previous layout
                       pass: give it a target pad node unless a placement
                       node (loop head, procedure entry, target pad)
                       already stands in front of it or its label run.
                       Not inside a hand-written block: the layout of such
                       a block belongs to its author (the hand-laid
                       assembler set of the product carries its own pads),
                       and the nops such a pad put behind a jump broke a
                       program that raises and catches exceptions freely
                       (chimera) on both machines. }
                     { a forward jump has already stamped the current pass
                       on its label, a backward jump the previous one }
                     objsym:=ObjData.symbolref(Tai_label(hp).labsym);
                     if (objsym.targetpass=prevlayoutpass) or (objsym.targetpass=ObjData.currpass) then
                       begin
                         runstart:=hp;
                         prevtai:=tai(hp.previous);
                         while assigned(prevtai) and (prevtai.typ in TransparentInstr+[ait_label]) do
                           begin
                             if prevtai.typ=ait_label then
                               runstart:=prevtai;
                             prevtai:=tai(prevtai.previous);
                           end;
                         if not (assigned(prevtai) and (prevtai.typ=ait_align) and
                                 (tai_align_abstract(prevtai).purpose<>ap_none)) then
                           begin
                             targetnode:=cai_align.create(1);
                             targetnode.purpose:=ap_target;
                             currlist.InsertBefore(targetnode,runstart);
                             TargetPad(targetnode);
                           end;
                       end;
                   end;
                 ObjData.SymbolDefine(Tai_label(hp).labsym);
               end;
             ait_string :
               ObjData.alloc(Tai_string(hp).len);
             ait_instruction :
               begin
                 inssz:=Taicpu(hp).Pass1(ObjData);
                 ObjData.alloc(inssz);
                 if relaxenabled then
                   begin
                     { a short backward jump whose target is already out of
                       range in this pass: take the allocation back and
                       encode it as a near jump right away }
                     if tai_cpu_abstract(hp).verify_short_jump(ObjData,true) then
                       begin
                         inc(relaxforced);
                         inc(passforced);
                         ObjData.CurrObjSec.Size:=TObjSectionOfs(int64(ObjData.CurrObjSec.Size)-inssz);
                         ObjData.alloc(Taicpu(hp).Pass1(ObjData));
                         layoutchanged:=true;
                       end;
                     { not inside a hand-written block: the compiler
                       puts no byte of its own into such a block.  Its
                       author may rely on the exact length of the code -
                       mORMot copies its replacement string routines over
                       the RTL's with hard-coded sizes (PatchJmp $3f),
                       and an 8-byte pad the assembler put behind the
                       tail jump of _ansistr_assign pushed its return
                       past that size: the copied routine lost its ret
                       and the program died in the first exception. }
                     if (asmblockdepth=0) and
                        (oso_executable in ObjData.CurrObjSec.secoptions) then
                       ApplyBranchPad(hp);
                     { a backward jump: remember how far the loop reaches
                       for the loop alignment of the next pass }
                     objsym:=tai_cpu_abstract(hp).jump_target(ObjData,inssz);
                     if assigned(objsym) then
                       objsym.targetpass:=ObjData.currpass;
                     if assigned(objsym) and (objsym.pass=ObjData.currpass) then
                       begin
                         if objsym.looppass<>ObjData.currpass then
                           begin
                             objsym.looplen:=0;
                             objsym.looppass:=ObjData.currpass;
                           end;
                         if inssz-longint(objsym.offset)>objsym.looplen then
                           objsym.looplen:=inssz-longint(objsym.offset);
                       end;
                   end;
               end;
             ait_marker :
               case tai_marker(hp).Kind of
                 mark_AsmBlockStart:
                   inc(asmblockdepth);
                 mark_AsmBlockEnd:
                   dec(asmblockdepth);
                 else
                   ;
               end;
             ait_cutobject :
               if SmartAsm then
                break;
             ait_directive :
               begin
                 case tai_directive(hp).directive of
                   asd_indirect_symbol:
                     if tai_directive(hp).name='' then
                       Internalerror(2009101103)
                     else if not SetIndirectToSymbol(Tai(hp.Previous), tai_directive(hp).name) then
                       Internalerror(2009101102);
                   asd_lazy_reference:
                     { handled in TreePass0 }
                     ;
                   asd_reference:
                     { ignore for now, but should be added}
                     ;
                   asd_thumb_func:
                     { ignore for now, but should be added}
                     ;
                   asd_force_thumb:
                     { ignore for now, but should be added}
                     ;
                   asd_code:
                     { ignore for now, but should be added}
                     ;
                   asd_option:
                     { ignore for now, but should be added}
                     ;
                   asd_weak_definition:
                     { ignore for now, but should be added}
                     ;
{$ifdef OMFOBJSUPPORT}
                   asd_omf_linnum_line:
                     { ignore for now, but should be added}
                     ;
{$endif OMFOBJSUPPORT}
                   asd_cpu:
                     begin
                       ObjData.CPUType:=cpu_none;
                       for cpu:=low(tcputype) to high(tcputype) do
                         if cputypestr[cpu]=tai_directive(hp).name then
                           begin
                             ObjData.CPUType:=cpu;
                             break;
                           end;
                     end;
                   else
                     internalerror(2010011102);
                 end;
               end;
             ait_eabi_attribute :
               begin
                 eabi_section:=ObjData.findsection('.ARM.attributes');
                 if not(assigned(eabi_section)) then
                   Internalerror(2019100702);
                 if eabi_section.Size=0 then
                   eabi_section.alloc(16);
                 eabi_section.alloc(LengthUleb128(tai_attribute(hp).tag));
                 case tai_attribute(hp).eattr_typ of
                   eattrtype_dword:
                     eabi_section.alloc(LengthUleb128(tai_attribute(hp).value));
                   eattrtype_ntbs:
                     if assigned(tai_attribute(hp).valuestr) then
                       eabi_section.alloc(Length(tai_attribute(hp).valuestr^)+1)
                     else
                       eabi_section.alloc(1);
                   else
                     Internalerror(2019100703);
                 end;
               end;
{$ifdef WASM}
             ait_functype:
               TWasmObjData(ObjData).DeclareFuncType_Pass1(tai_functype(hp));
             ait_local:
               TWasmObjData(ObjData).DeclareLocals_Pass1(tai_local(hp));
{$endif WASM}
             else
               ;
           end;
           hp:=Tai(hp.next);
         end;
        TreePass1:=hp;
      end;


    function TInternalAssembler.TreePass2(hp:Tai):Tai;
      var
        fillbuffer : tfillbuffer;
        leblen : byte;
        lebbuf : array[0..63] of byte;
        objsym,
        ref,
        objsymend : TObjSymbol;
        zerobuf : array[0..63] of byte;
        relative_reloc: boolean;
        pdata : pointer;
	real_byte_count, index, step : longint;
        ssingle : single;
        ddouble : double;
        {$if defined(cpuextended) and defined(FPC_HAS_TYPE_EXTENDED)}
        eextended : extended;
        {$else}
        {$ifdef USE_SOFT_FLOATX80}
        f32 : float32;
        f64 : float64;
        eextended : floatx80;
        has_gap : boolean;
        gap_ofs_low,gap_ofs_high : byte;
        gap_index, gap_size : byte;
        {$endif}
        {$endif}
{$ifdef FPC_COMP_IS_INT64}
        ccomp: int64;
{$else}
        ccomp: comp;
{$endif}
        comp_data_size : byte;
        tmp    : word;
        cpu: tcputype;
        ddword : dword;
        b : byte;
        w : word;
        d : dword;
        q : qword;
        eabi_section: TObjSection;
        s: String;
        TmpDataPos: TObjSectionOfs;
      begin
        fillchar(zerobuf,sizeof(zerobuf),0);
        fillchar(objsym,sizeof(objsym),0);
        fillchar(objsymend,sizeof(objsymend),0);
{$ifdef USE_SOFT_FLOATX80}
        has_gap:=false;
        gap_index:=0;
        gap_size:=0;
{$endif USE_SOFT_FLOATX80}
        { main loop }
        while assigned(hp) do
         begin
{$ifdef DEBUG}
           if not(hp.typ in SkipLineInfo) then
             current_filepos:=tailineinfo(hp).fileinfo;
{$endif DEBUG}
           case hp.typ of
             ait_align :
               begin
                 if relaxenabled and (tai_align_abstract(hp).fixedfill or (tai_align_abstract(hp).purpose=ap_target)) then
                   begin
                     { branch pad nops and target pad nops are reported
                       apart: the former sit in the executed path of the
                       branch, the latter on the fall-through path into a
                       jump target (the old jumpalign did the same) }
                     if PadIsDead(hp) then
                       inc(relaxdeadnops,tai_align_abstract(hp).fillsize)
                     else if tai_align_abstract(hp).purpose=ap_target then
                       inc(relaxtargetnops,tai_align_abstract(hp).fillsize)
                     else
                       inc(relaxnops,tai_align_abstract(hp).fillsize);
                     if (tai_align_abstract(hp).purpose=ap_target) and (tai_align_abstract(hp).padbytes>0) then
                       inc(relaxtargets);
                   end;
                 if (tai_align_abstract(hp).aligntype>ObjData.CurrObjSec.secalign) and
                    not tai_align_abstract(hp).fixedfill and
                    not (relaxenabled and (oso_executable in ObjData.CurrObjSec.secoptions)) then
                   InternalError(2012072301);
                 if oso_data in ObjData.CurrObjSec.secoptions then
                   ObjData.writebytes(Tai_align_abstract(hp).calculatefillbuf(fillbuffer,oso_executable in ObjData.CurrObjSec.secoptions)^,
                     Tai_align_abstract(hp).fillsize)
                 else
                   ObjData.alloc(Tai_align_abstract(hp).fillsize);
               end;
             ait_section :
               begin
                 { use cached value }
                 ObjData.setsection(Tai_section(hp).sec);
               end;
             ait_symbol :
               begin
                 ObjOutput.exportsymbol(ObjData.SymbolRef(Tai_symbol(hp).sym));
               end;
            ait_symbol_end :
               begin
                 { recalculate size, as some preceding instructions
                   could have been changed to smaller size }
                 objsym:=ObjData.SymbolRef(Tai_symbol_end(hp).sym);
                 objsym.size:=ObjData.CurrObjSec.Size-objsym.offset;
               end;
             ait_datablock :
               begin
                 ObjOutput.exportsymbol(ObjData.SymbolRef(Tai_datablock(hp).sym));
{$ifdef USE_COMM_IN_BSS}
                 if not(writingpackages and
                        Tai_datablock(hp).is_global) then
{$endif USE_COMM_IN_BSS}
                   begin
                     ObjData.allocalign(used_align(size_2_align(Tai_datablock(hp).size),0,ObjData.CurrObjSec.secalign));
                     ObjData.alloc(Tai_datablock(hp).size);
                   end;
               end;
             ait_realconst:
               begin
                 real_byte_count:=tai_realconst(hp).datasize;
                 case tai_realconst(hp).realtyp of
                   aitrealconst_s32bit:
                     begin
                       ssingle:=single(tai_realconst(hp).value.s32val);
                       pdata:=@ssingle;
                     end;
                   aitrealconst_s64bit:
                     begin
                       ddouble:=double(tai_realconst(hp).value.s64val);
                       pdata:=@ddouble;
                     end;
         {$if defined(cpuextended) and defined(FPC_HAS_TYPE_EXTENDED)}
                   { can't write full 80 bit floating point constants yet on non-x86 }
                   aitrealconst_s80bit:
                     begin
                       eextended:=extended(tai_realconst(hp).value.s80val);
                       pdata:=@eextended;
                     end;
         {$else}
         {$ifdef USE_SOFT_FLOATX80}
           {$push}{$warn 6018 off} { Unreachable code due to compile time evaluation }
                   aitrealconst_s80bit:
                     begin
                       if sizeof(tai_realconst(hp).value.s80val) = sizeof(double) then
                         begin
                           f64:=float64(double(tai_realconst(hp).value.s80val));
                           if float64_is_signaling_nan(f64)<>0 then
                             begin
                               f64.low := 0;
                               f64.high := longword($fff80000);
                             end;
                           eextended:=float64_to_floatx80(f64);
                         end
                       else if sizeof(tai_realconst(hp).value.s80val) = sizeof(single) then
                         begin
                           f32:=float32(single(tai_realconst(hp).value.s80val));
                           if float32_is_signaling_nan(f32)<>0 then
                             begin
                               f32 := longword($ffc00000);
                             end;
                           eextended:=float32_to_floatx80(f32);
                         end
                       else
                         internalerror(2017091903);
                       pdata:=@eextended;
                       if sizeof(eextended)>10 then
                         begin
                           gap_ofs_high:=(pbyte(@eextended.high) - pbyte(@eextended));
                           gap_ofs_low:=(pbyte(@eextended.low) - pbyte(@eextended));
                           if (gap_ofs_low<gap_ofs_high) then
                             begin
                               gap_index:=gap_ofs_low+sizeof(eextended.low);
                               gap_size:=gap_ofs_high-gap_index;
                             end
                           else
                             begin
                               gap_index:=gap_ofs_high+sizeof(eextended.high);
                               gap_size:=gap_ofs_low-gap_index;
                             end;
                           if source_info.endian<>target_info.endian then
                             gap_index:=gap_index+gap_size-1;
                           has_gap:=gap_size <> 0;
                         end
                       else
                         has_gap:=false;
                     end;
           {$pop}
         {$endif}
         {$endif cpuextended}
                   aitrealconst_s64comp:
                     begin
{$ifdef FPC_COMP_IS_INT64}
                       ccomp:=system.trunc(tai_realconst(hp).value.s64compval);
{$else}
                       ccomp:=comp(tai_realconst(hp).value.s64compval);
{$endif}
                       pdata:=@ccomp;
                     end;
                   else
                     internalerror(2015030501);
                 end;
                 if source_info.endian<>target_info.endian then
                   { write bytes in inverse order if source and target endianess don't match }
                   begin
                     { go from back to front }
{$ifdef USE_SOFT_FLOATX80}
                     if has_gap then
                       index:=sizeof(eextended)-1
                     else
{$endif USE_SOFT_FLOATX80}
                       index:=real_byte_count-1;
                     step:=-1;
                   end
                 else
                   begin
                     index:=0;
                     step:=1;
                   end;
                 if (source_info.endian<>target_info.endian)
                   {$ifdef USE_SOFT_FLOATX80} or has_gap{$endif} then
                   begin
                     d:=0;
                     repeat
{$ifdef USE_SOFT_FLOATX80}
                       if has_gap and (index=gap_index) then
                         index:=index+step*gap_size;
{$endif USE_SOFT_FLOATX80}
                       lebbuf[d]:=pbyte(pdata)[index];
                       inc(index,step);
                       dec(real_byte_count);
                       inc(d);
                     until real_byte_count=0;
		     { d now bares the count value }
                     pdata:=@lebbuf;
                     ObjData.writebytes(pdata^,d);
                     ObjData.writebytes(zerobuf,tai_realconst(hp).savesize-d);
                   end
		 else
                   begin
                     ObjData.writebytes(pdata^,tai_realconst(hp).datasize);
                     ObjData.writebytes(zerobuf,tai_realconst(hp).savesize-tai_realconst(hp).datasize);
		   end;
               end;
             ait_string :
               ObjData.writebytes(Tai_string(hp).str,Tai_string(hp).len);
             ait_const :
               begin
                 { Recalculate relative symbols, addresses of forward references
                   can be changed in treepass1 }
                 relative_reloc:=false;
                 if assigned(tai_const(hp).sym) and
                    assigned(tai_const(hp).endsym) then
                   begin
                     objsym:=Objdata.SymbolRef(tai_const(hp).sym);
                     objsymend:=Objdata.SymbolRef(tai_const(hp).endsym);
                     relative_reloc:=(objsym.objsection<>objsymend.objsection);
                     if Tai_const(hp).consttype in [aitconst_gottpoff] then
                       begin
                         if objsymend.objsection<>ObjData.CurrObjSec then
                           Internalerror(2019092802);
                         Tai_const(hp).value:=objsymend.address-ObjData.CurrObjSec.Size+Tai_const(hp).symofs;
                       end
                     else if Tai_const(hp).consttype in [aitconst_tlsgd,aitconst_tlsdesc] then
                       begin
                         if objsymend.objsection<>ObjData.CurrObjSec then
                           Internalerror(2019092803);
                         Tai_const(hp).value:=ObjData.CurrObjSec.Size-objsymend.address+Tai_const(hp).symofs;
                       end
                     else if objsymend.objsection<>objsym.objsection then
                       begin
                         if (Tai_const(hp).consttype in [aitconst_uleb128bit,aitconst_sleb128bit]) or
                            (objsym.objsection<>ObjData.CurrObjSec) then
                           internalerror(2019010301);
                       end
                     else
{$push} {$R-}{$Q-}
                       Tai_const(hp).value:=objsymend.address-objsym.address+Tai_const(hp).symofs;
                   end;
{$pop}
                 case tai_const(hp).consttype of
                   aitconst_64bit,
                   aitconst_32bit,
                   aitconst_16bit,
                   aitconst_64bit_unaligned,
                   aitconst_32bit_unaligned,
                   aitconst_16bit_unaligned,
                   aitconst_8bit :
                     begin
                       if assigned(tai_const(hp).sym) and
                          not assigned(tai_const(hp).endsym) then
                         ObjData.writereloc(Tai_const(hp).symofs,tai_const(hp).size,Objdata.SymbolRef(tai_const(hp).sym),RELOC_ABSOLUTE)
                       else if relative_reloc then
                         ObjData.writereloc(ObjData.CurrObjSec.size+tai_const(hp).size-objsym.address+tai_const(hp).symofs,tai_const(hp).size,objsymend,RELOC_RELATIVE)
                       else
                         if source_info.endian<>target_info.endian then
                           begin
                             case tai_const(hp).size of
                                1 : begin
                                      b:=byte(Tai_const(hp).value);
                                      ObjData.writebytes(b,1);
                                    end;
                                2 : begin
                                      w:=word(Tai_const(hp).value);
                                      w:=swapendian(w);
                                      ObjData.writebytes(w,2);
                                    end;
                                4 : begin
                                      d:=dword(Tai_const(hp).value);
                                      d:=swapendian(d);
                                      ObjData.writebytes(d,4);
                                    end;
                                8 : begin
                                      q:=qword(Tai_const(hp).value);
                                      q:=swapendian(q);
                                      ObjData.writebytes(q,8);
                                    end;
                             else
                               internalerror(2024012502);
                             end;
                           end
                         else
                           ObjData.writebytes(Tai_const(hp).value,tai_const(hp).size);
                     end;
                   aitconst_rva_symbol :
                     begin
                       { PE32+? }
                       if target_info.system in systems_peoptplus then
                         ObjData.writereloc(Tai_const(hp).symofs,sizeof(longint),Objdata.SymbolRef(tai_const(hp).sym),RELOC_RVA)
                       else
                         ObjData.writereloc(Tai_const(hp).symofs,sizeof(pint),Objdata.SymbolRef(tai_const(hp).sym),RELOC_RVA);
                     end;
                   aitconst_secrel32_symbol :
                     begin
                       { Required for DWARF2 support under Windows }
                       ObjData.writereloc(Tai_const(hp).symofs,sizeof(longint),Objdata.SymbolRef(tai_const(hp).sym),RELOC_SECREL32);
                     end;
{$ifdef i8086}
                   aitconst_farptr :
                     if assigned(tai_const(hp).sym) and
                        not assigned(tai_const(hp).endsym) then
                       ObjData.writereloc(Tai_const(hp).symofs,tai_const(hp).size,Objdata.SymbolRef(tai_const(hp).sym),RELOC_FARPTR)
                     else if relative_reloc then
                       internalerror(2015040601)
                     else
                       ObjData.writebytes(Tai_const(hp).value,tai_const(hp).size);
                   aitconst_seg:
                     if assigned(tai_const(hp).sym) and (tai_const(hp).size=2) then
                       ObjData.writereloc(0,2,Objdata.SymbolRef(tai_const(hp).sym),RELOC_SEG)
                     else
                       internalerror(2015110502);
                   aitconst_dgroup:
                     ObjData.writereloc(0,2,nil,RELOC_DGROUP);
                   aitconst_fardataseg:
                     ObjData.writereloc(0,2,nil,RELOC_FARDATASEG);
{$endif i8086}
{$ifdef arm}
                   aitconst_got:
                     ObjData.writereloc(Tai_const(hp).symofs,sizeof(longint),Objdata.SymbolRef(tai_const(hp).sym),RELOC_GOT32);
{                   aitconst_gottpoff:
                     ObjData.writereloc(Tai_const(hp).symofs,sizeof(longint),Objdata.SymbolRef(tai_const(hp).sym),RELOC_TPOFF); }
                   aitconst_tpoff:
                     ObjData.writereloc(Tai_const(hp).symofs,sizeof(longint),Objdata.SymbolRef(tai_const(hp).sym),RELOC_TPOFF);
                   aitconst_tlsgd:
                     ObjData.writereloc(Tai_const(hp).symofs,sizeof(longint),Objdata.SymbolRef(tai_const(hp).sym),RELOC_TLSGD);
                   aitconst_tlsdesc:
                     begin
                       { must be a relative symbol, thus value being valid }
                       if not(assigned(tai_const(hp).sym)) or not(assigned(tai_const(hp).endsym)) then
                         Internalerror(2019092904);
                       ObjData.writereloc(Tai_const(hp).value,sizeof(longint),Objdata.SymbolRef(tai_const(hp).sym),RELOC_TLSDESC);
                     end;
{$endif arm}
                   aitconst_dtpoff:
                     { so far, the size of dtpoff is fixed to 4 bytes }
                     ObjData.writereloc(Tai_const(hp).symofs,4,Objdata.SymbolRef(tai_const(hp).sym),RELOC_DTPOFF);
                   aitconst_gotoff_symbol:
                     ObjData.writereloc(Tai_const(hp).symofs,sizeof(longint),Objdata.SymbolRef(tai_const(hp).sym),RELOC_GOTOFF);
                   aitconst_uleb128bit,
                   aitconst_sleb128bit :
                     begin
                       if Tai_const(hp).fixed_size=0 then
                         Internalerror(2019030302);
                       if tai_const(hp).consttype=aitconst_uleb128bit then
                         leblen:=EncodeUleb128(qword(Tai_const(hp).value),lebbuf,Tai_const(hp).fixed_size)
                       else
                         leblen:=EncodeSleb128(Tai_const(hp).value,lebbuf,Tai_const(hp).fixed_size);
                       if leblen<>tai_const(hp).fixed_size then
                         internalerror(200709271);
                       ObjData.writebytes(lebbuf,leblen);
                     end;
                   aitconst_darwin_dwarf_delta32,
                   aitconst_darwin_dwarf_delta64:
                     ObjData.writebytes(Tai_const(hp).value,tai_const(hp).size);
                   aitconst_half16bit,
                   aitconst_gs:
                     begin
                       tmp:=Tai_const(hp).value div 2;
                       ObjData.writebytes(tmp,2);
                     end;
                   else
                     internalerror(200603254);
                 end;
               end;
             ait_label :
               begin
                 { exporting shouldn't be necessary as labels are local,
                   but it's better to be on the safe side (PFV) }
                 ObjOutput.exportsymbol(ObjData.SymbolRef(Tai_label(hp).labsym));
               end;
             ait_instruction :
               begin
                 if relaxenabled then
                   inc(relaxprefixes,tai_cpu_abstract(hp).pad_prefix_count);
                 Taicpu(hp).Pass2(ObjData);
               end;
             ait_stab :
               WriteStab(Tai_stab(hp).str);
             ait_function_name,
             ait_force_line : ;
             ait_cutobject :
               if SmartAsm then
                break;
             ait_directive :
               begin
                 case tai_directive(hp).directive of
                   asd_weak_definition,
                   asd_weak_reference:
                     begin
                       objsym:=ObjData.symbolref(tai_directive(hp).name);
                       if objsym.bind in [AB_EXTERNAL,AB_WEAK_EXTERNAL] then
                         objsym.bind:=AB_WEAK_EXTERNAL
                       else
                         { TODO: should become a weak definition; for now, do
                             the same as what was done for ait_weak }
                         objsym.bind:=AB_WEAK_EXTERNAL;
                     end;
                   asd_cpu:
                     begin
                       ObjData.CPUType:=cpu_none;
                       for cpu:=low(tcputype) to high(tcputype) do
                         if cputypestr[cpu]=tai_directive(hp).name then
                           begin
                             ObjData.CPUType:=cpu;
                             break;
                           end;
                     end;
{$ifdef OMFOBJSUPPORT}
                   asd_omf_linnum_line:
                     begin
                       TOmfObjSection(ObjData.CurrObjSec).LinNumEntries.Add(
                         TOmfSubRecord_LINNUM_MsLink_Entry.Create(
                           strtoint(tai_directive(hp).name),
                           ObjData.CurrObjSec.Size
                         ));
                     end;
{$endif OMFOBJSUPPORT}
                   else
                     ;
                 end
               end;
             ait_symbolpair:
               begin
                 if tai_symbolpair(hp).kind=spk_set then
                   begin
                     objsym:=ObjData.symbolref(tai_symbolpair(hp).sym^);
                     ref:=objdata.symbolref(tai_symbolpair(hp).value^);

                     objsym.offset:=ref.offset;
                     objsym.objsection:=ref.objsection;
{$ifdef arm}
                     objsym.ThumbFunc:=ref.ThumbFunc;
{$endif arm}
                   end;
               end;
{$ifndef DISABLE_WIN64_SEH}
             ait_seh_directive :
               tai_seh_directive(hp).generate_code(objdata);
{$endif DISABLE_WIN64_SEH}
             ait_eabi_attribute :
               begin
                 eabi_section:=ObjData.findsection('.ARM.attributes');
                 if not(assigned(eabi_section)) then
                   Internalerror(2019100704);
                 if eabi_section.Size=0 then
                   begin
                     s:='A';
                     eabi_section.write(s[1],1);
                     ddword:=eabi_section.Size-1;
                     if source_info.endian<>target_info.endian then
                       ddword:=SwapEndian(ddword);
                     eabi_section.write(ddword,4);
                     s:='aeabi'#0;
                     eabi_section.write(s[1],6);
                     s:=#1;
                     eabi_section.write(s[1],1);
                     ddword:=eabi_section.Size-1-4-6-1;
                     if source_info.endian<>target_info.endian then
                       ddword:=SwapEndian(ddword);
                     eabi_section.write(ddword,4);
                   end;
                 leblen:=EncodeUleb128(tai_attribute(hp).tag,lebbuf,0);
                 eabi_section.write(lebbuf,leblen);

                 case tai_attribute(hp).eattr_typ of
                   eattrtype_dword:
                     begin
                       leblen:=EncodeUleb128(tai_attribute(hp).value,lebbuf,0);
                       eabi_section.write(lebbuf,leblen);
                     end;
                   eattrtype_ntbs:
                     begin
                       if assigned(tai_attribute(hp).valuestr) then
                         s:=tai_attribute(hp).valuestr^+#0
                       else
                         s:=#0;
                       eabi_section.write(s[1],Length(s));
                     end
                   else
                     Internalerror(2019100705);
                 end;
                 { update size of attributes section, write directly to the dyn. arrays as
                   we do not increase the size of section }
                 TmpDataPos:=eabi_section.Data.Pos;
                 eabi_section.Data.seek(1);
                 ddword:=eabi_section.Size-1;
                 if source_info.endian<>target_info.endian then
                   ddword:=SwapEndian(ddword);
                 eabi_section.Data.write(ddword,4);
                 eabi_section.Data.seek(12);
                 ddword:=eabi_section.Size-1-4-6;
                 if source_info.endian<>target_info.endian then
                   ddword:=SwapEndian(ddword);
                 eabi_section.Data.write(ddword,4);
                 eabi_section.Data.Seek(TmpDataPos);
               end;
{$ifdef WASM}
             ait_functype:
               TWasmObjData(ObjData).DeclareFuncType_Pass2(tai_functype(hp));
             ait_local:
               TWasmObjData(ObjData).WriteLocals_Pass2(tai_local(hp));
{$endif WASM}
             else
               ;
           end;
           hp:=Tai(hp.next);
         end;
        TreePass2:=hp;
      end;


    procedure TInternalAssembler.writetree;
      label
        doexit;
      const
        RelaxPassLimit = 64;
      var
        hp : Tai;
        ObjWriter : TObjectWriter;
        relaxpass : byte;
        stablepasses : longint;

      procedure Pass1Lists(passno:byte);
        begin
          prevlayoutpass:=lastlayoutpass;
          lastlayoutpass:=passno;
          relaxspans:=0;
          relaxprefixes:=0;
          relaxnops:=0;
          relaxdeadnops:=0;
          relaxtargets:=0;
          relaxtargetnops:=0;
          ObjData.currpass:=passno;
          ObjData.resetsections;
          ObjData.beforealloc;
          ObjData.createsection(sec_code);
          { start with list 1 }
          currlistidx:=1;
          currlist:=list[currlistidx];
          hp:=Tai(currList.first);
          while assigned(hp) do
           begin
             hp:=TreePass1(hp);
             MaybeNextList(hp);
           end;
          ObjData.createsection(sec_code);
          ObjData.afteralloc;
          if relaxenabled then
            begin
              currlistidx:=1;
              currlist:=list[currlistidx];
              if VerifyShortJumps(Tai(currList.first),false) then
                layoutchanged:=true;
            end;
        end;

      begin
        ObjWriter:=TObjectwriter.create;
        ObjOutput:=CObjOutput.Create(ObjWriter);
        ObjData:=ObjOutput.newObjData(ObjFileName);

        { Pass 0 }
        asmblockdepth:=0;
        ObjData.currpass:=0;
        ObjData.createsection(sec_code);
        ObjData.beforealloc;
        { start with list 1 }
        currlistidx:=1;
        currlist:=list[currlistidx];
        hp:=Tai(currList.first);
        while assigned(hp) do
         begin
           hp:=TreePass0(hp);
           MaybeNextList(hp);
         end;
        ObjData.afteralloc;
        { leave if errors have occurred }
        if errorcount>0 then
         goto doexit;

        { Pass 1 }
        relaxfrozen:=false;
        layoutchanged:=false;
        asmblockdepth:=0;
        lastlayoutpass:=0;
        ObjData.relaxing:=relaxenabled;
        Pass1Lists(1);
        if relaxenabled then
          TracePass(1);

        { leave if errors have occurred }
        if errorcount>0 then
         goto doexit;

        { code placement: repeat pass 1 until the padding no longer moves
          anything; every pass uses a fresh pass number so that symbol
          redefinition is not reported as a duplicate label }
        if relaxenabled and layoutchanged then
          begin
            ObjData.relaxing:=true;
            relaxpass:=3;
            stablepasses:=0;
            repeat
              layoutchanged:=false;
              asmblockdepth:=0;
              { after the pass limit only jump encodings may still change,
                and they only ever grow, so the loop terminates }
              relaxfrozen:=relaxpass>=RelaxPassLimit;
              Pass1Lists(relaxpass);
              TracePass(relaxpass);
              if errorcount>0 then
                goto doexit;
              if layoutchanged then
                stablepasses:=0
              else
                inc(stablepasses);
              inc(relaxpass);
              if relaxpass>200 then
                internalerror(2026091401);
            until stablepasses>=2;
            if relaxpass-3>relaxpasses then
              relaxpasses:=relaxpass-3;
            ObjData.relaxing:=false;
            relaxfrozen:=false;
          end;

        { Pass 2 }
        ObjData.relaxing:=false;
        ObjData.currpass:=2;
        ObjData.resetsections;
        ObjData.beforewrite;
        ObjData.createsection(sec_code);
        { start with list 1 }
        currlistidx:=1;
        currlist:=list[currlistidx];
        hp:=Tai(currList.first);
        while assigned(hp) do
         begin
           hp:=TreePass2(hp);
           MaybeNextList(hp);
         end;
        ObjData.createsection(sec_code);
        ObjData.afterwrite;

        { don't write the .o file if errors have occurred }
        if errorcount=0 then
         begin
           { write objectfile }
           ObjOutput.startobjectfile(ObjFileName);
           ObjOutput.writeobjectfile(ObjData);
         end;

      doexit:
        { Cleanup }
        ObjData.free;
        ObjData:=nil;
        ObjWriter.free;
        ObjWriter := nil;
      end;


    procedure TInternalAssembler.writetreesmart;
      const
        RelaxPassLimit = 64;
      var
        hp : Tai;
        startsectype : TAsmSectiontype;
        place: tcutplace;
        ObjWriter : TObjectWriter;
        startsecname: String;
        startsecorder: TAsmSectionOrder;
        relaxpass : byte;
        stablepasses : longint;

      procedure Pass1Chunk(passno:byte);
        begin
          prevlayoutpass:=lastlayoutpass;
          lastlayoutpass:=passno;
          relaxspans:=0;
          relaxprefixes:=0;
          relaxnops:=0;
          relaxdeadnops:=0;
          relaxtargets:=0;
          relaxtargetnops:=0;
          ObjData.currpass:=passno;
          ObjData.resetsections;
          ObjData.beforealloc;
          if startsectype<>sec_none then
            ObjData.CreateSection(startsectype,startsecname,startsecorder);
          TreePass1(hp);
          ObjData.afteralloc;
          if relaxenabled and VerifyShortJumps(hp,true) then
            layoutchanged:=true;
        end;

      begin
        if not(cs_asm_leave in current_settings.globalswitches) and
           not(af_needar in asminfo^.flags) then
          ObjWriter:=CInternalAr.CreateAr(current_module.staticlibfilename)
        else
          ObjWriter:=TObjectwriter.create;

        NextSmartName(cut_normal);
        ObjOutput:=CObjOutput.Create(ObjWriter);
        startsectype:=sec_none;
        startsecname:='';
        startsecorder:=secorder_default;

        { start with list 1 }
        currlistidx:=1;
        currlist:=list[currlistidx];
        hp:=Tai(currList.first);
        while assigned(hp) do
         begin
           ObjData:=ObjOutput.newObjData(ObjFileName);

           { Pass 0 }
           asmblockdepth:=0;
           ObjData.currpass:=0;
           ObjData.resetsections;
           ObjData.beforealloc;
           if startsectype<>sec_none then
             ObjData.CreateSection(startsectype,startsecname,startsecorder);
           TreePass0(hp);
           ObjData.afteralloc;
           { leave if errors have occurred }
           if errorcount>0 then
             break;

           { Pass 1 }
           relaxfrozen:=false;
           layoutchanged:=false;
           asmblockdepth:=0;
           lastlayoutpass:=0;
           ObjData.relaxing:=relaxenabled;
           Pass1Chunk(1);
           if relaxenabled then
             TracePass(1);

           { leave if errors have occurred }
           if errorcount>0 then
             break;

           { code placement relaxation, see writetree }
           if relaxenabled and layoutchanged then
             begin
               ObjData.relaxing:=true;
               relaxpass:=3;
               stablepasses:=0;
               repeat
                 layoutchanged:=false;
                 asmblockdepth:=0;
                 relaxfrozen:=relaxpass>=RelaxPassLimit;
                 Pass1Chunk(relaxpass);
                 TracePass(relaxpass);
                 if errorcount>0 then
                   break;
                 if layoutchanged then
                   stablepasses:=0
                 else
                   inc(stablepasses);
                 inc(relaxpass);
                 if relaxpass>200 then
                   internalerror(2026091402);
               until stablepasses>=2;
               if relaxpass-3>relaxpasses then
                 relaxpasses:=relaxpass-3;
               ObjData.relaxing:=false;
               relaxfrozen:=false;
               if errorcount>0 then
                 break;
             end;

           { Pass 2 }
           ObjData.relaxing:=false;
           ObjData.currpass:=2;
           ObjOutput.startobjectfile(ObjFileName);
           ObjData.resetsections;
           ObjData.beforewrite;
           if startsectype<>sec_none then
             ObjData.CreateSection(startsectype,startsecname,startsecorder);
           hp:=TreePass2(hp);
           ObjData.afterwrite;

           { leave if errors have occurred }
           if errorcount>0 then
             break;

           { write the current objectfile }
           ObjOutput.writeobjectfile(ObjData);
           ObjData.free;
           ObjData:=nil;

           { end of lists? }
           if not MaybeNextList(hp) then
             break;

           { we will start a new objectfile so reset everything }
           { The place can still change in the next while loop, so don't init }
           { the writer yet (JM)                                              }
           if (hp.typ=ait_cutobject) then
             place := Tai_cutobject(hp).place
           else
             place := cut_normal;

           { avoid empty files }
           startsectype:=sec_none;
           startsecname:='';
           startsecorder:=secorder_default;
           while assigned(hp) and
                 (Tai(hp).typ in [ait_marker,ait_comment,ait_section,ait_cutobject]) do
            begin
              if Tai(hp).typ=ait_section then
                begin
                  startsectype:=Tai_section(hp).sectype;
                  startsecname:=Tai_section(hp).name^;
                  startsecorder:=Tai_section(hp).secorder;
                end;
              if (Tai(hp).typ=ait_cutobject) then
                place:=Tai_cutobject(hp).place;
              hp:=Tai(hp.next);
            end;

           if not MaybeNextList(hp) then
             break;

           { start next objectfile }
           NextSmartName(place);
         end;
        ObjData.free;
        ObjData:=nil;
        ObjWriter.free;
        ObjWriter := nil;
      end;


    procedure TInternalAssembler.MakeObject;

    var to_do:set of TasmlistType;
        i:TasmlistType;

        procedure addlist(p:TAsmList);
        begin
          inc(lists);
          list[lists]:=p;
        end;

      begin
        to_do:=[low(Tasmlisttype)..high(Tasmlisttype)];
        if usedeffileforexports then
          exclude(to_do,al_exports);
        if not(tf_section_threadvars in target_info.flags) then
          exclude(to_do,al_threadvars);
        for i:=low(TasmlistType) to high(TasmlistType) do
          if (i in to_do) and (current_asmdata.asmlists[i]<>nil) and
             (not current_asmdata.asmlists[i].empty) then
            addlist(current_asmdata.asmlists[i]);

        if SmartAsm then
          writetreesmart
        else
          writetree;
        if relaxenabled then
          Comment(V_Debug,'Code placement: branch pads '+tostr(relaxpads)+
            ', jumps forced near '+tostr(relaxforced)+
            ', relaxation passes '+tostr(relaxpasses)+
            ', span alignments '+tostr(relaxspans)+
            ', pad bytes as prefixes '+tostr(relaxprefixes)+
            ', as nops '+tostr(relaxnops)+
            ' (dead '+tostr(relaxdeadnops)+')'+
            ', target pads '+tostr(relaxtargets)+
            ' (nop bytes '+tostr(relaxtargetnops)+')');
      end;


{*****************************************************************************
                     Generate Assembler Files Main Procedure
*****************************************************************************}

    Procedure GenerateAsm(smart:boolean);
      var
        a : TAssembler;
      begin
        if not assigned(CAssembler[target_asm.id]) then
          Message(asmw_f_assembler_output_not_supported);
        a:=CAssembler[target_asm.id].Create(@target_asm,smart);
        a.MakeObject;
        a.Free;
        a := nil;
      end;


    function GetExternalGnuAssemblerWithAsmInfoWriter(info: pasminfo; wr: TExternalAssemblerOutputFile): TExternalAssembler;
      var
        asmkind: tasm;
      begin
        for asmkind in [as_gas,as_ggas,as_darwin,as_clang_gas,as_clang_asdarwin] do
          if assigned(asminfos[asmkind]) and
             (target_info.system in asminfos[asmkind]^.supported_targets) then
            begin
              result:=TExternalAssemblerClass(CAssembler[asmkind]).CreateWithWriter(asminfos[asmkind],wr,false,false);
              exit;
            end;
        Internalerror(2015090604);
      end;

{*****************************************************************************
                                 Init/Done
*****************************************************************************}

    procedure RegisterAssembler(const r:tasminfo;c:TAssemblerClass);
      var
        t : tasm;
      begin
        t:=r.id;
        if assigned(asminfos[t]) then
          writeln('Warning: Assembler is already registered!')
        else
          new(asminfos[t]);
        asminfos[t]^:=r;
        CAssembler[t]:=c;
      end;

end.
