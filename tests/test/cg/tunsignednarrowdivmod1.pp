program tunsignednarrowdivmod1;

{$mode delphiunicode}
{$R+}{$Q+}

uses
  SysUtils;

const
  values: array[0..8] of cardinal =
    (0,1,2,3,17,65535,65536,2147483648,4294967295);

var
  calls,
  leftcalls,
  rightcalls,
  callorder: longint;

procedure fail(code: longint);
  begin
    halt(code);
  end;

function narrowdiv(a,b: cardinal): uint64; noinline;
  begin
    result:=uint64(a) div uint64(b);
  end;

function narrowmod(a,b: cardinal): uint64; noinline;
  begin
    result:=uint64(a) mod uint64(b);
  end;

function widediv(a,b: uint64): uint64; noinline;
  begin
    result:=a div b;
  end;

function widemod(a,b: uint64): uint64; noinline;
  begin
    result:=a mod b;
  end;

function signedwide(a,b: longint): int64; noinline;
  begin
    result:=int64(a) div int64(b);
  end;

function leftvalue(value: cardinal): cardinal; noinline;
  begin
    inc(calls);
    inc(leftcalls);
    callorder:=callorder*10+1;
    result:=value;
  end;

function rightvalue(value: cardinal): cardinal; noinline;
  begin
    inc(calls);
    inc(rightcalls);
    callorder:=callorder*10+2;
    result:=value;
  end;

function directeffectdiv: uint64; noinline;
  begin
    result:=uint64(leftvalue(100)) div uint64(rightvalue(7));
  end;

function directeffectmod: uint64; noinline;
  begin
    result:=uint64(leftvalue(100)) mod uint64(rightvalue(7));
  end;

function zerovalue: cardinal; noinline;
  begin
    inc(calls);
    result:=0;
  end;

procedure checkmatrix;
  var
    a,
    b: cardinal;
    i,
    j: longint;
    q,
    r: uint64;
  begin
    for i:=low(values) to high(values) do
      for j:=1 to high(values) do
        begin
          a:=values[i];
          b:=values[j];
          q:=narrowdiv(a,b);
          r:=narrowmod(a,b);
          if (q<>a div b) or (r<>a mod b) then
            begin
              writeln('mismatch a=',a,' b=',b,' q=',q,' expected q=',a div b,
                ' r=',r,' expected r=',a mod b);
              fail(1);
            end;
          if (q*uint64(b)+r<>a) or (r>=b) then
            fail(2);
        end;
  end;

procedure checkevaluation;
  begin
    calls:=0;
    leftcalls:=0;
    rightcalls:=0;
    if narrowdiv(leftvalue(100),rightvalue(7))<>14 then
      fail(3);
    if (calls<>2) or (leftcalls<>1) or (rightcalls<>1) then
      fail(4);

    calls:=0;
    leftcalls:=0;
    rightcalls:=0;
    if narrowmod(leftvalue(100),rightvalue(7))<>2 then
      fail(5);
    if (calls<>2) or (leftcalls<>1) or (rightcalls<>1) then
      fail(6);

    calls:=0;
    leftcalls:=0;
    rightcalls:=0;
    callorder:=0;
    if directeffectdiv<>14 then
      fail(11);
    if (calls<>2) or (leftcalls<>1) or (rightcalls<>1) or (callorder<>12) then
      fail(12);

    calls:=0;
    leftcalls:=0;
    rightcalls:=0;
    callorder:=0;
    if directeffectmod<>2 then
      fail(13);
    if (calls<>2) or (leftcalls<>1) or (rightcalls<>1) or (callorder<>12) then
      fail(14);
  end;

procedure checkexceptions;
  var
    raised: boolean;
  begin
    calls:=0;
    raised:=false;
    try
      narrowdiv(1,zerovalue);
    except
      on EDivByZero do
        raised:=true;
    end;
    if not raised or (calls<>1) then
      fail(7);

    calls:=0;
    raised:=false;
    try
      narrowmod(1,zerovalue);
    except
      on EDivByZero do
        raised:=true;
    end;
    if not raised or (calls<>1) then
      fail(8);
  end;

procedure checkwidecontrols;
  var
    a,
    b,
    q,
    r: uint64;
  begin
    a:=(uint64(1) shl 48)+123456789;
    b:=(uint64(1) shl 33)+17;
    q:=widediv(a,b);
    r:=widemod(a,b);
    if (q*b+r<>a) or (r>=b) then
      fail(9);
    if signedwide(low(longint),-1)<>int64(2147483648) then
      fail(10);
  end;

begin
  checkmatrix;
  checkevaluation;
  checkexceptions;
  checkwidecontrols;
  writeln('UNSIGNED_NARROW_DIVMOD_OK');
end.
