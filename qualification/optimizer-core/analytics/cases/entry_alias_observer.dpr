program entry_alias_observer;

{$mode delphiunicode}{$H+}{$R-}{$Q-}{$inline off}{$asmmode intel}

uses SysUtils;

var
  G: Double;
  H: Int64;
  S: Single;
  First: Double;
  AliasG: Double external name 'U_$P$ENTRY_ALIAS_OBSERVER_$$_G';
  AliasH: Int64 external name 'U_$P$ENTRY_ALIAS_OBSERVER_$$_H';
  AliasS: Single external name 'U_$P$ENTRY_ALIAS_OBSERVER_$$_S';

{ Only volatile registers, valid under both Win64 and SysV. The caller has
  no assembler block; an opaque observer reads only the BSS aliases. }
procedure Clobber; assembler; nostackframe;
asm
  MOV RAX,$7FF8000000000022
  MOVQ XMM0,RAX
  MOVQ XMM1,RAX
  MOVQ XMM2,RAX
  MOVQ XMM3,RAX
  MOVQ XMM4,RAX
  MOVQ XMM5,RAX
  MOV RCX,$123456789ABCDE
  MOV RDX,RCX
  MOV R8,RCX
  MOV R9,RCX
  MOV R10,RCX
  MOV R11,RCX
end;

function ReadAliases: Double; noinline;
begin
  Result := AliasG + AliasH + AliasS;
end;

begin
  try
    Clobber;
    First := ReadAliases;
  finally
    Writeln('sibling');
  end;
  G := 11;
  H := 17;
  S := 23;
  Writeln(First:0:0, ' ', (G + H + S):0:0);
  If (First <> 0) or (G + H + S <> 51) then Halt(1);
end.
