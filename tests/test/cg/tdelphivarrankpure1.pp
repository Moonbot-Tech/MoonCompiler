program tdelphivarrankpure1;

{ overload ranking must classify var/out addressability purely: an rvalue
  never keeps a var/out candidate alive, in either declaration order, and
  no special var-compatibility branch bypasses the lvalue gate. Writable
  storage keeps winning the var overloads (Delphi 12.2 oracled) }

{$mode delphi}

type
  PB = ^Byte;
  PI = ^Integer;
  A1251 = type AnsiString(1251);
  TByteSet = set of byte;
  TWordSet = set of 1..100;

var
  marker : integer;
  gpb : PB;
  gpi : PI;
  ga : A1251;
  gset : TByteSet;

function GetPB : PB;
begin
  result:=gpb;
end;

function GetA : A1251;
begin
  result:=ga;
end;

{ var overload declared FIRST }

procedure P1(var x: PI); overload;
begin
  marker:=1;
end;

procedure P1(x: Pointer); overload;
begin
  marker:=2;
end;

{ var overload declared SECOND }

procedure P2(x: Pointer); overload;
begin
  marker:=2;
end;

procedure P2(var x: PI); overload;
begin
  marker:=1;
end;

{ set literal against a var set }

procedure S(var st: TByteSet); overload;
begin
  marker:=1;
end;

procedure S(st: TWordSet); overload;
begin
  marker:=2;
end;

{ AnsiString with a different code page }

procedure Q(var s: AnsiString); overload;
begin
  marker:=1;
end;

procedure Q(const s: UnicodeString); overload;
begin
  marker:=2;
end;

{$J+}
const
  wc : PI = nil;
{$J-}

begin
  gpb:=nil;
  gpi:=nil;
  ga:='';
  gset:=[];

  { a function result is not writable storage: the pointer-compatible var
    candidate must lose to the value overload, both declaration orders }
  P1(GetPB);
  if marker<>2 then
    halt(1);
  P2(GetPB);
  if marker<>2 then
    halt(2);

  { nil is not writable storage either }
  P1(nil);
  if marker<>2 then
    halt(3);
  P2(nil);
  if marker<>2 then
    halt(4);

  { a real pointer variable keeps choosing the var overload }
  P1(gpi);
  if marker<>1 then
    halt(5);
  P2(gpi);
  if marker<>1 then
    halt(6);

  { a writable typed constant is storage: var must still win }
  P1(wc);
  if marker<>1 then
    halt(7);
  P2(wc);
  if marker<>1 then
    halt(8);

  { a set literal is not writable storage }
  S([1,2]);
  if marker<>2 then
    halt(11);

  { a set variable is }
  S(gset);
  if marker<>1 then
    halt(12);

  { an AnsiString rvalue with a foreign code page must not survive as a
    var candidate through the encoding branch }
  Q(GetA);
  if marker<>2 then
    halt(13);
end.
