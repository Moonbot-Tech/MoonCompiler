unit constref_remote_probe;

{ Support unit for constref_formal_semantic: an untyped constref formal
  behind a PPU boundary. }

{$mode delphiunicode}{$H+}

interface

function PeekRemote(constref X): Byte;

implementation

function PeekRemote(constref X): Byte;
var
  B: Byte absolute X;
begin
  Result := B;
end;

end.
