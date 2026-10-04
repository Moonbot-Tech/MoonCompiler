program sse_store_place_semantic;

{ "movapd %xmm0,%xmm1 ... movsd %xmm1,mem" is one store of %xmm0, and the
  x86 peephole (OptPass1_V_MOVAP, "(V)MOVA*(V)MOVS*2(V)MOVS* 1") merges the
  pair.  At -O3 the two need not be adjacent, and the merged store went to
  the place of the copy, past everything between them.  Two red forms:

  Delta and Smooth are the difference with the value of the last call:
  "_time := Clock; _delta := _time - FOld; FOld := _time" (the text of
  TPTCTimer.Delta, packages/ptc).  The store of the new value passed the
  read of the old one: "call Clock; movsd %xmm0,FOld; subsd FOld,%xmm0", the
  difference was zero on every call.  Keep, Between and Twice have a read or
  a write of the cell between the copy and the store in other clothes.

  BandRd1 is the text of bandrd1, packages/numlib (eigh1.pas).  Its plane
  rotation "u := c*a[i] - s*a[j]; a[j] := s*a[i] + c*a[j]; a[i] := u" keeps
  u in a register while the second statement computes its indexes; the store
  of u passed the instructions which compute the index of a[i] and went to
  a[j].

  The values are those of Delphi 12.2 and of -O1. }

{$mode delphi}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  cwstring,
  {$endif UNIX}
  SysUtils;

type
  TTimer = class
  public
    FRunning: Boolean;
    FOld: Double;
    FPrev: Double;
    FSum: Double;
    FTicks: Double;
    function Clock: Double;
    function Half(Value: Double): Double;
    function Delta: Double;
    function Smooth(Value: Double): Double;
    function Keep(Value: Double): Double;
    function Between(Value: Double): Double;
    function Twice(Value: Double): Double;
  end;

  ArbFloat = Double;
  ArbInt = LongInt;
  arfloat1 = array[1..1000] of ArbFloat;

var
  Fails: Integer = 0;

procedure Check(Ok: Boolean; const Name: string);
begin
  if not Ok then
  begin
    WriteLn('FAIL ', Name);
    Inc(Fails);
  end;
end;

function TTimer.Clock: Double; noinline;
begin
  FTicks := FTicks + 2.5;
  Result := FTicks;
end;

function TTimer.Half(Value: Double): Double; noinline;
begin
  Result := Value * 0.5;
end;

function TTimer.Delta: Double;
var
  _time: Double;
  _delta: Double;
begin
  if FRunning then
  begin
    _time := Clock;
    _delta := _time - FOld;
    FOld := _time;
    if _delta < 0 then
      _delta := 0;
    Result := _delta;
  end
  else
    Result := 0;
end;

function TTimer.Smooth(Value: Double): Double;
var
  V, R: Double;
begin
  V := Half(Value);
  R := V + FOld;
  FOld := V;
  Result := R;
end;

{ the old value goes to another cell }
function TTimer.Keep(Value: Double): Double;
var
  V: Double;
begin
  V := Half(Value);
  FPrev := FOld;
  FOld := V;
  Result := V + 1;
end;

{ a write and a read of the cell stand between }
function TTimer.Between(Value: Double): Double;
var
  V: Double;
begin
  V := Half(Value);
  FOld := 1.5;
  FSum := FSum + FOld;
  FOld := V;
  Result := V * 2;
end;

{ the value is changed after the copy }
function TTimer.Twice(Value: Double): Double;
var
  V, W: Double;
begin
  V := Half(Value);
  W := V;
  V := V * FOld;
  FOld := W;
  Result := V;
end;

procedure bandrd1(var a: ArbFloat; n, m, rwidth: ArbInt; var d, cd: ArbFloat);

{ wilkinson linear algebra ii/8 procedure bandrd; matv = false }

var      j, k, l, r, maxr, maxl, ugl, ikr, jj, jj1, i, ll : ArbInt;
                            b, c, s, s2, c2, cs, u, u1, g : ArbFloat;
                                              pa, pd, pcd : ^arfloat1;
