program cardinal_zero_extension_semantic;

{ UInt64(Cardinal(...)) must zero-extend for every value shape.

  The red form (Devil dvl-0001): O3 propagates an Integer array element
  into an immediate, leaving "movl $imm,%reg; movq %reg,%dest".  The
  MovMov2Mov peephole merged the pair into "movq $imm,%dest", turning the
  zero-extension of a negative immediate into a sign-extension.  The exact
  shape needs the IntToHex consumption beside the conversion, so this test
  keeps the original repro layout and pins the neighbours around it. }

{$mode delphiunicode}{$H+}
{$Q-}{$R-}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}cthreads,cwstring,{$endif UNIX}
  SysUtils;

var
  Fails: Integer = 0;

procedure Check(const Name: string; Got, Want: UInt64);
begin
  if Got <> Want then
  begin
    WriteLn('FAIL ', Name, ' got=', IntToHex(Got, 16), ' want=', IntToHex(Want, 16));
    Inc(Fails);
  end;
end;

function RawI32(V: Integer): UInt64;
begin
  Result := UInt64(Cardinal(V));
end;

function BinExpr(A, B: Integer): UInt64;
begin
  Result := UInt64(Cardinal(A + B));
end;

function SuccForm(V: Integer): UInt64;
begin
  Result := UInt64(Cardinal(Succ(V)));
end;

function NotForm(V: Cardinal): UInt64;
begin
  Result := UInt64(not V);
end;

function MemDest(V: Integer): UInt64;
var
  Store: array[0..1] of UInt64;
begin
  Store[0] := UInt64(Cardinal(V));
  Store[1] := Store[0];
  Result := Store[1];
end;

procedure Probe;
var
  R: UInt64;
  Arr: array[0..3] of Integer;
begin
  Arr[1] := Integer(-1581716328);
  R := RawI32(Arr[1]);
  { the IntToHex consumption is part of the triggering shape - keep it }
  if IntToHex(R, 16) <> '00000000A1B8EC98' then
  begin
    WriteLn('FAIL array-element hex = ', IntToHex(R, 16));
    Inc(Fails);
  end;
  Check('array-element', R, UInt64($00000000A1B8EC98));
  Check('binexpr', BinExpr(Arr[1], 0), UInt64($00000000A1B8EC98));
  Check('succ', SuccForm(Arr[1]), UInt64($00000000A1B8EC99));
  Check('not', NotForm(Cardinal($A1B8EC98)), UInt64($000000005E471367));
  Check('memdest', MemDest(Arr[1]), UInt64($00000000A1B8EC98));
  Check('positive', RawI32(Integer(Arr[1] and $7FFFFFFF)), UInt64($0000000021B8EC98));
  Check('const-form', UInt64(Cardinal(Integer(-1581716328))), UInt64($00000000A1B8EC98));
end;

begin
  Probe;
  if Fails <> 0 then
    Halt(1);
  WriteLn('ZEROEXT_SEMANTIC_OK');
end.
