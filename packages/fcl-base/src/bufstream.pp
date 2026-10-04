{
    This file is part of the Free Component Library.
    Copyright (c) 1999-2000 by the Free Pascal development team

    Implement a buffered stream.
    TBufferedFileStream contributed by José Mejuto, bug ID 30549.

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}

{$mode objfpc}
{$H+}
{$IFNDEF FPC_DOTTEDUNITS}
unit BufStream;
{$ENDIF FPC_DOTTEDUNITS}

interface

{$IFDEF FPC_DOTTEDUNITS}
uses
  System.Classes, System.SysUtils;
{$ELSE FPC_DOTTEDUNITS}
uses
  Classes, SysUtils;
{$ENDIF FPC_DOTTEDUNITS}

Const
  DefaultBufferCapacity : Integer = 16; // Default buffer capacity in Kb.

Type

{ ---------------------------------------------------------------------
  TBufStream - simple read or write buffer, for sequential reading/writing
  ---------------------------------------------------------------------}

  TBufStream = Class(TOwnerStream)
  Private
    FTotalPos : Int64;
    Fbuffer: Pointer;
    FBufPos: Integer;
    FBufSize: Integer;
    FCapacity: Integer;
    procedure SetCapacity(const AValue: Integer);
  Protected
    function GetPosition: Int64; override;
    function GetSize: Int64; override;
    procedure BufferError(const Msg : String);
    Procedure FillBuffer; Virtual;
    Procedure FlushBuffer; Virtual;
  Public
    Constructor Create(ASource : TStream; ACapacity: Integer);
    Constructor Create(ASource : TStream);
    Destructor Destroy; override;
    Property Buffer : Pointer Read Fbuffer;
    Property Capacity : Integer Read FCapacity Write SetCapacity;
    Property BufferPos : Integer Read FBufPos; // 0 based.
    Property BufferSize : Integer Read FBufSize; // Number of bytes in buffer.
  end;

  { TReadBufStream }

  TReadBufStream = Class(TBufStream)
  Public
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; override;
    Function Read(var ABuffer; ACount : LongInt) : Integer; override;
  end;

  { TWriteBufStream }

  TWriteBufStream = Class(TBufStream)
  Public
    Destructor Destroy; override;
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; override;
    Function Write(Const ABuffer; ACount : LongInt) : Integer; override;
  end;

{ ---------------------------------------------------------------------
  TBufferedFileStream -
  Multiple pages buffer for random access reading/writing in file.
  ---------------------------------------------------------------------}

  TBufferedFileStream = class(TFileStream)
  private
    const
      TSTREAMCACHEPAGE_SIZE_DEFAULT=4*1024;
      TSTREAMCACHEPAGE_MAXCOUNT_DEFAULT=8;
    type
      TStreamCacheEntry=record
        IsDirty: Boolean;
        LastTick: NativeUInt;
        PageBegin: int64;
        PageRealSize: integer;
        Buffer: Pointer;
      end;
      PStreamCacheEntry=^TStreamCacheEntry;
  private
    FCachePages: array of PStreamCacheEntry;
    FCacheLastUsedPage: integer;
    FCacheStreamPosition: int64;
    FCacheStreamSize: int64;
    FOpCounter: NativeUInt;
    FStreamCachePageSize: integer;
    FStreamCachePageMaxCount: integer;
    FEmergencyFlag: Boolean;
    procedure ClearCache;
    procedure WriteDirtyPage(const aPage: PStreamCacheEntry);
    procedure WriteDirtyPage(const aIndex: integer);
    procedure WriteDirtyPages;
    procedure EmergencyWriteDirtyPages;
    procedure FreePage(const aPage: PStreamCacheEntry; const aFreeBuffer: Boolean); inline;
    procedure ExtendPageWithZeros(const aPage: PStreamCacheEntry);
    function  LookForPositionInPages: Boolean;
    function  ReadPageForPosition: Boolean;
    function  ReadPageBeforeWrite: Boolean;
    function  FreeOlderInUsePage(const aFreeBuffer: Boolean=false): PStreamCacheEntry;
    function  GetOpCounter: NativeUInt; inline;
    function  DoCacheRead(var Buffer; Count: Longint): Longint;
    function  DoCacheWrite(const Buffer; Count: Longint): Longint;
  protected
    function  GetPosition: Int64; override;
    procedure SetPosition(const Pos: Int64); override;
    function  GetSize: Int64; override;
    procedure SetSize64(const NewSize: Int64); override;
    procedure SetSize(NewSize: Longint); override;overload;
    procedure SetSize(const NewSize: Int64); override;overload;
  public
    // Warning using Mode=fmOpenWrite because the write buffer
    // needs to read, as this class is a cache system not a dumb buffer.
    constructor Create(const AFileName: string; Mode: Word);
    constructor Create(const AFileName: string; Mode: Word; Rights: Cardinal);
    destructor  Destroy; override;
    function  Seek(Offset: Longint; Origin: Word): Longint; override; overload;
    function  Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; override; overload;
    function  Read(var Buffer; Count: Longint): Longint; override;
    function  Write(const Buffer; Count: Longint): Longint; override;
    // Flush write-cache content to disk
    procedure Flush;
    // re-initialize the cache with aCacheBlockCount block
    // of aCacheBlockSize bytes in each block.
    procedure InitializeCache(const aCacheBlockSize: integer; const aCacheBlockCount: integer);
  end;


