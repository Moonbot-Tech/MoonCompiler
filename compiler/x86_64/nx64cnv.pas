{
    Copyright (c) 1998-2002 by Florian Klaempfl

    Generate x86-64 assembler for type converting nodes

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
unit nx64cnv;

{$i fpcdefs.inc}

interface

    uses
      node,defutil,pass_1,
      nx86cnv;

    type
       tx8664typeconvnode = class(tx86typeconvnode)
         protected
         function first_nothing : tnode;override;
         procedure second_int_to_int;override;
         { procedure second_string_to_string;override; }
         { procedure second_cstring_to_pchar;override; }
         { procedure second_string_to_chararray;override; }
         { procedure second_array_to_pointer;override; }
         { procedure second_pointer_to_array;override; }
         { procedure second_chararray_to_string;override; }
         { procedure second_char_to_string;override; }
         { function first_int_to_real: tnode; override; }
         function first_int_to_real : tnode;override;
         procedure second_int_to_real;override;
         { procedure second_real_to_real;override; }
         { procedure second_cord_to_pointer;override; }
         { procedure second_proc_to_procvar;override; }
         { procedure second_bool_to_int;override; }
         { procedure second_int_to_bool;override; }
         { procedure second_load_smallset;override;  }
         { procedure second_ansistring_to_pchar;override; }
         { procedure second_pchar_to_string;override; }
         { procedure second_class_to_intf;override;  }
         { procedure second_char_to_char;override; }
       end;


implementation

    uses
      verbose,globals,globtype,
      aasmbase,aasmtai,aasmdata,aasmcpu,
      symconst,symdef,
      cgbase,cga,
      ncnv,
      cpubase,cpuinfo,
      cgutils,cgobj,hlcgobj,cgx86;


    function tx8664typeconvnode.first_nothing : tnode;
      begin
        result:=nil;
        { If typecasting between a Single or Double and a record of equal size,
          we can use MOVD and MOVQ }
        if (resultdef.typ in [recorddef,orddef]) and
          use_vectorfpu(left.resultdef) and
          (resultdef.size=left.resultdef.size) then
          expectloc:=LOC_MMREGISTER
        else if (left.resultdef.typ in [recorddef,orddef]) and
          use_vectorfpu(resultdef) and
          (resultdef.size=left.resultdef.size) then
          expectloc:=LOC_REGISTER
        else
          result:=inherited first_nothing;
      end;


    procedure tx8664typeconvnode.second_int_to_int;
      var
        newsize : tcgsize;
      begin
        { 128 bit conversions are done on register pairs }
        if is_128bit(resultdef) and
           (left.resultdef.size<resultdef.size) then
          begin
            { insert range check if not explicit or internally generated conversion }
            if (flags*[nf_explicit,nf_internal])=[] then
              hlcg.g_rangecheck(current_asmdata.CurrAsmList,left.location,left.resultdef,resultdef);
            location_copy(location,left.location);
            hlcg.location_force_reg(current_asmdata.CurrAsmList,location,left.resultdef,resultdef,true);
            exit;
          end;
        if is_128bit(left.resultdef) and
           (resultdef.size<left.resultdef.size) and
           (left.location.loc in [LOC_REGISTER,LOC_CREGISTER]) then
          begin
            if (flags*[nf_explicit,nf_internal])=[] then
              hlcg.g_rangecheck(current_asmdata.CurrAsmList,left.location,left.resultdef,resultdef);
            { the narrowed value is the low half of the pair }
            newsize:=def_cgsize(resultdef);
            location_reset(location,LOC_REGISTER,newsize);
            location.register:=cg.getintregister(current_asmdata.CurrAsmList,newsize);
            cg.a_load_reg_reg(current_asmdata.CurrAsmList,OS_64,newsize,left.location.register128.reglo,location.register);
            exit;
          end;
        inherited second_int_to_int;
      end;


    function tx8664typeconvnode.first_int_to_real : tnode;
      begin
        result:=nil;
        if use_vectorfpu(resultdef) and
           (torddef(left.resultdef).ordtype=u32bit) and
           not(FPUX86_HAS_AVX512F in fpu_capabilities[current_settings.fputype]) then
          begin
            inserttypeconv(left,s64inttype);
            firstpass(left);
          end
        else
          result:=inherited first_int_to_real;
       if use_vectorfpu(resultdef) then
         expectloc:=LOC_MMREGISTER;
      end;


    procedure tx8664typeconvnode.second_int_to_real;
      var
         l1,l2 : tasmlabel;
         op : tasmop;
         shiftedreg,stickyreg : tregister;

      procedure emit_signed_conversion(reg : tregister);
        begin
          if UseAVX then
            current_asmdata.CurrAsmList.concat(taicpu.op_reg_reg_reg(op,S_Q,reg,location.register,location.register))
          else
            current_asmdata.CurrAsmList.concat(taicpu.op_reg_reg(op,S_Q,reg,location.register));
        end;
      begin
        if use_vectorfpu(resultdef) and not(FPUX86_HAS_AVX512F in fpu_capabilities[current_settings.fputype]) then
          begin
            if is_double(resultdef) then
              if UseAVX then
                op:=A_VCVTSI2SD
              else
                op:=A_CVTSI2SD
            else if is_single(resultdef) then
              if UseAVX then
                op:=A_VCVTSI2SS
              else
                op:=A_CVTSI2SS
            else
              internalerror(200506061);

            location_reset(location,LOC_MMREGISTER,def_cgsize(resultdef));
            location.register:=cg.getmmregister(current_asmdata.CurrAsmList,location.size);

            case torddef(left.resultdef).ordtype of
              u64bit:
                begin
                   { CVTSI2S* only accepts signed integers.  Converting the
                     negative interpretation first and adding 2^64 afterwards
                     loses the discarded low bits before the final unsigned
                     value is formed.  For the high half, preserve them as a
                     sticky bit, convert the resulting positive Int64 once,
                     then scale by two. }
                   current_asmdata.getjumplabel(l1);
                   current_asmdata.getjumplabel(l2);
                   { both conversions below write only the low lane: zero the
                     register first (tx86typeconvnode.second_int_to_real) }
                   if UseAVX then
                     emit_reg_reg_reg(A_VXORPS,S_NO,location.register,location.register,location.register)
                   else
                     emit_reg_reg(A_XORPS,S_NO,location.register,location.register);

                   if not(left.location.loc in [LOC_REGISTER,LOC_CREGISTER]) then
                     hlcg.location_force_reg(current_asmdata.CurrAsmList,left.location,left.resultdef,left.resultdef,false);
                   cg.a_reg_alloc(current_asmdata.CurrAsmList,NR_DEFAULTFLAGS);
                   emit_const_reg(A_BT,S_Q,63,left.location.register);
                   cg.a_jmp_flags(current_asmdata.CurrAsmList,F_NC,l1);
                   cg.a_reg_dealloc(current_asmdata.CurrAsmList,NR_DEFAULTFLAGS);

                   shiftedreg:=cg.getintregister(current_asmdata.CurrAsmList,OS_64);
                   stickyreg:=cg.getintregister(current_asmdata.CurrAsmList,OS_64);
                   cg.a_load_reg_reg(current_asmdata.CurrAsmList,OS_64,OS_64,left.location.register,shiftedreg);
                   cg.a_load_reg_reg(current_asmdata.CurrAsmList,OS_64,OS_64,left.location.register,stickyreg);
                   cg.a_op_const_reg(current_asmdata.CurrAsmList,OP_SHR,OS_64,1,shiftedreg);
                   cg.a_op_const_reg(current_asmdata.CurrAsmList,OP_AND,OS_64,1,stickyreg);
                   cg.a_op_reg_reg(current_asmdata.CurrAsmList,OP_OR,OS_64,stickyreg,shiftedreg);
                   emit_signed_conversion(shiftedreg);
                   cg.a_opmm_reg_reg(current_asmdata.CurrAsmList,OP_ADD,location.size,
                     location.register,location.register,mms_movescalar);
                   cg.a_jmp_always(current_asmdata.CurrAsmList,l2);

                   cg.a_label(current_asmdata.CurrAsmList,l1);
                   emit_signed_conversion(left.location.register);
                   cg.a_label(current_asmdata.CurrAsmList,l2);
                end
              else
                inherited second_int_to_real;
            end;
          end
        else
          inherited second_int_to_real;
      end;


begin
   ctypeconvnode:=tx8664typeconvnode;
end.
