unit f_asm;

{ Inline assembler: the model cannot see inside - everything is read and
  written, all locals included, with every instruction effect. }

interface

procedure AsmForm;

implementation

// EXPECT: proc=AsmForm r=L!EHGTP w=L!EHGTP ie=smt reason=inline_asm
// EXPECT: proc=AsmForm sc=1 q=ok un=ok
procedure AsmForm;
begin
  asm
  end;
end;

end.