implementation

Resourcestring
  SErrCapacityTooSmall    = 'Capacity is less than actual buffer size.';
  SErrCouldNotFLushBuffer = 'Could not flush buffer';
  SErrInvalidSeek         = 'Invalid buffer seek operation';

  SErrCacheUnexpectedPageDiscard ='CACHE: Unexpected behaviour. Discarded page.';
  SErrCacheUnableToReadExpected = 'CACHE: Unable to read expected bytes (Open for write only ?). Expected: %d, effective read: %d';
  SErrCacheUnableToWriteExpected ='CACHE: Unable to write expected bytes (Open for read only ?). Expected: %d, effective write: %d';
  SErrCacheInternal = 'CACHE: Internal error.';

{ TBufStream }

procedure TBufStream.SetCapacity(const AValue: Integer);
begin
  if (FCapacity<>AValue) then
    begin
    If (AValue<FBufSize) then
      BufferError(SErrCapacityTooSmall);
    ReallocMem(FBuffer,AValue);
    FCapacity:=AValue;
    end;
end;

function TBufStream.GetPosition: Int64;
begin
  Result:=FTotalPos;
end;

function TBufStream.GetSize: Int64;
begin
  Result:=Source.Size;
end;

procedure TBufStream.BufferError(const Msg: String);
begin
  Raise EStreamError.Create(Msg);
end;

procedure TBufStream.FillBuffer;

Var
  RCount : Integer;
  P : PAnsiChar;

begin
  P:=PAnsiChar(FBuffer);
  // Reset at beginning if empty.
  If (FBufSize-FBufPos)<=0 then
   begin
   FBufSize:=0;
   FBufPos:=0;
   end;
  Inc(P,FBufSize);
  RCount:=1;
  while (RCount<>0) and (FBufSize<FCapacity) do
    begin
    RCount:=FSource.Read(P^,FCapacity-FBufSize);
    Inc(P,RCount);
    Inc(FBufSize,RCount);
    end;
end;

procedure TBufStream.FlushBuffer;

Var
  WCount : Integer;
  P : PAnsiChar;

begin
  P:=PAnsiChar(FBuffer);
  Inc(P,FBufPos);
  WCount:=1;
  While (WCount<>0) and ((FBufSize-FBufPos)>0) do
    begin
    WCount:=FSource.Write(P^,FBufSize-FBufPos);
    Inc(P,WCount);
    Inc(FBufPos,WCount);
    end;
  If ((FBufSize-FBufPos)<=0) then
    begin
    FBufPos:=0;
    FBufSize:=0;
    end
  else
    BufferError(SErrCouldNotFLushBuffer);
end;

constructor TBufStream.Create(ASource: TStream; ACapacity: Integer);
begin
  Inherited Create(ASource);
  SetCapacity(ACapacity);
end;

constructor TBufStream.Create(ASource: TStream);
begin
  Create(ASource,DefaultBufferCapacity*1024);
end;

destructor TBufStream.Destroy;
begin
  FBufSize:=0;
  SetCapacity(0);
  inherited Destroy;
end;

{ TReadBufStream }

function TReadBufStream.Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;

begin
  FakeSeekForward(Offset,Origin,FTotalPos);
  Result:=FTotalPos; // Pos updated by fake read
end;

function TReadBufStream.Read(var ABuffer; ACount: LongInt): Integer;

