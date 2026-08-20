program constref_formal_semantic;

{ An untyped constref parameter promises the callee an address for every
  admitted actual.

  The red form (audit 5daacab2): the validator accepts a non-void call
  result as an untyped constref actual, but only vs_const materialized a
  non-reference actual before push_addr_para - vs_constref reached the
  backend without a LOC_REFERENCE and died with internal error 200304235.
  Materialization now covers both formal kinds; forms the frontend rejects
  (literals, indexed call results, cast constants) keep their clean
  compile-time error. }

{$mode delphiunicode}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}cthreads,cwstring,{$endif UNIX}
  SysUtils,
  constref_remote_probe;

var
  Fails: Integer = 0;
  EvalCount: Integer = 0;

function MakeValue: UInt32; noinline;
begin
  Inc(EvalCount);
  Result := $11223344;
end;

function MakeByte: Byte; noinline;
begin
  Result := 200;
end;

function MakeStr: UnicodeString; noinline;
begin
  Result := 'abcdef';
end;

function Peek(constref X): UInt32;
var
  V: UInt32 absolute X;
begin
  Result := V;
end;

function PeekInline(constref X): UInt32; inline;
var
  V: UInt32 absolute X;
begin
  Result := V;
end;

function PeekBytes(constref X): Byte;
var
  B: Byte absolute X;
begin
  Result := B;
end;

procedure Check(const Name: string; Got, Want: UInt64);
begin
  if Got <> Want then
  begin
    WriteLn('FAIL ', Name, ' got=', IntToHex(Got, 8), ' want=', IntToHex(Want, 8));
    Inc(Fails);
  end;
end;

var
  Arr: array[0..3] of Byte;
  S: UnicodeString;
begin
  { the original lvalue form of tw41766 stays valid }
  Arr[0] := $AA;
  Check('lvalue-elem', PeekBytes(Arr[0]), $AA);
  { call-result actuals are materialized once }
  Check('call-result', Peek(MakeValue), $11223344);
  Check('single-eval', EvalCount, 1);
  Check('inline-call-result', PeekInline(MakeValue), $11223344);
  Check('inline-single-eval', EvalCount, 2);
  { managed lvalue }
  S := MakeStr;
  Check('managed-elem', PeekBytes(S[1]), Ord('a'));
  { PPU boundary }
  Check('cross-unit', PeekRemote(MakeByte), 200);
  if Fails <> 0 then
    Halt(1);
  WriteLn('CONSTREF_FORMAL_SEMANTIC_OK');
end.
