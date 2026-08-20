program cbool_ord_domain_semantic;

{ Ord and equality over boolean types follow the measured DCC64 36.0 domain.

  Red forms (audit "C-bool comparisons и Ord"):
  - Ord of a boolean constant lost the Delphi constant domain:
    Ord(Pred(False)) gave 255 instead of -1, Ord(ByteBool/WordBool(True))
    gave -1 instead of the unsigned storage 255/65535 (ninl constant path
    sent every boolean constant through the runtime storage view);
  - the equality shortcut "x <> False" / "x = True" returned the raw
    C-bool operand: Ord(W <> False) gave -1 instead of 1 (nadd removed
    the compare and skipped the normalization the comparison promised).

  Known deviations kept as our contract (DCC's own domain is internally
  inconsistent there, see the audit record): 64-bit contexts over a
  runtime Ord(C-bool) sign-extend (DCC zero-extends), and explicit
  and/or/xor over C-bool variables produce payload -1 for True (DCC
  produces 1; truth agrees). }

{$mode delphiunicode}{$H+}
{$Q-}{$R-}

uses
  mormot.core.fpcx64mm,
  SysUtils;

const
  V = Pred(False);

var
  Fails: Integer = 0;
  B: Boolean;
  BB: ByteBool;
  WB: WordBool;
  LB: LongBool;
  B2: Boolean;
  n: Integer;

procedure Check(const Name: string; Got, Want: Int64);
begin
  if Got <> Want then
  begin
    WriteLn('FAIL ', Name, ' got=', Got, ' want=', Want);
    Inc(Fails);
  end;
end;

begin
  { constant domain (DCC): pasbool keeps the signed value, ByteBool and
    WordBool read unsigned storage, LongBool stays signed }
  Check('const-pasbool', Ord(V), -1);
  Check('const-pasbool-size', SizeOf(Ord(V)), 1);
  Check('const-bytebool', Ord(ByteBool(True)), 255);
  Check('const-wordbool', Ord(WordBool(True)), 65535);
  Check('const-longbool', Ord(LongBool(True)), -1);
  Check('const-int64-cast', Int64(Ord(WordBool(True))), 65535);

  { runtime reads agree with DCC in 8/16/32-bit contexts }
  B := True;
  BB := ByteBool(True);
  WB := WordBool(True);
  LB := LongBool(True);
  Check('run-pasbool', Ord(B), 1);
  Check('run-bytebool', Ord(BB), -1);
  Check('run-wordbool', Ord(WB), -1);
  Check('run-longbool', Ord(LB), -1);
  Check('run-sum', Ord(WB) + Ord(BB) + Ord(LB), -3);

  { the comparison contract: normalized boolean of the operand's width }
  Check('cmp-wordbool-ne', Ord(WB <> False), 1);
  Check('cmp-wordbool-eq', Ord(WB = True), 1);
  Check('cmp-bytebool-ne', Ord(BB <> False), 1);
  Check('cmp-longbool-eq', Ord(LB = True), 1);
  Check('cmp-false-side', Ord(WB = False), 0);
  Check('cmp-size', SizeOf(WB <> False), 2);
  Check('cmp-two-vars', Ord(WB <> B2), 1);
  B2 := WB <> False;
  Check('cmp-via-assign', Ord(B2), 1);
  if WB <> False then
    n := 1
  else
    n := 0;
  Check('cmp-via-if', n, 1);
  WB := WordBool(False);
  Check('cmp-false-value', Ord(WB <> False), 0);
  Check('cmp-eq-false', Ord(WB = False), 1);
  WB := WordBool(True);

  { pinned known deviations - our stable contract, not DCC parity }
  Check('dev-int64-of-ord', Int64(Ord(WB)), -1);
  Check('dev-xor-vars', Ord(WB xor ByteBool(BB)), 0);

  if Fails <> 0 then
    Halt(1);
  WriteLn('CBOOL_ORD_SEMANTIC_OK');
end.