Var
  P,PB : PAnsiChar;
  Avail,MSize,RCount : Integer;

begin
  Result:=0;
  P:=PAnsiChar(@ABuffer);
  Avail:=1;
  While (Result<ACount) and (Avail>0) do
    begin
    If (FBufSize-FBufPos<=0) then
      FillBuffer;
    Avail:=FBufSize-FBufPos;
    If (Avail>0) then
      begin
      MSize:=ACount-Result;
      If (MSize>Avail) then
        MSize:=Avail;
      PB:=PAnsiChar(FBuffer);
      Inc(PB,FBufPos);
      Move(PB^,P^,MSIze);
      Inc(FBufPos,MSize);
      Inc(P,MSize);
      Inc(Result,MSize);
      end;
    end;
  Inc(FTotalPos,Result);
end;

{ TWriteBufStream }

destructor TWriteBufStream.Destroy;
begin
  FlushBuffer;
  inherited Destroy;
end;

function TWriteBufStream.Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;

begin
  if (Offset=0) and (Origin=soCurrent) then
    Result := FTotalPos
  else
    BufferError(SErrInvalidSeek);
end;

function TWriteBufStream.Write(const ABuffer; ACount: LongInt): Integer;

Var
  P,PB : PAnsiChar;
  Avail,MSize,RCount : Integer;

begin
  Result:=0;
  P:=PAnsiChar(@ABuffer);
  While (Result<ACount) do
    begin
    If (FBufSize=FCapacity) then
      FlushBuffer;
    Avail:=FCapacity-FBufSize;
    MSize:=ACount-Result;
    If (MSize>Avail) then
      MSize:=Avail;
    PB:=PAnsiChar(FBuffer);
    Inc(PB,FBufSize);
    Move(P^,PB^,MSIze);
    Inc(FBufSize,MSize);
    Inc(P,MSize);
    Inc(Result,MSize);
    end;
  Inc(FTotalPos,Result);
end;



{ ---------------------------------------------------------------------
  TBufferedFileStream
  ---------------------------------------------------------------------}

procedure TBufferedFileStream.ClearCache;
var
  j: integer;
  pStream: PStreamCacheEntry;
begin
  try
    WriteDirtyPages;
  finally
    for j := 0 to Pred(FStreamCachePageMaxCount) do begin
      pStream:=FCachePages[j];
      if Assigned(pStream) then begin
        if Assigned(pStream^.Buffer) then Freemem(pStream^.Buffer);
        Dispose(pStream);
        FCachePages[j]:=nil;
      end;
    end;
  end;
end;

procedure TBufferedFileStream.WriteDirtyPage(const aPage: PStreamCacheEntry);
var
  lEffectiveBytesWrite: integer;
begin
  inherited Seek(aPage^.PageBegin,soBeginning);
  lEffectiveBytesWrite:=inherited Write(aPage^.Buffer^,aPage^.PageRealSize);
  if lEffectiveBytesWrite<>aPage^.PageRealSize then begin
    EmergencyWriteDirtyPages;
    Raise EStreamError.CreateFmt(SErrCacheUnableToWriteExpected,[aPage^.PageRealSize,lEffectiveBytesWrite,IntToStr(aPage^.PageBegin)]);
  end;
  aPage^.IsDirty:=False;
  aPage^.LastTick:=GetOpCounter;
end;

procedure TBufferedFileStream.WriteDirtyPage(const aIndex: integer);
var
  pCache: PStreamCacheEntry;
begin
  pCache:=FCachePages[aIndex];
  if Assigned(pCache) then begin
    WriteDirtyPage(pCache);
  end;
end;

procedure TBufferedFileStream.WriteDirtyPages;
var
  j: integer;
  pCache: PStreamCacheEntry;
begin
  for j := 0 to Pred(FStreamCachePageMaxCount) do begin
    pCache:=FCachePages[j];
    if Assigned(pCache) then begin
      if pCache^.IsDirty then begin
        WriteDirtyPage(pCache);
      end;
    end;
  end;
end;

procedure TBufferedFileStream.EmergencyWriteDirtyPages;
var
  j: integer;
  pCache: PStreamCacheEntry;
