program safecall_nostackframe_rejected;
{$IFDEF FPC}{$mode delphi}{$asmmode intel}{$ENDIF}

{ A safecall wrapper needs a frame for its HRESULT.  An explicit
  nostackframe directive cannot describe that routine. }
procedure Conflicting; safecall; assembler; nostackframe;
asm
  nop
end;

begin
  Conflicting;
end.
