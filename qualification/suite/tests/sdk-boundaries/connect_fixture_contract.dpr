program connect_fixture_contract;

{$IFDEF MSWINDOWS}{$DEFINE OSWINDOWS}{$ELSE}{$DEFINE OSPOSIX}{$ENDIF}

uses System.SysUtils;

const
  NO_ERROR = 0;
{$IFDEF OSWINDOWS}
  WSAEINPROGRESS = 10036;
  WSAEWOULDBLOCK = 10035;
  WSATRY_AGAIN = 11002;
  WSAETIMEDOUT = 10060;
  WSAEINVAL = 10022;
  WSAEMFILE = 10024;
  WSAECONNREFUSED = 10061;
  WSAECONNRESET = 10054;
  WSAECONNABORTED = 10053;
{$ELSE}
  WSAEINPROGRESS = 115;
  WSATRY_AGAIN = 11;
  WSAETIMEDOUT = 110;
  WSAEINVAL = 22;
  WSAEMFILE = 24;
  WSAECONNREFUSED = 111;
  WSAECONNRESET = 104;
  WSAECONNABORTED = 103;
  ESysEPIPE = 32;
  ESysEINTR = 4;
{$ENDIF}

type
  TNetResult = (nrOK, nrRetry, nrNoSocket, nrNotFound, nrNotImplemented, nrClosed,
    nrFatalError, nrUnknownError, nrTooManyConnections, nrRefused, nrTimeout, nrInvalidParameter);
  TNetEvent = (neRead, neWrite, neError, neClosed);
  TNetEvents = set of TNetEvent;
  TNetSocket = class
    Socket: Integer;
    function MakeAsync: TNetResult;
    function MakeBlocking: TNetResult;
    function WaitFor(Ms: Integer; Events: TNetEvents): TNetEvents;
  end;
  TNetAddr = record
    Addr: array[0..15] of Byte;
    function Size: Integer;
    function SocketConnect(socket: TNetSocket; ms: Integer): TNetResult;
  end;

var
  NativeError, ConnectResult, ConnectError: Integer;
  ConnectCalls, BlockingCalls, WaitCalls, Checks, Failures: Integer;

function RawSocketErrNo: Integer;
begin
  Result := NativeError;
end;

function NetLastError(AnotherNonFatal: Integer = 0; Error: System.PInteger = nil): TNetResult; forward;
function NetCheck(res: Integer): TNetResult; forward;
function NetEventsToNetResult(ev: TNetEvents): TNetResult; forward;

function StandTick: Int64;
begin
  Result := 0;
end;

procedure SleepHiRes(Ms: Integer);
begin
end;

function connect(Socket: Integer; Address: Pointer; Size: Integer): Integer;
begin
  Inc(ConnectCalls);
  NativeError := ConnectError;
  Result := ConnectResult;
end;

function TNetSocket.MakeAsync: TNetResult;
begin
  Result := nrOK;
end;

function TNetSocket.MakeBlocking: TNetResult;
begin
  Inc(BlockingCalls);
  NativeError := 888;
  Result := nrOK;
end;

function TNetSocket.WaitFor(Ms: Integer; Events: TNetEvents): TNetEvents;
begin
  Inc(WaitCalls);
  NativeError := 777;
  Result := [neWrite];
end;

function TNetAddr.Size: Integer;
begin
  Result := SizeOf(Addr);
end;

{$I connect_implementations.inc}

procedure Check(Value: Boolean; const Text: string);
begin
  Inc(Checks);
  If not Value then begin
    Inc(Failures);
    Writeln('FAIL ', Text);
  end;
end;

procedure RunCase(Error, Ms: Integer; Expected: TNetResult; const Name: string);
var
  Address: TNetAddr;
  Socket: TNetSocket;
  Actual: TNetResult;
begin
  ConnectCalls := 0;
  BlockingCalls := 0;
  WaitCalls := 0;
  ConnectError := Error;
  If Error = 0 then ConnectResult := 0 else ConnectResult := -1;
  Address := Default(TNetAddr);
  Socket := TNetSocket.Create;
  try
    Actual := Address.SocketConnect(Socket, Ms);
    Check(Actual = Expected, Name + ' result');
    Check(ConnectCalls = 1, Name + ' exactly one connect');
    If Expected > nrRetry then begin
      Check(NativeError = Error, Name + ' native errno survives');
      Check((BlockingCalls = 0) and (WaitCalls = 0), Name + ' no OS follow-up after initial failure');
    end else If Ms < 0 then
      Check((BlockingCalls = 0) and (WaitCalls = 0), Name + ' does not wait for async completion')
    else
      Check((BlockingCalls = 1) and (WaitCalls = 1), Name + ' completes pending connect normally');
  finally
    Socket.Free;
  end;
end;

begin
  RunCase(99, -1, nrFatalError, 'immediate EADDRNOTAVAIL');
  RunCase(WSAECONNREFUSED, -1, nrRefused, 'immediate refusal');
  RunCase(WSAEINVAL, -1, nrInvalidParameter, 'immediate invalid parameter');
  RunCase(WSAEMFILE, -1, nrTooManyConnections, 'immediate descriptor exhaustion');
  RunCase(99, 1000, nrFatalError, 'timed immediate EADDRNOTAVAIL');
  RunCase(WSAEINPROGRESS, -1, nrOK, 'pending connect');
{$IFDEF OSPOSIX}
  RunCase(ESysEINTR, -1, nrOK, 'interrupted connect awaits completion');
{$ENDIF}
  RunCase(WSATRY_AGAIN, -1, nrOK, 'nonfatal retry connect');
{$IFDEF OSWINDOWS}
  RunCase(WSAEWOULDBLOCK, -1, nrOK, 'Windows would-block connect');
{$ENDIF}
  RunCase(0, -1, nrOK, 'immediate success');
  RunCase(WSAEINPROGRESS, 1000, nrOK, 'timed pending success');
  Writeln('CONNECT_FIXTURE_CONTRACT checks=', Checks, ' failures=', Failures);
  If Failures <> 0 then Halt(1);
end.
