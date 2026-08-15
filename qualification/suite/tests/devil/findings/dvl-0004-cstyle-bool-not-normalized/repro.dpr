program wbool;
{$ifdef FPC}
  {$mode delphiunicode}{$H+}
{$endif}
{$APPTYPE CONSOLE}
{$Q-}{$R-}
uses SysUtils;

type
  TRec = record
    W: WordBool;
    B: ByteBool;
    L: LongBool;
  end;

var
  R: TRec;
begin
  R.W := True;
  R.B := True;
  R.L := True;
  WriteLn('ord(wordbool)      = ', IntToHex(UInt64(Ord(R.W)), 16));
  WriteLn('ord(w <> False)    = ', IntToHex(UInt64(Ord(R.W <> False)), 16));
  WriteLn('ord(w = True)      = ', IntToHex(UInt64(Ord(R.W = True)), 16));
  WriteLn('ord(bytebool)      = ', IntToHex(UInt64(Ord(R.B)), 16));
  WriteLn('ord(b <> False)    = ', IntToHex(UInt64(Ord(R.B <> False)), 16));
  WriteLn('ord(longbool)      = ', IntToHex(UInt64(Ord(R.L)), 16));
  WriteLn('ord(l <> False)    = ', IntToHex(UInt64(Ord(R.L <> False)), 16));
end.
