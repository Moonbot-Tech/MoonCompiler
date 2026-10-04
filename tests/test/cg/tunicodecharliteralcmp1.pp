program tunicodecharliteralcmp1;

{$mode delphiunicode}
{$R+}{$Q+}

type
  tpredicate = function(const value: unicodestring): boolean;

var
  calls: longint;

procedure fail(code: longint);
  begin
    halt(code);
  end;

function eqx(const value: unicodestring): boolean; noinline;
  begin
    result:=value='x';
  end;

function nex(const value: unicodestring): boolean; noinline;
  begin
    result:=value<>'x';
  end;

function xeq(const value: unicodestring): boolean; noinline;
  begin
    result:='x'=value;
  end;

function xne(const value: unicodestring): boolean; noinline;
  begin
    result:='x'<>value;
  end;

function eqnul(const value: unicodestring): boolean; noinline;
  begin
    result:=value=#$0000;
  end;

function eqsurrogate(const value: unicodestring): boolean; noinline;
  begin
    result:=value=#$d800;
  end;

function eqhigh(const value: unicodestring): boolean; noinline;
  begin
    result:=value=#$ffff;
  end;

{$zerobasedstrings on}
function eqxzero(const value: unicodestring): boolean; noinline;
  begin
    result:=value='x';
  end;
{$zerobasedstrings off}

function produce(const value: unicodestring): unicodestring; noinline;
  begin
    inc(calls);
    result:=value;
  end;

function eqproduced(const value: unicodestring): boolean; noinline;
  begin
    result:=produce(value)='x';
  end;

function eqansi(const value: ansistring): boolean; noinline;
  begin
    result:=value='x';
  end;

procedure checkall(predicate: tpredicate; expected: word; code: longint);
  var
    i: longint;
    value: unicodestring;
  begin
    setlength(value,1);
    for i:=0 to 65535 do
      begin
        value[1]:=widechar(i);
        if predicate(value)<>(i=expected) then
          fail(code);
      end;
  end;

procedure checkedges;
  var
    value: unicodestring;
  begin
    value:='';
    if eqx(value) or not nex(value) then
      fail(8);
    value:='xx';
    if eqx(value) or not nex(value) then
      fail(9);
    setlength(value,2);
    value[1]:='x';
    value[2]:=#0;
    if eqx(value) or not nex(value) then
      fail(10);
    setlength(value,1);
    value[1]:='x';
    if not eqx(value) or not xeq(value) or nex(value) or xne(value) then
      fail(11);
    if not eqxzero(value) then
      fail(12);
  end;

procedure checksideeffects;
  begin
    calls:=0;
    if not eqproduced('x') or (calls<>1) then
      fail(13);
    calls:=0;
    if eqproduced('xx') or (calls<>1) then
      fail(14);
  end;

begin
  checkall(@eqx,ord('x'),1);
  checkall(@xeq,ord('x'),2);
  checkall(@eqnul,0,3);
  checkall(@eqsurrogate,$d800,4);
  checkall(@eqhigh,$ffff,5);
  checkall(@eqxzero,ord('x'),6);
  checkedges;
  checksideeffects;
  if not eqansi('x') or eqansi('xx') then
    fail(15);
  writeln('UNICODE_CHAR_LITERAL_CMP_OK');
end.
