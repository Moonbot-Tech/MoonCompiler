program memory_footprint_10x10m;

{$mode delphi}

uses
  cthreads,
  mormot.core.fpcx64mm,
  BaseUnix,
  SysUtils,
  Classes;

const
  WorkerCount = 10;
  BytesPerWorker = 10 * 1024 * 1024;
  SmallBlockSize = 64;
  MediumBlockSize = 64 * 1024;

type
  TProfile = (
    fpSmall,
    fpMedium,
    fpMixed);

  TFootprintThread = class(TThread)
  private
    FProfile: TProfile;
    FHead: Pointer;
    FRequested: QWord;
    FCapacity: QWord;
    FError: Integer;
    procedure AllocateBytes(Bytes, BlockSize: PtrUInt);
    procedure ReleaseBlocks;
  protected
    procedure Execute; override;
  public
    constructor Create(Profile: TProfile);
    property Requested: QWord read FRequested;
    property Capacity: QWord read FCapacity;
    property Error: Integer read FError;
  end;

var
  Stage: LongInt;
  Started: LongInt;
  Ready: LongInt;

procedure WaitForValue(var Value: LongInt; Expected: LongInt);
begin
  while Value <> Expected do
    Sleep(0);
end;

constructor TFootprintThread.Create(Profile: TProfile);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FProfile := Profile;
end;

procedure TFootprintThread.AllocateBytes(Bytes, BlockSize: PtrUInt);
var
  P: Pointer;
  Size: PtrUInt;
begin
  while Bytes <> 0 do
  begin
    Size := BlockSize;
    If Size > Bytes then
      Size := Bytes;
    P := _GetMem(Size);
    If P = nil then
      raise EOutOfMemory.Create('allocation failed');
    FillChar(P^, Size, Byte(ThreadID));
    PPointer(P)^ := FHead;
    FHead := P;
    Inc(FRequested, Size);
    Inc(FCapacity, _MemSize(P));
    Dec(Bytes, Size);
  end;
end;

procedure TFootprintThread.ReleaseBlocks;
var
  Next: Pointer;
begin
  while FHead <> nil do
  begin
    Next := PPointer(FHead)^;
    _FreeMem(FHead);
    FHead := Next;
  end;
end;

procedure TFootprintThread.Execute;
begin
  InterlockedIncrement(Started);
  while Stage = 0 do
    Sleep(0);
  try
    case FProfile of
      fpSmall:
        AllocateBytes(BytesPerWorker, SmallBlockSize);
      fpMedium:
        AllocateBytes(BytesPerWorker, MediumBlockSize);
      fpMixed:
        begin
          AllocateBytes(BytesPerWorker div 2, SmallBlockSize);
          AllocateBytes(BytesPerWorker div 2, MediumBlockSize);
        end;
    end;
  except
    FError := 1;
  end;
  InterlockedIncrement(Ready);
  WaitForValue(Stage, 2);
  ReleaseBlocks;
end;

function ReadStatusValue(const Buffer; BufferLength: Integer;
  const Name: PChar; NameLength: Integer): QWord;
var
  Bytes: PByte;
  I: Integer;
