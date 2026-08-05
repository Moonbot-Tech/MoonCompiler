{ %CPU=x86_64 }
program tcheckednegconst1;

{$mode delphi}
{$Q+}

begin
  if -UInt64($8000000000000000) <> Low(Int64) then
    Halt(1);
  if -UInt128(UInt128(1) shl 127) <> Low(Int128) then
    Halt(2);
  if -UInt32(High(UInt32)) <> Int64(-4294967295) then
    Halt(3);
  if -Byte(255) <> -255 then
    Halt(4);
end.
