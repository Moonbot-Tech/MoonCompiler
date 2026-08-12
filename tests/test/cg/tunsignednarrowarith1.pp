program tunsignednarrowarith1;

{$ifdef FPC}
  {$mode delphi}
{$endif}
{$R+}
{$Q-}

var
  a: word;
  b: word;
  cardinalproduct: longword;
  signedproduct: longint;
  product: uint64;

function kind(value: longint): byte; overload;
  begin
    result:=1;
  end;

function kind(value: longword): byte; overload;
  begin
    result:=2;
  end;

begin
  a:=65535;
  b:=65534;
  product:=uint64(a*b);
  if product<>uint64(4294770690) then
    halt(1);
  if int64(a*b)<>int64(4294770690) then
    halt(2);
  if kind(a*b)<>1 then
    halt(3);
  cardinalproduct:=a*b;
  if cardinalproduct<>longword(4294770690) then
    halt(4);
  signedproduct:=a*b;
  if signedproduct<>-196606 then
    halt(5);
end.