begin
  // Are we already in a emergency write dirty pages ??
  if FEmergencyFlag then exit;
  FEmergencyFlag:=true;
  // This procedure tries to save all dirty pages unconditional
  // because a write fail happens, so everything in cache will
  // be dumped to stream if possible, trying to save as much
  // information as possible.
  for j := 0 to Pred(FStreamCachePageMaxCount) do begin
    pCache:=FCachePages[j];
    if Assigned(pCache) then begin
      if pCache^.IsDirty then begin
        try
          WriteDirtyPage(pCache);
        except on e: Exception do begin
          // Do nothing, eat exception if happen.
          // This way the cache still holds data to be
          // written (that fails) and can be written later
          // if write fail conditions change.
          end;
        end;
      end;
    end;
  end;
  FEmergencyFlag:=False;
end;

procedure TBufferedFileStream.FreePage(const aPage: PStreamCacheEntry;
  const aFreeBuffer: Boolean);
begin
  aPage^.PageBegin:=0;
  aPage^.PageRealSize:=0;
  aPage^.LastTick:=0;
  aPage^.IsDirty:=false;
  if aFreeBuffer then begin
    FreeMem(aPage^.Buffer);
    aPage^.Buffer:=nil;
  end;
end;

{ The bytes of a slot behind the page's data are the file's zeros: the page
  was filled from the file when it was created, and everything written into
  the slot since went through this page.  So while the logical size reaches
  behind the data, the page may grow with zeros up to that size or the slot
  end, whichever comes first.  Not marked dirty: the OS makes those bytes
  zero itself when the file grows past them. }
procedure TBufferedFileStream.ExtendPageWithZeros(const aPage: PStreamCacheEntry);
var
  lNewSize: int64;
begin
  lNewSize:=FCacheStreamSize-aPage^.PageBegin;
  if lNewSize>FStreamCachePageSize then
    lNewSize:=FStreamCachePageSize;
  if lNewSize>aPage^.PageRealSize then begin
    FillByte((PBYTE(aPage^.Buffer)+aPage^.PageRealSize)^,lNewSize-aPage^.PageRealSize,0);
    aPage^.PageRealSize:=lNewSize;
  end;
end;

{ Pages are aligned slots of FStreamCachePageSize bytes, so a position belongs
  to the page whose slot contains it, whether or not the page already holds
  data that far: matching on PageRealSize instead created a second page for
  the same slot as soon as a write landed behind the data of the first one
  (write frame, seek back to patch its header, seek to the frame end, write
  the next frame), and the two pages then overwrote each other on flush. }
function TBufferedFileStream.LookForPositionInPages: Boolean;
var
  j: integer;
  pCache: PStreamCacheEntry;
begin
  Result:=false;
  for j := 0 to Pred(FStreamCachePageMaxCount) do begin
    pCache:=FCachePages[j];
    if Assigned(pCache^.Buffer) then begin
      if (FCacheStreamPosition>=pCache^.PageBegin) and (FCacheStreamPosition<pCache^.PageBegin+FStreamCachePageSize) then begin
        FCacheLastUsedPage:=j;
        Result:=true;
        exit;
      end;
    end;
  end;
end;

function TBufferedFileStream.ReadPageForPosition: Boolean;
var
  j: integer;
  pCache: PStreamCacheEntry=nil;
  lStreamPosition: int64;
begin
  // Find free page entry
  for j := 0 to Pred(FStreamCachePageMaxCount) do begin
    if not Assigned(FCachePages[j]^.Buffer) then begin
      pCache:=FCachePages[j];
      FCacheLastUsedPage:=j;
      break;
    end;
  end;
  if not Assigned(pCache) then begin
    // Free last used page
    pCache:=FreeOlderInUsePage(false);
  end;
  if not Assigned(pCache^.Buffer) then begin
    Getmem(pCache^.Buffer,FStreamCachePageSize);
  end;
  lStreamPosition:=(FCacheStreamPosition div FStreamCachePageSize)*FStreamCachePageSize;
  inherited Seek(lStreamPosition,soBeginning);
  pCache^.PageBegin:=lStreamPosition;
  pCache^.PageRealSize:=inherited Read(pCache^.Buffer^,FStreamCachePageSize);
  if pCache^.PageRealSize=FStreamCachePageSize then begin
    pCache^.LastTick:=GetOpCounter;
    Result:=true;
  end else begin
    { data written further on but not yet flushed leaves a hole here }
    ExtendPageWithZeros(pCache);
    if FCacheStreamPosition<lStreamPosition+pCache^.PageRealSize then begin
      pCache^.LastTick:=GetOpCounter;
      Result:=true;
    end else begin
      Result:=false;
    end;
  end;
