{ %CPU=x86_64 }
program tu64modpow2mask1;

var
  Value,
  Got : UInt64;

begin
  Value:=UInt64($12345678abcdef01);
  Got:=Value mod UInt64($100000000);
  if Got<>UInt64($abcdef01) then
    halt(1);
end.
