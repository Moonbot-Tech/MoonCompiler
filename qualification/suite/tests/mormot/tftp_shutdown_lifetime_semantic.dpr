program tftp_shutdown_lifetime_semantic;

{$APPTYPE CONSOLE}

uses
  {$ifdef FPC}
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  {$endif UNIX}
  {$endif FPC}
  SysUtils,
  Classes,
  {$ifndef FPC}
  Winapi.Windows,
  {$endif FPC}
  mormot.core.base,
  mormot.core.os,
  mormot.core.threads,
  mormot.net.tftp.client,
  mormot.net.tftp.server
  {$ifdef OSPOSIX}
  , mormot.lib.curl
  {$endif OSPOSIX};

var
  ConnectionStarted: integer;
  ConnectionDestroyed: integer;
  OwnerAccessed: integer;

type
  TSlowTftpConnection = class(TTftpConnectionThread)
  protected
    procedure Execute; override;
    procedure DoExecute; override;
  public
    destructor Destroy; override;
  end;

  TTestTftpServer = class(TTftpServerThread)
  public
    procedure AddTestConnection(Connection: TTftpConnectionThread);
    procedure TerminateAndWaitFinished(TimeOutMs: integer = 5000); override;
  end;

procedure TSlowTftpConnection.Execute;
begin
  { Isolate the ownership contract from the logger and real UDP state. }
  DoExecute;
end;

procedure TSlowTftpConnection.DoExecute;
begin
  InterlockedIncrement(ConnectionStarted);
  while not Terminated do
    SleepHiRes(1);
  { Stay alive beyond the deliberately short server timeout, then exercise the
    same owner access that the real transfer loop and destructor perform. }
  SleepHiRes(100);
  If fOwner.MaxRetry >= 0 then
    InterlockedIncrement(OwnerAccessed);
end;

destructor TSlowTftpConnection.Destroy;
begin
  inherited Destroy;
  InterlockedIncrement(ConnectionDestroyed);
end;

procedure TTestTftpServer.AddTestConnection(
  Connection: TTftpConnectionThread);
begin
  fConnection.Add(Connection);
  if Connection.Suspended then
    Connection.Start;
end;

procedure TTestTftpServer.TerminateAndWaitFinished(TimeOutMs: integer);
begin
  { The ownership contract must remain safe even when a caller requests a
    timeout shorter than a worker's final cleanup. }
  inherited TerminateAndWaitFinished(1);
end;

{$ifdef OSPOSIX}
procedure CheckRealTransfer;
const
  Port = '39699';
var
  I: integer;
  ResultCode: TCurlResult;
  Handle: TCurl;
  FileName: TFileName;
  Uri: RawUtf8;
  Source, Received: RawByteString;
  Server: TTftpServerThread;
begin
  if not CurlIsAvailable then
    Halt(20);
  SetLength(Source, 65537);
  for I := 1 to Length(Source) do
    PByteArray(pointer(Source))^[I - 1] := byte(I * 131 + I shr 8);
  FileName := TemporaryFileName;
  if not FileFromString(Source, FileName) then
    Halt(21);
  Server := TTftpServerThread.Create(ExtractFilePath(FileName), [ttoRrq], nil,
    '127.0.0.1', Port, 'tftp-transfer', {CacheTimeoutSecs=}0);
  try
    SleepHiRes(50);
    StringToUtf8(ExtractFileName(FileName), Uri);
    Uri := 'tftp://127.0.0.1:' + Port + '/' + Uri;
    Handle := curl.easy_init;
    if Handle = nil then
      Halt(22);
    try
      curl.easy_setopt(Handle, coUrl, pointer(Uri));
      curl.easy_setopt(Handle, coWriteFunction, @CurlWriteRawByteString);
      curl.easy_setopt(Handle, coWriteData, @Received);
      curl.easy_setopt(Handle, coTimeoutMs, 5000);
      ResultCode := curl.easy_perform(Handle);
    finally
      curl.easy_cleanup(Handle);
    end;
    if ResultCode <> crOk then
      Halt(23);
    if Received <> Source then
      Halt(24);
  finally
    Server.Free;
    DeleteFile(FileName);
  end;
end;
{$endif OSPOSIX}

var
  Context: TTftpContext;
  Connection: TSlowTftpConnection;
  Server: TTestTftpServer;
  StartedAt: Int64;
  DestroyedAtReturn: integer;

begin
  ConnectionStarted := 0;
  ConnectionDestroyed := 0;
  OwnerAccessed := 0;
  FillChar(Context, SizeOf(Context), 0);
  Context.BlockSize := 512;
  Context.FrameLen := 2;
  GetMem(Context.Frame, Context.FrameLen);
  FillChar(Context.Frame^, Context.FrameLen, 0);
  Context.FileStream := TMemoryStream.Create;
  Server := TTestTftpServer.Create('', [], nil, '127.0.0.1', '0',
    'tftp-lifetime', {CacheTimeoutSecs=}0);
  try
    Connection := TSlowTftpConnection.Create(Context, Server);
    Context.FileStream := nil; // ownership moved into Connection.fContext
    Server.AddTestConnection(Connection);
    StartedAt := GetTickCount64;
    while (InterlockedCompareExchange(ConnectionStarted, 0, 0) = 0) and
          (GetTickCount64 - StartedAt < 5000) do
      SleepHiRes(1);
    If InterlockedCompareExchange(ConnectionStarted, 0, 0) = 0 then
      Halt(1);
  finally
    Server.Free;
    FreeMem(Context.Frame);
    Context.FileStream.Free;
  end;
  DestroyedAtReturn := InterlockedCompareExchange(ConnectionDestroyed, 0, 0);
  If DestroyedAtReturn <> 1 then
  begin
    { Let a broken pre-fix worker finish before the test process exits. }
    SleepHiRes(250);
    Halt(2);
  end;
  If InterlockedCompareExchange(OwnerAccessed, 0, 0) <> 1 then
    Halt(10);
  {$ifdef OSPOSIX}
  CheckRealTransfer;
  {$endif OSPOSIX}
  WriteLn('TFTP_SHUTDOWN_LIFETIME_OK');
end.