end;

function TBufferedFileStream.ReadPageBeforeWrite: Boolean;
var
  j: integer;
  pCache: PStreamCacheEntry=nil;
  lStreamPosition: int64;
begin
  // Find free page entry
  for j := 0 to Pred(FStreamCachePageMaxCount) do begin
    if not Assigned(FCachePages[j]^.Buffer) then begin
      pCache:=FCachePages[j];
      FCacheLastUsedPage:=j;
      break;
    end;
  end;
  if not Assigned(pCache) then begin
    // Free last used page
    pCache:=FreeOlderInUsePage(false);
  end;
  if not Assigned(pCache^.Buffer) then begin
    Getmem(pCache^.Buffer,FStreamCachePageSize);
  end;
  lStreamPosition:=(FCacheStreamPosition div FStreamCachePageSize)*FStreamCachePageSize;
  inherited Seek(lStreamPosition,soBeginning);
  pCache^.PageBegin:=lStreamPosition;
  pCache^.PageRealSize:=inherited Read(pCache^.Buffer^,FStreamCachePageSize);
  pCache^.LastTick:=GetOpCounter;
  Result:=true;
end;

function TBufferedFileStream.FreeOlderInUsePage(const aFreeBuffer: Boolean
  ): PStreamCacheEntry;
var
  j: integer;
  lOlderTick: int64=High(int64);
  lOlderEntry: integer=-1;
begin
  for j := 0 to Pred(FStreamCachePageMaxCount) do begin
    Result:=FCachePages[j];
    if Assigned(Result^.Buffer) then begin
      if Result^.LastTick<lOlderTick then begin
        lOlderTick:=Result^.LastTick;
        lOlderEntry:=j;
      end;
    end;
  end;
  if lOlderEntry=-1 then begin
    Raise Exception.Create(SErrCacheInternal);
  end;
  Result:=FCachePages[lOlderEntry];
  FCacheLastUsedPage:=lOlderEntry;
  if Result^.IsDirty then begin
    WriteDirtyPage(Result);
  end;
  FreePage(Result,aFreeBuffer);
end;

function TBufferedFileStream.GetOpCounter: NativeUInt;
begin
  Result:=FOpCounter;
  {$PUSH}
  {$Q-}
  inc(FOpCounter);
  {$POP}
end;

function TBufferedFileStream.DoCacheRead(var Buffer; Count: Longint): Longint;
var
  pCache: PStreamCacheEntry;
  lAvailableInThisPage: integer;
  lPositionInPage: integer;
  lNewBuffer: PBYTE;
begin
  pCache:=FCachePages[FCacheLastUsedPage];
  if Assigned(pCache) then begin
    // Check if FCacheStreamPosition is in range
    if Assigned(pCache^.Buffer) then begin
      if (FCacheStreamPosition>=pCache^.PageBegin) and (FCacheStreamPosition<pCache^.PageBegin+pCache^.PageRealSize) then begin
        // Position is in range, so read available data from this page up to count or page end
        lPositionInPage:=(FCacheStreamPosition-pCache^.PageBegin);
        lAvailableInThisPage:=pCache^.PageRealSize - lPositionInPage;
        if lAvailableInThisPage>=Count then begin
          move((PBYTE(pCache^.Buffer)+lPositionInPage)^,Buffer,Count);
          inc(FCacheStreamPosition,Count);
          Result:=Count;
          pCache^.LastTick:=GetOpCounter;
          exit;
        end else begin
          move((PBYTE(pCache^.Buffer)+lPositionInPage)^,Buffer,lAvailableInThisPage);
          inc(FCacheStreamPosition,lAvailableInThisPage);
          pCache^.LastTick:=GetOpCounter;
          // The rest: the next slot, the file's zeros behind this page's
          // data while the logical size reaches there, or nothing at the end
          // of the file - the recursive call decides, it returns 0 at the end.
          lNewBuffer:=PBYTE(@Buffer)+lAvailableInThisPage;
          Result:=lAvailableInThisPage+DoCacheRead(lNewBuffer^,Count-lAvailableInThisPage);
          exit;
        end;
      end else if (FCacheStreamPosition>=pCache^.PageBegin) and (FCacheStreamPosition<pCache^.PageBegin+FStreamCachePageSize) then begin
        // Inside this page's slot but behind its data: the file's zeros up to
        // the logical size, nothing beyond it.
        ExtendPageWithZeros(pCache);
        if FCacheStreamPosition<pCache^.PageBegin+pCache^.PageRealSize then
          Result:=DoCacheRead(Buffer,Count)
        else
          Result:=0;
        exit;
      end else begin
        // The position is in other cache page or not in cache at all, so look for
        // position in cached pages or allocate a new page.
        if LookForPositionInPages then begin
          Result:=DoCacheRead(Buffer,Count);
          exit;
        end else begin
          if ReadPageForPosition then begin
            Result:=DoCacheRead(Buffer,Count);
          end else begin
            Result:=0;
          end;
          exit;
        end;
      end;
    end else begin
      if ReadPageForPosition then begin
        Result:=DoCacheRead(Buffer,Count);
      end else begin
        Result:=0;
      end;
      exit;
    end;
  end else begin
    // The page has been discarded for some unknown reason
    Raise EStreamError.Create(SErrCacheUnexpectedPageDiscard);
  end;
