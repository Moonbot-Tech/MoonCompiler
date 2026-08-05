{ %OPT=-O3 }
program tmoddividentity1;

{$mode delphi}

function Kind(Value: Byte): Byte; overload;
begin
  Result := 1;
end;

function Kind(Value: Word): Byte; overload;
begin
  Result := 2;
end;

function Kind(Value: Integer): Byte; overload;
begin
  Result := 3;
end;

function Kind(Value: Cardinal): Byte; overload;
begin
  Result := 4;
end;

function Kind(Value: Int64): Byte; overload;
begin
  Result := 5;
end;

var
  B: Byte;
  W: Word;
  I: Integer;
  C: Cardinal;
begin
  B := 7;
  W := 257;
  I := -7;
  C := 7;

  If Kind(B div 1) <> 3 then Halt(1);
  If Kind(B mod 1) <> 3 then Halt(2);
  If Kind(W div 1) <> 3 then Halt(3);
  If Kind(W mod 1) <> 3 then Halt(4);
  If Kind(I div 1) <> 3 then Halt(5);
  If Kind(I mod 1) <> 3 then Halt(6);
  If Kind(C div 1) <> 4 then Halt(7);
  If Kind(C mod 1) <> 4 then Halt(8);

  If (B div 1) <> 7 then Halt(9);
  If (B mod 1) <> 0 then Halt(10);
  If (W div 1) <> 257 then Halt(11);
  If (W mod 1) <> 0 then Halt(12);
  If (I div 1) <> -7 then Halt(13);
  If (I mod 1) <> 0 then Halt(14);
end.
