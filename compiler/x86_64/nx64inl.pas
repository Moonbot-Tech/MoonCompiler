{
    Copyright (c) 1998-2002 by Florian Klaempfl

    Generate x86-64 inline nodes

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
unit nx64inl;

{$i fpcdefs.inc}

interface

    uses
       node,nx86inl;

    type
       tx8664inlinenode = class(tx86inlinenode)
        protected
          procedure maybe_remove_round_trunc_typeconv; override;
          function first_atomic: tnode; override;
          procedure second_atomic;
        public
          procedure pass_generate_code_cpu; override;
       end;

implementation

  uses
    globtype,
    verbose,
    compinnr,
    aasmbase,aasmdata,aasmcpu,
    cgbase,cgutils,cgobj,hlcgobj,cgx86,
    cpubase,
    symconst,symdef,defutil,
    ncal,ncnv,ninl,
    pass_2;

  procedure tx8664inlinenode.maybe_remove_round_trunc_typeconv;
    var
      temp: tnode;
    begin
      { the prototype of trunc()/round() in the system unit is declared
        with valreal as parameter type, so the argument will always be
        extended -> remove the typeconversion to extended if any; not done
        in ninl, because there are other code generators that assume that
        the parameter to trunc has been converted to valreal (e.g. PowerPC).

        We can always remove such typeconversions here if they exist, because
        on the x87 all floating point types are handled the same, and
        if we call the inherited version we'll insert a call node, which
        will insert the necessary type conversion again }
      if (left.nodetype=typeconvn) and
         not(nf_explicit in left.flags) and
         (ttypeconvnode(left).left.resultdef.typ=floatdef) then
        begin
          { get rid of the type conversion, so the use_vectorfpu will be
            applied to the original type }
          temp:=ttypeconvnode(left).left;
          ttypeconvnode(left).left:=nil;
          left.free;
          left:=temp;
        end;
    end;


  function tx8664inlinenode.first_atomic: tnode;
    var
      third: tcallparanode;
    begin
      { the four-parameter CmpExchange form (with the Succeeded output) and
        sub-longint element sizes keep the generic helper redirect }
      if not(resultdef.size in [4,8]) then
        exit(inherited first_atomic);
      if inlinenumber=in_atomic_cmp_xchg then
        begin
          third:=tcallparanode(tcallparanode(tcallparanode(left).right).right);
          if assigned(third.right) then
            exit(inherited first_atomic);
        end;
      expectloc:=LOC_REGISTER;
      result:=nil;
    end;


  procedure tx8664inlinenode.pass_generate_code_cpu;
    begin
      case inlinenumber of
        in_atomic_inc,
        in_atomic_dec,
        in_atomic_xchg,
        in_atomic_cmp_xchg:
          second_atomic;
        else
          inherited pass_generate_code_cpu;
      end;
    end;


  procedure tx8664inlinenode.second_atomic;
    var
      targetpara,
      valuepara,
      cmppara : tcallparanode;
      cgsz : tcgsize;
      opsz : topsize;
      list : TAsmList;
      hreg,
      valreg : tregister;
      delta : longint;
      href : treference;
    begin
      list:=current_asmdata.CurrAsmList;
      targetpara:=tcallparanode(left);
      valuepara:=tcallparanode(targetpara.right);
      cmppara:=nil;
      if assigned(valuepara) then
        cmppara:=tcallparanode(valuepara.right);

      secondpass(targetpara.left);
      if not(targetpara.left.location.loc in [LOC_REFERENCE,LOC_CREFERENCE]) then
        internalerror(2026081801);
      if assigned(valuepara) then
        secondpass(valuepara.left);
      if assigned(cmppara) then
        secondpass(cmppara.left);

      href:=targetpara.left.location.reference;
      tcgx86(cg).make_simple_ref(list,href);

      cgsz:=def_cgsize(resultdef);
      opsz:=TCGSize2OpSize[cgsz];

      case inlinenumber of
        in_atomic_inc,
        in_atomic_dec:
          begin
            hreg:=cg.getintregister(list,cgsz);
            if assigned(valuepara) then
              begin
                { keep the delta: xadd leaves the old value in hreg and the
                  intrinsic returns the new one }
                valreg:=cg.getintregister(list,cgsz);
                hlcg.location_force_reg(list,valuepara.left.location,
                  valuepara.left.resultdef,resultdef,false);
                cg.a_load_reg_reg(list,cgsz,cgsz,valuepara.left.location.register,valreg);
                if inlinenumber=in_atomic_dec then
                  begin
                    cg.a_load_const_reg(list,cgsz,0,hreg);
                    cg.a_op_reg_reg(list,OP_SUB,cgsz,valreg,hreg);
                  end
                else
                  cg.a_load_reg_reg(list,cgsz,cgsz,valreg,hreg);
                list.concat(taicpu.op_none(A_LOCK,S_NO));
                list.concat(taicpu.op_reg_ref(A_XADD,opsz,hreg,href));
                if inlinenumber=in_atomic_dec then
                  cg.a_op_reg_reg(list,OP_SUB,cgsz,valreg,hreg)
                else
                  cg.a_op_reg_reg(list,OP_ADD,cgsz,valreg,hreg);
              end
            else
              begin
                if inlinenumber=in_atomic_dec then
                  delta:=-1
                else
                  delta:=1;
                cg.a_load_const_reg(list,cgsz,delta,hreg);
                list.concat(taicpu.op_none(A_LOCK,S_NO));
                list.concat(taicpu.op_reg_ref(A_XADD,opsz,hreg,href));
                cg.a_op_const_reg(list,OP_ADD,cgsz,delta,hreg);
              end;
            location_reset(location,LOC_REGISTER,cgsz);
            location.register:=hreg;
          end;
        in_atomic_xchg:
          begin
            hreg:=cg.getintregister(list,cgsz);
            hlcg.location_force_reg(list,valuepara.left.location,
              valuepara.left.resultdef,resultdef,false);
            cg.a_load_reg_reg(list,cgsz,cgsz,valuepara.left.location.register,hreg);
            { xchg with a memory operand asserts the bus lock on its own }
            list.concat(taicpu.op_reg_ref(A_XCHG,opsz,hreg,href));
            location_reset(location,LOC_REGISTER,cgsz);
            location.register:=hreg;
          end;
        in_atomic_cmp_xchg:
          begin
            { CMPXCHG compares with and returns the old value in [R/E]AX }
            hlcg.location_force_reg(list,valuepara.left.location,
              valuepara.left.resultdef,resultdef,false);
            valreg:=valuepara.left.location.register;
            cg.getcpuregister(list,NR_RAX);
            cg.a_load_loc_reg(list,cgsz,cmppara.left.location,
              cg.makeregsize(list,NR_RAX,cgsz));
            list.concat(taicpu.op_none(A_LOCK,S_NO));
            list.concat(taicpu.op_reg_ref(A_CMPXCHG,opsz,valreg,href));
            hreg:=cg.getintregister(list,cgsz);
            cg.a_load_reg_reg(list,cgsz,cgsz,cg.makeregsize(list,NR_RAX,cgsz),hreg);
            cg.ungetcpuregister(list,NR_RAX);
            location_reset(location,LOC_REGISTER,cgsz);
            location.register:=hreg;
          end;
        else
          internalerror(2026081802);
      end;
    end;

begin
   cinlinenode:=tx8664inlinenode;
end.