begin
  Result := 0;
  Bytes := @Buffer;
  I := 0;
  while I <= BufferLength - NameLength - 1 do
  begin
    If CompareMem(@Bytes[I], Name, NameLength) then
    begin
      Inc(I, NameLength);
      while (I < BufferLength) and
            ((Bytes[I] = Ord(' ')) or (Bytes[I] = Ord(#9))) do
        Inc(I);
      while (I < BufferLength) and
            (Bytes[I] >= Ord('0')) and (Bytes[I] <= Ord('9')) do
      begin
        Result := Result * 10 + Bytes[I] - Ord('0');
        Inc(I);
      end;
      Result := Result * 1024;
      Exit;
    end;
    Inc(I);
  end;
end;

procedure ReadProcessMemory(out VmSize, Rss: QWord);
const
  VmSizeName: PChar = 'VmSize:';
  VmRssName: PChar = 'VmRSS:';
var
  Buffer: array[0..16383] of Byte;
  FileHandle: THandle;
  ReadCount: Int64;
begin
  FileHandle := fpOpen('/proc/self/status', O_RDONLY);
  If FileHandle < 0 then
    RaiseLastOSError;
  try
    ReadCount := fpRead(FileHandle, Buffer[0], SizeOf(Buffer));
    If ReadCount <= 0 then
      RaiseLastOSError;
  finally
    fpClose(FileHandle);
  end;
  VmSize := ReadStatusValue(Buffer, ReadCount, VmSizeName, 7);
  Rss := ReadStatusValue(Buffer, ReadCount, VmRssName, 6);
  If (VmSize = 0) or (Rss = 0) then
    raise Exception.Create('unable to parse /proc/self/status');
end;

function ProfileName(Profile: TProfile): string;
begin
  case Profile of
    fpSmall:
      Result := 'small64';
    fpMedium:
      Result := 'medium64k';
    fpMixed:
      Result := 'mixed50';
  end;
end;

function ParseProfile: TProfile;
begin
  If ParamCount <> 1 then
    raise Exception.Create('usage: memory_footprint_10x10m small64|medium64k|mixed50');
  If ParamStr(1) = 'small64' then
    Result := fpSmall
  else If ParamStr(1) = 'medium64k' then
    Result := fpMedium
  else If ParamStr(1) = 'mixed50' then
    Result := fpMixed
  else
    raise Exception.Create('unknown profile');
end;

var
  Profile: TProfile;
  Workers: array[0..WorkerCount - 1] of TFootprintThread;
  IdleStatus, LoadedStatus: TMMStatus;
  IdleVmSize, IdleRss, LoadedVmSize, LoadedRss: QWord;
  Requested, Capacity: QWord;
  Created, I: Integer;
begin
  Profile := ParseProfile;
  InitializeMemoryManager;
  try
    Created := 0;
    try
      for I := 0 to High(Workers) do
      begin
        Workers[I] := TFootprintThread.Create(Profile);
        Workers[I].Start;
        Inc(Created);
      end;
      WaitForValue(Started, WorkerCount);
      IdleStatus := CurrentHeapStatus;
      ReadProcessMemory(IdleVmSize, IdleRss);
      InterlockedExchange(Stage, 1);
      WaitForValue(Ready, WorkerCount);
      Requested := 0;
      Capacity := 0;
      for I := 0 to High(Workers) do
      begin
        If Workers[I].Error <> 0 then
          raise Exception.Create('worker allocation failed');
        Inc(Requested, Workers[I].Requested);
        Inc(Capacity, Workers[I].Capacity);
      end;
      LoadedStatus := CurrentHeapStatus;
      ReadProcessMemory(LoadedVmSize, LoadedRss);
      WriteLn('FOOTPRINT profile=', ProfileName(Profile),
        ' threads=', WorkerCount,
        ' requested=', Requested,
        ' capacity=', Capacity,
        ' idle-vmsize=', IdleVmSize,
        ' loaded-vmsize=', LoadedVmSize,
        ' delta-vmsize=', LoadedVmSize - IdleVmSize,
        ' idle-rss=', IdleRss,
        ' loaded-rss=', LoadedRss,
        ' delta-rss=', LoadedRss - IdleRss,
        ' idle-mm-medium=', IdleStatus.Medium.CurrentBytes,
        ' loaded-mm-medium=', LoadedStatus.Medium.CurrentBytes,
        ' delta-mm-medium=', LoadedStatus.Medium.CurrentBytes -
          IdleStatus.Medium.CurrentBytes,
        ' small-capacity=', LoadedStatus.SmallBlocksSize);
    finally
      InterlockedExchange(Stage, 2);
      for I := 0 to Created - 1 do
      begin
        Workers[I].WaitFor;
        Workers[I].Free;
      end;
    end;
  finally
    FreeAllMemory;
  end;
end.