end;

function TBufferedFileStream.DoCacheWrite(const Buffer; Count: Longint): Longint;
var
  pCache: PStreamCacheEntry;
  lAvailableInThisPage: integer;
  lPositionInPage: integer;
  lNewBuffer: PBYTE;
begin
  pCache:=FCachePages[FCacheLastUsedPage];
  if Assigned(pCache) then begin
    // Check if FCacheStreamPosition is in range
    if Assigned(pCache^.Buffer) then begin
      if (FCacheStreamPosition>=pCache^.PageBegin) and (FCacheStreamPosition<pCache^.PageBegin+FStreamCachePageSize) then begin
        // Position is in range, so write data up to end of page
        lPositionInPage:=(FCacheStreamPosition-pCache^.PageBegin);
        lAvailableInThisPage:=FStreamCachePageSize - lPositionInPage;
        // Bytes between the page's data and this write are the file's zeros,
        // not whatever the buffer held before.
        if lPositionInPage>pCache^.PageRealSize then
          FillByte((PBYTE(pCache^.Buffer)+pCache^.PageRealSize)^,lPositionInPage-pCache^.PageRealSize,0);
        if lAvailableInThisPage>=Count then begin
          move(Buffer,(PBYTE(pCache^.Buffer)+lPositionInPage)^,Count);
          if not pCache^.IsDirty then pCache^.IsDirty:=true;
          inc(FCacheStreamPosition,Count);
          // Update page size
          if lPositionInPage+Count > pCache^.PageRealSize then pCache^.PageRealSize:=lPositionInPage+Count;
          // Update file size
          if FCacheStreamPosition>FCacheStreamSize then FCacheStreamSize:=FCacheStreamPosition;
          Result:=Count;
          pCache^.LastTick:=GetOpCounter;
          exit;
        end else begin
          move(Buffer,(PBYTE(pCache^.Buffer)+lPositionInPage)^,lAvailableInThisPage);
          if not pCache^.IsDirty then pCache^.IsDirty:=true;
          inc(FCacheStreamPosition,lAvailableInThisPage);
          // Update page size
          if lPositionInPage+Count > pCache^.PageRealSize then pCache^.PageRealSize:=lPositionInPage+lAvailableInThisPage;
          // Update file size
          if FCacheStreamPosition>FCacheStreamSize then FCacheStreamSize:=FCacheStreamPosition;

          Assert(pCache^.PageRealSize=FStreamCachePageSize,'This must not happened');
          lNewBuffer:=PBYTE(@Buffer)+lAvailableInThisPage;
          Result:=lAvailableInThisPage+DoCacheWrite(lNewBuffer^,Count-lAvailableInThisPage);
          exit;
        end;
      end else begin
        // The position is in other cache page or not in cache at all, so look for
        // position in cached pages or allocate a new page.
        if LookForPositionInPages then begin
          Result:=DoCacheWrite(Buffer,Count);
          exit;
        end else begin
          if ReadPageBeforeWrite then begin
            Result:=DoCacheWrite(Buffer,Count);
          end else begin
            Result:=0;
          end;
          exit;
        end;
      end;
    end else begin
      if ReadPageBeforeWrite then begin
        Result:=DoCacheWrite(Buffer,Count);
      end else begin
        Result:=0;
      end;
      exit;
    end;
  end else begin
    // The page has been discarded for some unknown reason
    Raise EStreamError.Create(SErrCacheUnexpectedPageDiscard);
  end;
