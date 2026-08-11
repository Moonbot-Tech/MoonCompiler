program timpfuncspez38;

{$mode Delphi}

uses
  uimpfuncspez38b,
  uimpfuncspez38a;

var
  S: RawByteString;
begin
  if Test(S)<>1 then
    Halt(1);
end.
