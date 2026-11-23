program weak_interface_resize_semantic;
{$mode delphiunicode}

uses SysUtils;

type
  TRow = record
    [Weak] Link: IInterface;
    Id: NativeInt;
    class operator Finalize(var Value: TRow);
  end;
  TRows = array of TRow;

var
  Original, Probe: TMemoryManager;
  WatchedAllocation: Pointer;
  RejectSize: PtrUInt;
  ReturnNil, RejectZeroed: Boolean;
  Finalized, Resizes: Integer;

class operator TRow.Finalize(var Value: TRow);
begin
  Inc(Finalized);
end;

function Allocate(Size: PtrUInt): Pointer;
begin
  if (RejectSize <> 0) and (Size = RejectSize) then begin
    RejectSize := 0;
    if ReturnNil then Exit(nil);
    OutOfMemoryError;
  end;
  Result := Original.GetMem(Size);
end;

function Resize(var P: Pointer; Size: PtrUInt): Pointer;
begin
  if P = WatchedAllocation then Inc(Resizes);
  Result := Original.ReAllocMem(P, Size);
end;

function AllocateZeroed(Size: PtrUInt): Pointer;
begin
  if RejectZeroed then begin
    RejectZeroed := False;
    Exit(nil);
  end;
  Result := Original.AllocMem(Size);
end;

procedure Check(OK: Boolean; const Where: string);
begin
  if not OK then raise Exception.Create(Where);
end;

procedure CheckFailedShrink(UseDelete, Shared, RegisterSlots, NilFailure: Boolean);
var
  Rows, AliasRows: TRows;
  Owner: IInterface;
  Backing: Pointer;
  I, Before: Integer;
  Failed: Boolean;
begin
  SetLength(Rows, 3);
  Owner := TInterfacedObject.Create;
  for I := 0 to High(Rows) do begin
    Rows[I].Id := I + 1;
    if RegisterSlots then Rows[I].Link := Owner;
  end;
  if Shared then AliasRows := Rows;
  Backing := Pointer(Rows);
  Before := Finalized;
  Failed := False;
  ReturnNil := NilFailure;
  RejectSize := 2 * SizeOf(Pointer) + 2 * SizeOf(TRow);
  SetMemoryManager(Probe);
  try
    try
      if UseDelete then Delete(Rows, 0, 1) else SetLength(Rows, 2);
    except
      on E: EOutOfMemory do Failed := True;
    end;
  finally
    SetMemoryManager(Original);
    RejectSize := 0;
  end;
  Check(Failed and (Length(Rows) = 3) and (Pointer(Rows) = Backing), 'failed shrink changed the array');
  if not Shared then Check(Finalized = Before, 'premature finalization');
  for I := 0 to High(Rows) do begin
    Check(Rows[I].Id = I + 1, 'failed shrink moved an element');
    if RegisterSlots then Check(Pointer(Rows[I].Link) = Pointer(Owner), 'failed shrink lost an owner');
  end;
  if UseDelete then Delete(Rows, 0, 1) else SetLength(Rows, 2);
  Check((Length(Rows) = 2) and (Rows[0].Id = 1 + Ord(UseDelete)) and
    (Rows[1].Id = 2 + Ord(UseDelete)), 'retry lost survivors');
  if Shared then Check((Length(AliasRows) = 3) and (AliasRows[0].Id = 1), 'alias changed');
  Owner := nil;
  for I := 0 to High(Rows) do Check(Pointer(Rows[I].Link) = nil, 'surviving weak slot');
  for I := 0 to High(AliasRows) do Check(Pointer(AliasRows[I].Link) = nil, 'alias weak slot');
  Before := Finalized;
  Rows := nil;
  AliasRows := nil;
  Check(Finalized - Before = 2 + 3 * Ord(Shared), 'finalizer count after retry');
end;

procedure CheckUnregisteredGrowth;
var
  Rows: TRows;
begin
  SetLength(Rows, 3);
  Rows[0].Id := 41;
  WatchedAllocation := Pointer(Rows) - 2 * SizeOf(Pointer);
  SetMemoryManager(Probe);
  try
    SetLength(Rows, 3);
    Check(Resizes = 0, 'same length reallocated');
    SetLength(Rows, 8);
  finally
    SetMemoryManager(Original);
    WatchedAllocation := nil;
  end;
  Check((Resizes = 1) and (Rows[0].Id = 41), 'unregistered growth bypassed realloc');
end;

procedure CheckFirstRegistration;
var
  Row: TRow;
  Owner: IInterface;
  Failed: Boolean;
begin
  Owner := TInterfacedObject.Create;
  Failed := False;
  RejectZeroed := True;
  SetMemoryManager(Probe);
  try
    try
      Row.Link := Owner;
    except
      on E: EOutOfMemory do Failed := True;
    end;
  finally
    SetMemoryManager(Original);
    RejectZeroed := False;
  end;
  Check(Failed and (Pointer(Row.Link) = nil), 'first registration failed to roll back');
  Row.Link := Owner;
  Check(Pointer(Row.Link) = Pointer(Owner), 'registration retry');
  Owner := nil;
  Check(Pointer(Row.Link) = nil, 'registered target survived its owner');
end;

var
  UseDelete, Shared, Registered, NilFailure: Boolean;
begin
  GetMemoryManager(Original);
  Probe := Original;
  Probe.GetMem := @Allocate;
  Probe.ReAllocMem := @Resize;
  Probe.AllocMem := @AllocateZeroed;
  CheckUnregisteredGrowth;
  CheckFirstRegistration;
  for UseDelete := False to True do
    for Shared := False to True do
      for Registered := False to True do
        for NilFailure := False to True do
          CheckFailedShrink(UseDelete, Shared, Registered, NilFailure);
  WriteLn('WEAK_INTERFACE_RESIZE_PASS');
end.