end;

function TBufferedFileStream.GetPosition: Int64;
begin
  Result:=FCacheStreamPosition;
end;

procedure TBufferedFileStream.SetPosition(const Pos: Int64);
begin
  if Pos<0 then begin
    FCacheStreamPosition:=0;
  end else begin
    FCacheStreamPosition:=Pos;
  end;
end;

function TBufferedFileStream.GetSize: Int64;
begin
  Result:=FCacheStreamSize;
end;

procedure TBufferedFileStream.SetSize64(const NewSize: Int64);
var
  j: integer;
  pCache: PStreamCacheEntry;
begin
  WriteDirtyPages;
  inherited SetSize(NewSize); // Call THandleStream.SetSize, will truncate
  FCacheStreamSize:=inherited Seek(int64(0),soEnd);
  for j := 0 to Pred(FStreamCachePageMaxCount) do begin
    pCache:=FCachePages[j];
    if Assigned(pCache^.Buffer) and (pCache^.PageRealSize+pCache^.PageBegin>FCacheStreamSize) then begin
      // This page is out of bounds the new file size
      // so discard it.
      FreePage(pCache,True);
    end;
  end;
end;

procedure TBufferedFileStream.SetSize(NewSize: Longint);
begin
  SetSize64(NewSize);
end;

procedure TBufferedFileStream.SetSize(const NewSize: Int64);
begin
  SetSize64(NewSize);
end;

constructor TBufferedFileStream.Create(const AFileName: string; Mode: Word);
begin
  // Initialize with 8 blocks of 4096 bytes
  InitializeCache(TSTREAMCACHEPAGE_SIZE_DEFAULT,TSTREAMCACHEPAGE_MAXCOUNT_DEFAULT);
  inherited Create(AFileName,Mode);
  FCacheStreamSize:=inherited Seek(int64(0),soEnd);
end;

constructor TBufferedFileStream.Create(const AFileName: string; Mode: Word;
  Rights: Cardinal);
begin
  // Initialize with 8 blocks of 4096 bytes
  InitializeCache(TSTREAMCACHEPAGE_SIZE_DEFAULT,TSTREAMCACHEPAGE_MAXCOUNT_DEFAULT);
  inherited Create(AFileName,Mode,Rights);
  FCacheStreamSize:=inherited Seek(int64(0),soEnd);
end;

function TBufferedFileStream.Read(var Buffer; Count: Longint): Longint;
begin
  Result:=DoCacheRead(Buffer,Count);
end;

function TBufferedFileStream.Write(const Buffer; Count: Longint): Longint;
begin
  Result:=DoCacheWrite(Buffer,Count);
end;

procedure TBufferedFileStream.Flush;
begin
  WriteDirtyPages;
end;

function TBufferedFileStream.Seek(Offset: Longint; Origin: Word): Longint;
begin
  Result:=Seek(int64(OffSet),TSeekOrigin(Origin));
end;

function TBufferedFileStream.Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;
var
  lNewOffset: int64;
begin
  Case Origin of
    soEnd:
      begin
        lNewOffset:=FCacheStreamSize+Offset;
      end;
    soBeginning:
      begin
        lNewOffset:=0+Offset;
      end;
    soCurrent:
      begin
        lNewOffset:=FCacheStreamPosition+Offset;
      end;
  end;
  if lNewOffset>=0 then begin
    FCacheStreamPosition:=lNewOffset;
    Result:=lNewOffset;
  end else begin
    // This is compatible with FPC stream
    // as it returns the negative value :-?
    // but in fact does not move the read pointer.
    Result:=-1;
  end;
end;

procedure TBufferedFileStream.InitializeCache(const aCacheBlockSize: integer;
  const aCacheBlockCount: integer);
var
  j: integer;
begin
  ClearCache;
  FStreamCachePageSize:=aCacheBlockSize;
  FStreamCachePageMaxCount:=aCacheBlockCount;
  FCacheStreamSize:=inherited Seek(0,soEnd);
  SetLength(FCachePages,FStreamCachePageMaxCount);
  for j := 0 to Pred(FStreamCachePageMaxCount) do begin
    FCachePages[j]:=New(PStreamCacheEntry);
    FillByte(FCachePages[j]^,Sizeof(PStreamCacheEntry^),0);
  end;
end;

destructor TBufferedFileStream.Destroy;
begin
  ClearCache;
  inherited Destroy;
end;

end.
