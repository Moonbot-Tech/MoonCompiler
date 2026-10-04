{
    Copyright (c) 1998-2006 by Carl Eric Codere and Peter Vreman

    Does the parsing for the x86-64 intel styled inline assembler.

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
Unit rax64int;

{$i fpcdefs.inc}

  interface

    uses
      aasmtai, aasmcfi,
      rax86int;

    type
      tx8664intreader = class(tx86intreader)
        actsehdirective: TAsmSehDirective;
        actcfidirective: tcfikind;
        cfidirective: boolean;
        function is_targetdirective(const s:string):boolean;override;
        procedure HandleTargetDirective;override;
      end;


  implementation

    uses
      globtype,
      cutils,
      systems,
      verbose,
      cgbase,
      symconst,
      procinfo,
      rabase;

    const
      { x86_64 subset of SEH directives. .seh_proc and .seh_endproc excluded
        because they are generated automatically when needed. }
      recognized_directives: set of TAsmSehDirective=[
        ash_endprologue,ash_handler,ash_handlerdata,
        ash_setframe,ash_stackalloc,ash_pushreg,
        ash_savereg,ash_savexmm,ash_pushframe{,
        ash_pushnv,ash_savenv }
      ];

      { max offset and bitmask for .seh_savereg and .seh_setframe }
      maxoffset: array[boolean] of aint=(high(dword), 240);
      modulo: array[boolean] of integer=(7, 15);

    function tx8664intreader.is_targetdirective(const s:string):boolean;
      var
        i: TAsmSehDirective;
        cfikind: tcfikind;
      begin
        result:=false;
        cfidirective:=false;
        if target_info.system=system_x86_64_linux then
          for cfikind in [cfi_def_cfa_offset,cfi_offset,cfi_restore] do
            if s=cfi2str[cfikind] then
              begin
                { Like SEH, these describe a complete standalone ASM routine.
                  Its author owns the stack and register-save description. }
                result:=(po_assembler in current_procinfo.procdef.procoptions) and
                  not (po_inline in current_procinfo.procdef.procoptions);
                if not result then
                  Message(asmr_e_syntax_error);
                cfidirective:=result;
                actcfidirective:=cfikind;
                exit;
              end;
        if target_info.system<>system_x86_64_win64 then exit;

        for i:=low(TAsmSehDirective) to high(TAsmSehDirective) do
          begin
            if not (i in recognized_directives) then
              continue;
            if s=sehdirectivestr[i] then
              begin
                actsehdirective:=i;
                result:=true;
                break;
              end;
          end;
        { allow SEH directives only in pure assember routines }
        if result and not (po_assembler in current_procinfo.procdef.procoptions) then
          begin
            Message(asmr_e_seh_in_pure_asm_only);
            result:=false;
          end;
      end;


    procedure tx8664intreader.HandleTargetDirective;
      var
        hreg: TRegister;
        hnum: aint;
        flags: integer;
        ai: tai_seh_directive;
        hs: string;
        err: boolean;
      begin
        if actasmtoken<>AS_TARGET_DIRECTIVE then
          InternalError(2011100203);
        Consume(AS_TARGET_DIRECTIVE);
        if cfidirective then
          begin
            if actcfidirective=cfi_def_cfa_offset then
              begin
                hnum:=BuildConstExpression;
                if (hnum<0) or (hnum>high(longint)) then
                  Message(asmr_e_syntax_error)
                else
                  curlist.concat(tai_cfi_op_val.create(actcfidirective,hnum));
              end
            else
              begin
                hreg:=actasmregister;
                Consume(AS_REGISTER);
                if (getregtype(hreg)<>R_INTREGISTER) or (getsubreg(hreg)<>R_SUBQ) then
                  Message(asmr_e_syntax_error)
                else if actcfidirective=cfi_restore then
                  curlist.concat(tai_cfi_op_reg.create(actcfidirective,hreg))
                else
                  begin
                    Consume(AS_COMMA);
                    hnum:=BuildConstExpression;
                    { The existing DW_CFA_offset backend uses unsigned factored
                      offsets. Accept aligned x64 saves below CFA, never round
                      an unrepresentable byte offset in that backend. }
                    if (hnum<low(longint)) or (hnum>0) or ((hnum and 7)<>0) then
                      Message(asmr_e_syntax_error)
                    else
                      curlist.concat(tai_cfi_op_reg_val.create(actcfidirective,hreg,hnum));
                  end;
              end;
            if actasmtoken<>AS_SEPARATOR then
              Consume(AS_SEPARATOR);
            exit;
          end;
        Include(current_procinfo.flags,pi_has_unwind_info);
        case actsehdirective of
          { TODO: .seh_pushframe is supposed to have a boolean parameter,
                  but GAS 2.21 does not support it. }
          ash_endprologue,
          ash_pushframe,
          ash_handlerdata:
            curlist.concat(cai_seh_directive.create(actsehdirective));
          ash_handler:
            begin
              hs:=actasmpattern;
              Consume(AS_ID);
              flags:=0;
              err:=false;
              while actasmtoken=AS_COMMA do
                begin
                  Consume(AS_COMMA);
                  if actasmtoken=AS_ID then
                    begin
                      uppervar(actasmpattern);
                      if actasmpattern='@EXCEPT' then
                        flags:=flags or 1
                      else if actasmpattern='@UNWIND' then
                        flags:=flags or 2
                      else
                        err:=true;
                      Consume(AS_ID);
                    end
                  else
                    err:=true;
                  if err then
                    begin
                      Message(asmr_e_syntax_error);
                      RecoverConsume(false);
                      exit;
                    end;
                end;

              ai:=cai_seh_directive.create_name(ash_handler,hs);
              ai.data.flags:=flags;
              curlist.concat(ai);
            end;
          ash_stackalloc:
            begin
              hnum:=BuildConstExpression;//(false,false);
              if (hnum<0) or (hnum>high(dword)) or ((hnum and 7)<>0) then
                Message1(asmr_e_bad_seh_directive_offset,sehdirectivestr[ash_stackalloc])
              else
                curlist.concat(cai_seh_directive.create_offset(ash_stackalloc,hnum));
            end;
          //ash_pushnv,
          ash_pushreg:
            begin
              hreg:=actasmregister;
              Consume(AS_REGISTER);
              if (getregtype(hreg)<>R_INTREGISTER) or (getsubreg(hreg)<>R_SUBQ) then
                Message1(asmr_e_bad_seh_directive_register,sehdirectivestr[ash_pushreg])
              else
                curlist.concat(cai_seh_directive.create_reg(ash_pushreg,hreg));
            end;
          ash_setframe,
          ash_savereg:
            begin
              hreg:=actasmregister;
              Consume(AS_REGISTER);
              if (getregtype(hreg)<>R_INTREGISTER) or (getsubreg(hreg)<>R_SUBQ) then
                Message1(asmr_e_bad_seh_directive_register,sehdirectivestr[actsehdirective]);
              Consume(AS_COMMA);
              hnum:=BuildConstExpression;//(false,false);
              if (hnum<0) or (hnum>maxoffset[actsehdirective=ash_setframe]) or
                ((hnum mod modulo[actsehdirective=ash_setframe])<>0) then
                Message1(asmr_e_bad_seh_directive_offset,sehdirectivestr[actsehdirective])
              else
                curlist.concat(cai_seh_directive.create_reg_offset(actsehdirective,hreg,hnum));
            end;
          //ash_savenv,
          ash_savexmm:
            begin
              hreg:=actasmregister;
              Consume(AS_REGISTER);
              if (getregtype(hreg)<>R_MMREGISTER) then
                Message1(asmr_e_bad_seh_directive_register,sehdirectivestr[ash_savexmm]);
              Consume(AS_COMMA);
              hnum:=BuildConstExpression;//(false,false);
              if (hnum<0) or (hnum>high(dword)) or ((hnum and 15)<>0) then
                Message1(asmr_e_bad_seh_directive_offset,sehdirectivestr[ash_savexmm])
              else
                curlist.concat(cai_seh_directive.create_reg_offset(actsehdirective,hreg,hnum));
            end;
          else
            InternalError(2018022401);
        end;
        if actasmtoken<>AS_SEPARATOR then
          Consume(AS_SEPARATOR);
      end;

    const
      asmmode_x86_64_intel_info : tasmmodeinfo =
              (
                id    : asmmode_x86_64_intel;
                idtxt : 'INTEL';
                casmreader : tx8664intreader;
              );

initialization
  RegisterAsmMode(asmmode_x86_64_intel_info);
end.
