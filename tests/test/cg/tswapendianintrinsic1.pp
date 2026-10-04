program tswapendianintrinsic1;

{$mode delphiunicode}
{$R+}{$Q+}

uses
  uswapendianname1;

type
  tqwordswap = function(value: qword): qword;

var
  calls: longint;

procedure fail(code: longint);
  begin
    halt(code);
  end;

function swap32(value: dword): dword; noinline;
  begin
    result:=system.SwapEndian(value);
  end;

function swap64(value: qword): qword; noinline;
  begin
    result:=system.SwapEndian(value);
  end;

function swapsigned32(value: longint): longint; noinline;
  begin
    result:=system.SwapEndian(value);
  end;

function swapsigned64(value: int64): int64; noinline;
  begin
    result:=system.SwapEndian(value);
  end;

function constant32: dword; noinline;
  begin
    result:=system.SwapEndian(dword($01234567));
  end;

function constant64: qword; noinline;
  begin
    result:=system.SwapEndian(qword($0123456789abcdef));
  end;

function produce: qword; noinline;
  begin
    inc(calls);
    result:=$0123456789abcdef;
  end;

function swapeffect: qword; noinline;
  begin
    result:=system.SwapEndian(produce);
  end;

function swapnested(value: qword): qword; noinline;
  begin
    result:=system.SwapEndian(system.SwapEndian(value));
  end;

function swapthroughpointer(value: qword): qword; noinline;
  var
    swap: tqwordswap;
  begin
    swap:=@swap64;
    result:=swap(value);
  end;

function swapuser(value: qword): qword; noinline;
  begin
    { Keep a real call for the assembly contract, rather than a tail jump. }
    result:=uswapendianname1.SwapEndian(value) xor 1;
  end;

procedure checkvalues;
  begin
    if swap32($01234567)<>$67452301 then
      fail(1);
    if swap64($0123456789abcdef)<>$efcdab8967452301 then
      fail(2);
    if dword(swapsigned32(longint($89abcdef)))<>$efcdab89 then
      fail(3);
    if qword(swapsigned64(int64($89abcdef01234567)))<>$67452301efcdab89 then
      fail(4);
    if (constant32<>$67452301) or (constant64<>$efcdab8967452301) then
      fail(5);
    if swapnested($fedcba9876543210)<>$fedcba9876543210 then
      fail(6);
    if system.BEtoN(dword($01234567))<>$67452301 then
      fail(7);
    if system.NtoBE(qword($0123456789abcdef))<>$efcdab8967452301 then
      fail(8);
  end;

procedure checkcallboundaries;
  begin
    calls:=0;
    if swapeffect<>$efcdab8967452301 then
      fail(9);
    if calls<>1 then
      fail(10);
    if swapthroughpointer($0123456789abcdef)<>$efcdab8967452301 then
      fail(11);
    if swapuser($0123456789abcdef)<>$548910cddc019844 then
      fail(12);
  end;

begin
  checkvalues;
  checkcallboundaries;
  writeln('SWAPENDIAN_INTRINSIC_OK');
end.
