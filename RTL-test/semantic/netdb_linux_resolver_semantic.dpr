program netdb_linux_resolver_semantic;

{%TARGET=linux}
{$mode delphi}{$H+}

uses
  mormot.core.fpcx64mm,
  cthreads,
  cwstring,
  System.SysUtils,
  System.Classes,
  Sockets,
  NetDB;

const
  WorkerCount = 4;
  WorkerIterations = 16;

type
  TResolverThread = class(TThread)
  public
    Failure: string;
    procedure Execute; override;
  end;

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create('NETDB_LINUX_RESOLVER_FAIL: '+AMessage);
end;

function HasIPv4Localhost(const Addresses: array of THostAddr;
  Count: Integer): Boolean;
var
  I: Integer;
begin
  Result:=False;
  for I:=0 to Count-1 do
    if NetAddrToStr(Addresses[I])='127.0.0.1' then
      Exit(True);
end;

function HasIPv6OrMappedLocalhost(const Addresses: array of THostAddr6;
  Count: Integer): Boolean;
var
  I, J: Integer;
  IsIPv6Loopback, IsMappedIPv4Loopback: Boolean;
begin
  Result:=False;
  for I:=0 to Count-1 do
    begin
    IsIPv6Loopback:=Addresses[I].u6_addr8[15]=1;
    for J:=0 to 14 do
      IsIPv6Loopback:=IsIPv6Loopback and (Addresses[I].u6_addr8[J]=0);
    IsMappedIPv4Loopback:=
      (Addresses[I].u6_addr8[10]=$ff) and
      (Addresses[I].u6_addr8[11]=$ff) and
      (Addresses[I].u6_addr8[12]=127) and
      (Addresses[I].u6_addr8[13]=0) and
      (Addresses[I].u6_addr8[14]=0) and
      (Addresses[I].u6_addr8[15]=1);
    for J:=0 to 9 do
      IsMappedIPv4Loopback:=IsMappedIPv4Loopback and
        (Addresses[I].u6_addr8[J]=0);
    if IsIPv6Loopback or IsMappedIPv4Loopback then
      Exit(True);
    end;
end;

function HasPureIPv6Loopback(const Addresses: array of THostAddr6;
  Count: Integer): Boolean;
var
  I, J: Integer;
  IsLoopback: Boolean;
begin
  Result:=False;
  for I:=0 to Count-1 do
    begin
    IsLoopback:=Addresses[I].u6_addr8[15]=1;
    for J:=0 to 14 do
      IsLoopback:=IsLoopback and (Addresses[I].u6_addr8[J]=0);
    if IsLoopback then
      Exit(True);
    end;
end;

procedure CheckResolver;
var
  Addresses4: array[0..7] of THostAddr;
  Addresses6: array[0..7] of THostAddr6;
  Host: THostEntry;
  Count: Integer;
begin
  Count:=ResolveName('localhost',Addresses4);
  Check((Count>0) and HasIPv4Localhost(Addresses4,Count),'IPv4 localhost');

  Count:=ResolveName6('localhost',Addresses6);
  Check((Count>0) and HasIPv6OrMappedLocalhost(Addresses6,Count),
    'IPv6 or IPv4-mapped localhost');

  Count:=ResolveName6('::1',Addresses6);
  Check((Count>0) and HasPureIPv6Loopback(Addresses6,Count),
    'numeric IPv6 loopback');

  Count:=ResolveName('mooncompiler-netdb-nxdomain.invalid',Addresses4);
  Check(Count<0,'NXDOMAIN');

  Check(GetHostByName('localhost',Host),'/etc/hosts API was changed');
end;

procedure TResolverThread.Execute;
var
  Addresses: array[0..3] of THostAddr;
  Count: Integer;
  I: Integer;
begin
  try
    for I:=1 to WorkerIterations do
      begin
      Count:=ResolveName('localhost',Addresses);
      Check((Count>0) and HasIPv4Localhost(Addresses,Count),
        'concurrent IPv4 localhost');
      end;
  except
    on E: Exception do
      Failure:=E.ClassName+': '+E.Message;
  end;
end;

var
  Workers: array[0..WorkerCount-1] of TResolverThread;
  I: Integer;

begin
  CheckResolver;
  for I:=Low(Workers) to High(Workers) do
    begin
    Workers[I]:=TResolverThread.Create(True);
    Workers[I].FreeOnTerminate:=False;
    Workers[I].Start;
    end;
  for I:=Low(Workers) to High(Workers) do
    begin
    Workers[I].WaitFor;
    Check(Workers[I].Failure='',Workers[I].Failure);
    Workers[I].Free;
    end;
  WriteLn('NETDB_LINUX_RESOLVER_PASS');
end.
