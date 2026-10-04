program set_variable_bit_ops;

{$mode delphiunicode}

type
  TSet8 = set of 0..7;
  TSet16 = set of 0..15;
  TSet32 = set of 0..31;

var
  S8: TSet8;
  S16: TSet16;
  S32: TSet32;
  I: Integer;
begin
  I := 7;
  S8 := [];
  Include(S8, I);
  If not (7 in S8) then Halt(1);
  Exclude(S8, I);
  If 7 in S8 then Halt(2);

  I := 13;
  S16 := [];
  Include(S16, I);
  If not (13 in S16) then Halt(3);
  Exclude(S16, I);
  If 13 in S16 then Halt(4);

  I := 29;
  S32 := [];
  Include(S32, I);
  If not (29 in S32) then Halt(5);
  Exclude(S32, I);
  If 29 in S32 then Halt(6);

  Writeln('SET_VARIABLE_BIT_OPS_OK');
end.
