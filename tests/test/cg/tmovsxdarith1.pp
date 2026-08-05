{ %OPT=-O3 }
program tmovsxdarith1;

{$mode delphi}
{$Q-}
{$R-}

function CrossWord(W: Word): PtrInt;
var
  X: LongInt;
begin
  X := W;
  Inc(X, $7fff8001);
  Result := SarLongint(X, 31);
end;

begin
  If CrossWord(0) <> 0 then Halt(1);
  If CrossWord(32766) <> 0 then Halt(2);
  If CrossWord(32767) <> -1 then Halt(3);
  If CrossWord(32768) <> -1 then Halt(4);
  If CrossWord(65535) <> -1 then Halt(5);
end.
