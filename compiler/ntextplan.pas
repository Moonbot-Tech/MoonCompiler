{
    Copyright (c) 2026 by the Moon Compiler team

    One pure owner for compile-time text-domain decisions (A-001 stage 1).

    The string/character provenance of a constant expression is spread
    over several carriers (literalbyte, literalbytes, nf_explicit,
    anf_rawbytestring_concat, tstringdef.encoding) and today every
    consumer re-derives the domain from its own combination of them at
    its own moment in the AST's life.  This unit centralizes the
    DECISIONS; the consumers execute the returned plan and the carriers
    keep transporting the facts.  Behavior is mirrored 1:1 from the
    historical decision points - the whole gate series is the oracle.

 ****************************************************************************
}
unit ntextplan;

{$i fpcdefs.inc}

interface

    uses
      node,symtype;

    type
      { how a folded string constant materializes (the taddnode constant
        folding point) }
      TTextFoldPlan = record
        { the folded constant keeps the joined source bytes of its
          operands }
        joinliteralbytes : boolean;
        { the folded constant inherits the explicit-cast origin }
        markexplicit : boolean;
        { def the joined bytes are created with: the concrete result def
          when both operands already carry the target encoding (their
          bytes need no further conversion), nil for an untyped source
          constant that the later changestringtype converts exactly once }
        createdef : tdef;
        { def the folded constant finally becomes: the result def, or the
          plain source-page AnsiString for a RawByteString result without
          a genuine raw-concat intent (Delphi routes that expression
          through the system code page) }
        finaldef : tdef;
      end;

    { a numeric #$xx scanner byte or an explicitly typed AnsiChar
      constant: the one byte-domain proof shared by every consumer (it
      used to be re-spelled at each decision point; the added orddef
      check also stops the historical torddef() read through a constant
      of a non-ordinal def) }
    function text_byte_proof(n: tnode): boolean;

    { plan for folding <left> op <right> where both operands fold in the
      wide domain (both are wide/unicode string constants) }
    function plan_wide_const_fold(left,right: tnode): TTextFoldPlan;

    { plan for folding <left> + <right> in the byte domain; rawconcat is
      the taddnode raw-concat intent (anf_rawbytestring_concat) }
    function plan_ansi_const_fold(left,right: tnode; resultdef: tdef;
      rawconcat: boolean): TTextFoldPlan;

implementation

    uses
      globals,symconst,symdef,defutil,ncon;

    function text_byte_proof(n: tnode): boolean;
      begin
        result:=(n.nodetype=ordconstn) and
          assigned(n.resultdef) and
          (n.resultdef.typ=orddef) and
          (tordconstnode(n).literalbyte or
           (torddef(n.resultdef).ordtype=uchar));
      end;


    function plan_wide_const_fold(left,right: tnode): TTextFoldPlan;
      begin
        result.createdef:=nil;
        result.finaldef:=nil;
        result.markexplicit:=
          (nf_explicit in left.flags) or
          (nf_explicit in right.flags);
        result.joinliteralbytes:=
          ((left.nodetype=stringconstn) and
           tstringconstnode(left).hasliteralbytes) or
          ((right.nodetype=stringconstn) and
           tstringconstnode(right).hasliteralbytes);
      end;


    function plan_ansi_const_fold(left,right: tnode; resultdef: tdef;
      rawconcat: boolean): TTextFoldPlan;
      begin
        result.joinliteralbytes:=false;
        result.markexplicit:=
          (nf_explicit in left.flags) or
          (nf_explicit in right.flags);
        { both operands already carry the target encoding: create the
          joined bytes directly in the result def so they are not
          transcoded a second time (UTF8String('u') + #$85) }
        if is_ansistring(resultdef) and
           is_ansistring(left.resultdef) and
           is_ansistring(right.resultdef) and
           (tstringdef(left.resultdef).encoding=
            tstringdef(resultdef).encoding) and
           (tstringdef(right.resultdef).encoding=
            tstringdef(resultdef).encoding) then
          result.createdef:=resultdef
        else
          result.createdef:=nil;
        { a RawByteString result without a genuine raw-concat intent goes
          through the plain source-page AnsiString - the Delphi contract }
        if not is_ansistring(resultdef) or
           (tstringdef(resultdef).encoding<>globals.CP_NONE) or
           rawconcat then
          result.finaldef:=resultdef
        else
          result.finaldef:=getansistringdef;
      end;

end.
