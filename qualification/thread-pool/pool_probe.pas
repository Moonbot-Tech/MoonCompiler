unit pool_probe;

{$mode objfpc}{$H+}

interface

uses SysUtils, SyncObjs;

var
  ProbePool: TObject;
  ProbePoint: LongInt;
  Arrived, Proceed: TSemaphore;

procedure PoolProbe(APoint: LongInt; APool: TObject);

implementation

procedure PoolProbe(APoint: LongInt; APool: TObject);
begin
  if (APool=ProbePool) and (AtomicCmpExchange(ProbePoint,0,0)=APoint) then
    begin
    Arrived.Release;
    if Proceed.WaitFor(10000)<>wrSignaled then
      Halt(3);
    end;
end;

end.