begin
  pa:=@a; pd:=@d; pcd:=@cd;
  for k:=1 to n-2 do
    begin
      if n-k<m then maxr:=n-k else maxr:=m;
      for r:=maxr downto 2 do
        begin
          ikr:=(k-1)*rwidth+r+1; g:=pa^[ikr]; j:=k+r;
          while (g <> 0) and (j <= n) do
            begin
              if j=k+r then
                begin
                  b:=-pa^[ikr-1]/pa^[ikr]; ugl:=k
                end else
                begin
                  b:=-pa^[(j-m-2)*rwidth+m+1]/g; ugl:=j-m
                end;
              s:=1/sqrt(1+b*b); c:=b*s; c2:=c*c; s2:=s*s; cs:=c*s;
              jj:=(j-1)*rwidth+1; jj1:=jj-rwidth;
              u:=c2*pa^[jj1]-2*cs*pa^[jj1+1]+s2*pa^[jj];
              u1:=s2*pa^[jj1]+2*cs*pa^[jj1+1]+c2*pa^[jj];
              pa^[jj1+1]:=cs*(pa^[jj1]-pa^[jj])+(c2-s2)*pa^[jj1+1];
              pa^[jj1]:=u; pa^[jj]:=u1;
              for l:=ugl to j-2 do
                begin
                  ll:=(l-1)*rwidth+j-l+1;
                  u:=c*pa^[ll-1]-s*pa^[ll];
                  pa^[ll]:=s*pa^[ll-1]+c*pa^[ll];
                  pa^[ll-1]:=u;
                end; {l}
              if j <> k+r then
                begin
                  i:=(j-m-2)*rwidth+m+1; pa^[i]:=c*pa^[i]-s*g
                end;
              if n-j < m-1 then maxl:=n-j else maxl:=m-1;
              for l:=1 to maxl do
                begin
                  u:=c*pa^[jj1+l+1]-s*pa^[jj+l];
                  pa^[jj+l]:=s*pa^[jj1+l+1]+c*pa^[jj+l];
                  pa^[jj1+l+1]:=u
                end; {l}
              if j+m <= n then
                begin
                  g:=-s*pa^[jj+m]; pa^[jj+m]:=c*pa^[jj+m]
                end;
              j:=j+m;
            end {j}
        end {r}
    end; {k}
  pd^[1]:=pa^[1]; pcd^[1]:=0;
  for j:=2 to n do
    begin
      pd^[j]:=pa^[(j-1)*rwidth+1];
      if m>0 then pcd^[j]:=pa^[(j-2)*rwidth+2] else pcd^[j]:=0
    end {j}
end; {bandrd1}

const
  BandN = 12;
  BandM = 3;
  BandWidth = 4;
  WantD: array[1..BandN] of UInt64 = (
    UInt64($3FFB400000000000), UInt64($401D911F1018324C), UInt64($4025208EAB73AB55),
    UInt64($402BBAFA774210B7), UInt64($4030FAC39285D824), UInt64($400240D0804996B7),
    UInt64($C001589366676DC8), UInt64($3FEEF68E3E9F5C74), UInt64($3FEBDDD14458E8A4),
    UInt64($BF7435ADE9FF9900), UInt64($3FB4B7083D4F8630), UInt64($BFDDFB8D265E6460));
  WantCD: array[1..BandN] of UInt64 = (
    UInt64($0000000000000000), UInt64($4008EE74B960803F), UInt64($401B06316AE40422),
    UInt64($40235104BCC2506C), UInt64($C0288222970273F5), UInt64($401D92FCF68BBDEF),
    UInt64($BFF325571690CA81), UInt64($40103AEEB285B9FC), UInt64($3FFDAE6BD2007349),
    UInt64($3FE402D1573F42CE), UInt64($3FF398C1B18F66B2), UInt64($4004EC8FB7B20AFE));
  WantBand = UInt64($7E9CEC8B3F460A16);

function Bits(Value: Double): UInt64;
begin
  Move(Value, Result, SizeOf(Result));
end;

var
  T: TTimer;
  A: array[1..BandN * BandWidth + 8] of Double;
  D, CD: array[1..BandN] of Double;
  I, Bad: Integer;
  Sum: UInt64;
begin
  T := TTimer.Create;
  T.FRunning := True;
  T.FOld := 1;
  Check(T.Delta = 1.5, 'delta, first call');
  Check(T.Delta = 2.5, 'delta, second call');
  Check(T.FOld = 5, 'delta, the cell');
  T.FOld := 7;
  Check(T.Smooth(10) = 12, 'smooth, first call');
  Check(T.Smooth(3) = 6.5, 'smooth, second call');
  Check(T.FOld = 1.5, 'smooth, the cell');
  T.FOld := 4;
  Check(T.Keep(9) = 5.5, 'keep, the result');
  Check(T.FPrev = 4, 'keep, the old value');
  Check(T.FOld = 4.5, 'keep, the cell');
  T.FSum := 10;
  Check(T.Between(6) = 6, 'between, the result');
  Check(T.FSum = 11.5, 'between, the sum');
  Check(T.FOld = 3, 'between, the cell');
  T.FOld := 3;
  Check(T.Twice(8) = 12, 'twice, the result');
  Check(T.FOld = 4, 'twice, the cell');
  T.Free;

  for I := 1 to High(A) do
    A[I] := 1 + ((I * 37) mod 64) / 64 + I / 8;
  bandrd1(A[1], BandN, BandM, BandWidth, D[1], CD[1]);
  Sum := 0;
  for I := 1 to High(A) do
    Sum := (Sum xor Bits(A[I])) * UInt64($100000001B3);
  Check(Sum = WantBand, 'band, the matrix');
  Bad := 0;
  for I := 1 to BandN do
    if (Bits(D[I]) <> WantD[I]) or (Bits(CD[I]) <> WantCD[I]) then
      Inc(Bad);
  Check(Bad = 0, 'band, the diagonals');

  if Fails = 0 then
    WriteLn('SSE_STORE_PLACE_PASS')
  else
  begin
    WriteLn('SSE_STORE_PLACE_FAIL ', Fails);
    Halt(1);
  end;
end.
