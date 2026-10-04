{
    Copyright (c) 2002 by Florian Klaempfl

    Implements the x86-64 specific part of call nodes

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
unit nx64cal;

{$i fpcdefs.inc}

interface

    uses
      symdef,
      ncal,nx86cal;

    type
       tx8664callnode = class(tx86callnode)
       protected
         procedure gen_syscall_para(para: tcallparanode); override;
         procedure extra_call_code;override;
         procedure set_result_location(realresdef: tstoreddef);override;
       public
         procedure do_syscall;override;
       end;


implementation

    uses
      globtype,
      systems,verbose,cutils,
      cpubase,cgbase,cgutils,cgobj,parabase,
      symconst,symcpu,symsym,nld,
      aasmtai,aasmdata,aasmcpu,
      cpupi;

    procedure tx8664callnode.do_syscall;
      var
        tmpref: treference;
      begin
        case target_info.system of
          system_x86_64_aros:
            begin
              if ([po_syscall_baselast,po_syscall_basereg] * tprocdef(procdefinition).procoptions) <> [] then
                begin
                  current_asmdata.CurrAsmList.concat(tai_comment.create(strpnew('AROS SysCall')));

                  cg.getcpuregister(current_asmdata.CurrAsmList,NR_R12);
                  get_syscall_call_ref(tmpref,NR_R12);

                  current_asmdata.CurrAsmList.concat(taicpu.op_ref(A_CALL,S_NO,tmpref));
                  cg.ungetcpuregister(current_asmdata.CurrAsmList,NR_R12);
                  exit;
                end;
              internalerror(2016120101);
            end;
          else
            internalerror(2015062801);
        end;
      end;


    procedure tx8664callnode.gen_syscall_para(para: tcallparanode);
      begin
        { lib parameter has no special type but proccalloptions must be a syscall }
        para.left:=cloadnode.create(tcpuprocdef(procdefinition).libsym,tcpuprocdef(procdefinition).libsym.owner);
      end;


    procedure tx8664callnode.extra_call_code;
      var
        mmregs : aint;
        intsize : tcgsize;
        para : tcallparanode;
        paraloc : pcgparalocation;
        intreg,
        mmreg : tsuperregister;
        mmsize : tcgsize;
      begin
        if (cnf_uses_varargs in callnodeflags) and x86_64_use_ms_abi(procdefinition.proccalloption) then
          begin
            { The Microsoft x64 varargs ABI duplicates every floating-point
              argument in the first four argument slots in the matching integer
              and XMM registers.  Fixed parameters have an XMM canonical
              location, while the variadic tail has an integer canonical
              location; mirror both forms from the final call-parameter list
              immediately before the call. }
            para:=tcallparanode(left);
            while assigned(para) do
              begin
                if para.parasym.vardef.typ=floatdef then
                  begin
                    paraloc:=para.parasym.paraloc[callerside].location;
                    if assigned(paraloc) then
                      begin
                        case paraloc^.loc of
                          LOC_REGISTER:
                            begin
                              case getsupreg(paraloc^.register) of
                                RS_RCX:
                                  mmreg:=RS_XMM0;
                                RS_RDX:
                                  mmreg:=RS_XMM1;
                                RS_R8:
                                  mmreg:=RS_XMM2;
                                RS_R9:
                                  mmreg:=RS_XMM3;
                                else
                                  internalerror(2026090901);
                              end;
                              case paraloc^.size of
                                OS_32,OS_S32:
                                  mmsize:=OS_F32;
                                OS_64,OS_S64:
                                  mmsize:=OS_F64;
                                else
                                  internalerror(2026090902);
                              end;
                              cg.a_loadmm_intreg_reg(current_asmdata.CurrAsmList,
                                paraloc^.size,mmsize,paraloc^.register,
                                newreg(R_MMREGISTER,mmreg,
                                  cgsize2subreg(R_MMREGISTER,mmsize)),mms_movescalar);
                            end;
                          LOC_MMREGISTER:
                            begin
                              case getsupreg(paraloc^.register) of
                                RS_XMM0:
                                  intreg:=RS_RCX;
                                RS_XMM1:
                                  intreg:=RS_RDX;
                                RS_XMM2:
                                  intreg:=RS_R8;
                                RS_XMM3:
                                  intreg:=RS_R9;
                                else
                                  internalerror(2026091001);
                              end;
                              case paraloc^.size of
                                OS_F32:
                                  intsize:=OS_32;
                                OS_F64:
                                  intsize:=OS_64;
                                else
                                  internalerror(2026091002);
                              end;
                              cg.a_loadmm_reg_intreg(current_asmdata.CurrAsmList,
                                paraloc^.size,intsize,paraloc^.register,
                                newreg(R_INTREGISTER,intreg,
                                  cgsize2subreg(R_INTREGISTER,intsize)),mms_movescalar);
                            end;
                          LOC_REFERENCE:
                            ;
                          else
                            internalerror(2026091003);
                        end;
                      end;
                  end;
                para:=tcallparanode(para.right);
              end;
          end
        { The System V x86-64 ABI requires %al to contain the number of SSE
          registers used for variadic arguments. }
        else if (cnf_uses_varargs in callnodeflags) then
          begin
            if assigned(varargsparas) then
              mmregs:=varargsparas.mmregsused
            else
              mmregs:=0;
            current_asmdata.CurrAsmList.concat(taicpu.op_const_reg(A_MOV,S_Q,mmregs,NR_RAX))
          end;
      end;


    procedure tx8664callnode.set_result_location(realresdef: tstoreddef);
      begin
        { avoid useless "movq %xmm0,%rax" and "movq %rax,%xmm0" instructions
          (which moreover for some reason are not supported by the Darwin
           x86-64 assembler) }
        if assigned(retloc.location) and
           not assigned(retloc.location^.next) and
           (retloc.location^.loc in [LOC_MMREGISTER,LOC_CMMREGISTER]) then
          begin
            location_reset(location,LOC_MMREGISTER,retloc.location^.size);
            location.register:=cg.getmmregister(current_asmdata.CurrAsmList,retloc.location^.size);
          end
        else
          inherited
      end;

begin
   ccallnode:=tx8664callnode;
end.
