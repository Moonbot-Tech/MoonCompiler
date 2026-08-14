program tdelphimixeduint641;

{$ifdef FPC}
  {$mode delphi}
{$endif}

uses
  math;

const
  untypedone=1;
  typedintegerone:integer=1;
  typedint64one:int64=1;

var
  i: integer;
  s: int64;
  u, z: uint64;
  p: ptruint;

function kind(value: integer): byte; overload;
  begin
    result:=3;
end;

function kind(value: cardinal): byte; overload;
  begin
    result:=4;
end;

function kind(value: int64): byte; overload;
  begin
    result:=1;
  end;

function kind(value: uint64): byte; overload;
  begin
    result:=2;
  end;

function pairkind(a,b:int64):byte;overload;
  begin
    result:=1;
  end;

function pairkind(a,b:uint64):byte;overload;
  begin
    result:=2;
  end;

function pairkindreverse(a,b:uint64):byte;overload;
  begin
    result:=2;
  end;

function pairkindreverse(a,b:int64):byte;overload;
  begin
    result:=1;
  end;

begin
  s:=-1;
  i:=1;
  u:=2;
  z:=0;
  if kind(s+u)<>1 then
    halt(1);
  if kind(s div u)<>1 then
    halt(2);
  if uint64(s div u)<>high(int64) then
    halt(3);
  if not (s<u) then
    halt(4);
  if not ((u<>0) and (z=0)) then
    halt(5);
  u:=41;
  if kind(u+1)<>2 then
    halt(6);
  if kind(1+u)<>2 then
    halt(7);
  if kind(u-1)<>2 then
    halt(8);
  if kind(u*2)<>2 then
    halt(9);
  if kind(u or 1)<>2 then
    halt(10);
  if kind(u xor 1)<>2 then
    halt(11);
  if kind(u and 1)<>2 then
    halt(12);
  if kind(u div 2)<>2 then
    halt(13);
  if kind(u mod 2)<>2 then
    halt(14);
  if kind(u+untypedone)<>2 then
    halt(15);
  if kind(u+typedintegerone)<>1 then
    halt(16);
  if kind(u+typedint64one)<>1 then
    halt(17);
  if kind(u+i)<>1 then
    halt(18);
  if kind(u+int64(1))<>1 then
    halt(19);
  if kind(u+2147483647)<>2 then
    halt(20);
  if kind(u+2147483648)<>2 then
    halt(21);
  if kind(u+4294967295)<>2 then
    halt(22);
  if kind(u+4294967296)<>1 then
    halt(23);
  if max(u,u+1)<>42 then
    halt(24);
  if pairkind(u,u+typedintegerone)<>2 then
    halt(25);
  if pairkind(u+i,u)<>2 then
    halt(26);
  if pairkind(u,u mod 4294967296)<>2 then
    halt(27);
  if pairkindreverse(u,u+typedintegerone)<>2 then
    halt(28);
  p:=65536;
  if (p<65536) or (p>1114111) then
    halt(29);
end.
