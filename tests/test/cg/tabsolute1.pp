{ %OPT=-O2 }
program tabsolute1;

{$mode objfpc}

type
  TInner = packed record
    A, B, C: Word;
  end;

  TSource = packed record
    Inner: TInner;
    R: Word;
  end;

  TDest = packed record
    R: Word;
    Inner: TInner;
  end;

function Rotate(P: Pointer): Pointer; inline;
var
  Source: TSource absolute P;
  Dest: TDest absolute Result;
begin
  Dest.R := Source.R;
  Dest.Inner.A := Source.Inner.A;
  Dest.Inner.B := Source.Inner.B;
  Dest.Inner.C := Source.Inner.C;
end;

var
  Input, Got: Pointer;
begin
  Input := Pointer(PtrUInt($1122334455667788));
  Got := Rotate(Input);
  if PtrUInt(Got) <> PtrUInt($3344556677881122) then
    begin
      WriteLn('FAIL actual=',HexStr(PtrUInt(Got),16));
      Halt(1);
    end;
end.
