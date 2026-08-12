{ %CPU=i386,x86_64 }
program tdelphix86shiftfold1;

{$ifdef FPC}
  {$mode delphi}
{$endif}

var
  i32: longint;
  i64: int64;
  u64: uint64;
  count: byte;

procedure Observe(Value: uint64);
begin
  u64:=Value;
end;

function ShiftKind(Value: longint): byte; overload;
begin
  Result:=1;
end;

function ShiftKind(Value: longword): byte; overload;
begin
  Result:=2;
end;

function ShiftKind64(Value: int64): byte; overload;
begin
  Result:=1;
end;

function ShiftKind64(Value: uint64): byte; overload;
begin
  Result:=2;
end;

begin
  i32:=-1;
  count:=1;
  if uint64(i32 shr count)<>uint64($7fffffff) then
    halt(1);
  if uint64(longint(-1) shr 1)<>uint64($7fffffff) then
    halt(2);
  count:=32;
  if (longint(1) shl count)<>1 then
    halt(3);
  if (longint(1) shl 32)<>1 then
    halt(4);
  i64:=1;
  count:=64;
  if (i64 shl count)<>1 then
    halt(5);
  if (int64(1) shl 64)<>1 then
    halt(6);
  Observe(uint64(longint(-1) shl 32));
  if u64<>high(uint64) then
    halt(7);
  Observe(uint64(longint(-1) shr 32));
  if u64<>high(uint64) then
    halt(8);
  Observe(uint64(longint(-1) shl 63));
  if u64<>uint64($ffffffff80000000) then
    halt(9);
  i32:=longint(-1) shl 32;
  if i32<>-1 then
    halt(10);
  if ShiftKind(longint(-1) shl 32)<>1 then
    halt(11);
  if ShiftKind(longint(-1) shr 32)<>1 then
    halt(12);
  if (longint(-1) shl 31)<>low(longint) then
    halt(13);
  if uint64(longint(-1) shr 31)<>1 then
    halt(14);
  if (longint(-1) shl 33)<>-2 then
    halt(15);
  if uint64(longint(-1) shr 33)<>uint64($7fffffff) then
    halt(16);
  if ShiftKind(longword($ffffffff) shl 32)<>2 then
    halt(17);
  if (longword($ffffffff) shl 33)<>longword($fffffffe) then
    halt(18);
  if (int64(-1) shl 63)<>low(int64) then
    halt(19);
  if uint64(int64(-1) shr 63)<>1 then
    halt(20);
  if (int64(-1) shl 65)<>-2 then
    halt(21);
  if ShiftKind64(int64(-1) shl 64)<>1 then
    halt(22);
  if ShiftKind64(uint64(-1) shl 64)<>2 then
    halt(23);
end.
