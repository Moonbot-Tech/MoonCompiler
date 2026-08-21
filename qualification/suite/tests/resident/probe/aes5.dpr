program aes5;
{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch INLINEVARS}
{$endif}
{$APPTYPE CONSOLE}
{$Q-}{$R-}
uses
{$ifdef FPC}
  mormot.core.fpcx64mm,
{$endif}
  SysUtils;
{$I aescore.inc}

procedure Show(const Name: string; const B: TAesBlock);
var I: Integer; L: string;
begin
  L := '';
  for I := 0 to 15 do L := L + IntToHex(B[I], 2) + ' ';
  WriteLn(Name, L);
end;

var
  Key: TAesKey;
  Block, Temp: TAesBlock;
  Sched: TAesSchedule;
  I, C, Round_: Integer;
  A0, A1, A2, A3: Byte;
begin
  for I := 0 to 15 do Key[I] := KeyRef[I];
  for I := 0 to 15 do Block[I] := PlainRef[I];
  ExpandKey(Key, Sched);
  AddRoundKey(Block, Sched, 0);

  for Round_ := 1 to 2 do
  begin
    WriteLn('--- round ', Round_);
    Show('  in       : ', Block);
    for I := 0 to 15 do Block[I] := SBox[Block[I]];
    Show('  subbytes : ', Block);
    Temp := Block;
    for I := 0 to 3 do
    begin
      Block[I * 4 + 1] := Temp[((I + 1) mod 4) * 4 + 1];
      Block[I * 4 + 2] := Temp[((I + 2) mod 4) * 4 + 2];
      Block[I * 4 + 3] := Temp[((I + 3) mod 4) * 4 + 3];
    end;
    Show('  shiftrows: ', Block);
    if Round_ < 10 then
      for C := 0 to 3 do
      begin
        A0 := Block[C * 4]; A1 := Block[C * 4 + 1];
        A2 := Block[C * 4 + 2]; A3 := Block[C * 4 + 3];
        Block[C * 4] := GfMul(A0, 2) xor GfMul(A1, 3) xor A2 xor A3;
        Block[C * 4 + 1] := A0 xor GfMul(A1, 2) xor GfMul(A2, 3) xor A3;
        Block[C * 4 + 2] := A0 xor A1 xor GfMul(A2, 2) xor GfMul(A3, 3);
        Block[C * 4 + 3] := GfMul(A0, 3) xor A1 xor A2 xor GfMul(A3, 2);
      end;
    Show('  mixcols  : ', Block);
    AddRoundKey(Block, Sched, Round_);
    Show('  out      : ', Block);
  end;
  WriteLn('FIPS round2: in=A4 9C 7F F2..  sub=49 DE D2 89..  row=49 DB 87 3B..  mix=58 4D CA F1..  out=AA 8F 5F 03..');
end.
