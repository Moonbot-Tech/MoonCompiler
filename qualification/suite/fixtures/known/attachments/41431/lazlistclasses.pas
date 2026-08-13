unit LazListClasses;

{$mode objfpc}{$H+}
{$WARN 3124 off : Inlining disabled}
interface
  {$INLINE on}
  {$Optimization noAUTOINLINE}
  {$Optimization noREMOVEEMPTYPROCS}
  {$Optimization noDFA}
  (* DEADSTORE, DEADVALUES: important when calls to empty procs are removed *)
  {$Optimization noDEADSTORE} // needs DFA
  {$Optimization noDEADVALUES}
  {$Optimization noCONSTPROP}
  {$Optimization noCSE}
  // needs speed eval
  { $Optimization USELOADMODIFYSTORE}

  {$Optimization noREGVAR}
  {$Optimization noPEEPHOLE}
  { $Optimization STACKFRAME}
{$IMPLICITEXCEPTIONS off}

{$IFDEF ni}{$INLINE off}{$ENDIF}

uses
  Classes, SysUtils, math;

type

  TLazStorageMemShrinkProc = function(ARequired: Integer): Integer of object;
  TLazStorageMemGrowProc = function(ARequired: Integer): Integer of object;

  (* TLazListClassesItemSize
     Helper to specialize lists for a give type
  *)
  generic TLazListClassesItemSize<T> = object
  protected
    const
    ItemSize = SizeOf(T);
  end;

  (* TLazListClassesVarItemSize
     Helper to specialize lists for runtime specified size "TList.Create(ASize)"
  *)
  TLazListClassesVarItemSize = object
  public
    ItemSize: Integer;
  end;

  { TLazListClassesMemInitNone }

  TLazListClassesMemInitNone = object
  public
    class procedure Init(); inline; static;

    (* InitMem: First init
       - for InsertRows
       - for emptied Source area of move (old data is NOT finalized, since it moved)
    *)
    class procedure InitMem(AMem: Pointer; AnItemCount, AnItemSize: Integer); inline; static;

    (* FinalizeMem: (e.g. decrease ref count)
       - Before DeleteRows
       - Before Move for Target area, finalize old data.
       - NOT in Item[x] := / "Item[x]" uses a typed assignment of the data
       - No need to actually init/clean the underlaying memory
    *)
    class procedure FinalizeMem(AMem: Pointer; AnItemCount, AnItemSize: Integer); inline; static;

    // TODO: Maybe add...
    (* AcceptData: (e.g. increase ref count)
       - In Item[x] := // Not in ItemPointer[x]
       - No need to actually init/clean the underlaying memory
    *)
    (* ReleaseData: (e.g. decrease ref count)
       - In Item[x] := // Not in ItemPointer[x]
       - No need to actually init/clean the underlaying memory
    *)
  end;

  { TLazListClassesMemInitZero }

  TLazListClassesMemInitZero = object(TLazListClassesMemInitNone)
  public
    class procedure InitMem(AMem: Pointer; AnItemCount, AnItemSize: Integer); inline; static;
    class procedure FinalizeMem(AMem: Pointer; AnItemCount, AnItemSize: Integer); inline; static;
  end;

  { TLazListClassesMemInitManagedRefCnt }

  generic TLazListClassesMemInitManagedRefCnt<TItemT> = object(TLazListClassesMemInitNone)
  private type
    PItemT = ^TItemT;
  public
    class procedure InitMem(AMem: Pointer; AnItemCount, AnItemSize: Integer); inline; static;
    class procedure FinalizeMem(AMem: Pointer; AnItemCount, AnItemSize: Integer); inline; static;
  end;

  { TLazListClassesCapacityFixed }

  TLazListClassesCapacityFixed = object
  public
    class procedure Init(); inline; static;
    class function GrowCapacity(ARequired, ACurrent: Integer): Integer; inline; static;
    class function ShrinkCapacity({%H-}ARequired, ACurrent: Integer): Integer; inline; static;
  end;

  { TLazListClassesCapacityExp0x8000 }

  TLazListClassesCapacityExp0x8000 = object(TLazListClassesCapacityFixed)
  public
    class function GrowCapacity(ARequired, ACurrent: Integer): Integer; inline; static;
    class function ShrinkCapacity({%H-}ARequired, ACurrent: Integer): Integer; inline; static;
  end;

  { TGenLazListClassesCapacityCallback }

  generic TGenLazListClassesCapacityCallback<TFALLBACK> = object(TLazListClassesCapacityFixed)
  public
    FGrowProc: TLazStorageMemGrowProc;
    FShrinkProc: TLazStorageMemShrinkProc;
    FFallBack: TFALLBACK;
    procedure Init(); inline;
    function GrowCapacity(ARequired, ACurrent: Integer): Integer; inline;
    function ShrinkCapacity({%H-}ARequired, ACurrent: Integer): Integer; inline;
  end;

  TLazListClassesCapacityCallback = specialize TGenLazListClassesCapacityCallback<TLazListClassesCapacityFixed>;

  { TTypeToPointerGeneric
    Inline pointer type for specializing base classes
  }
  generic TTypeToPointerGeneric<T> = class public type PT = ^T; end;

  { TLazListClassesInternalMem
    Internally used helper object
  }

  TLazListClassesInternalMem = object
  protected type
    TMemRecord = record
      FirstItem: record
        case integer of
          1: (Ptr: PByte;);
          2: (Idx: Integer;);
        end;
      Count: Integer;
      Capacity: Cardinal;
      Data: byte; // Dummy byte: The address for the first byte of data. This is a dummy field (pbyte for pointer math)
    end;
    PMemRecord = ^TMemRecord;
  private
    FMem: PMemRecord;

    procedure SetCapacity(AValue: Cardinal); inline;
    function GetCapacity: Cardinal; inline;
    function GetCount: Integer; inline;
    procedure SetCount(AValue: Integer); inline;
  public
    procedure Init; inline;
    procedure Alloc(AByteSize: Integer); inline;
    procedure Free; inline;
    function IsAllocated: Boolean; inline;

    property Capacity: Cardinal read GetCapacity write SetCapacity;
    property Count: Integer read GetCount write SetCount;
  end;

  (*                              *
   * TLazRoundList variants *
   *                              *)

  { TGenLazRoundList }

  generic TGenLazRoundList<TPItemT, TSizeT, TInitMemT, TCapacityT> = object
  private
    // Keep the size small, if no entries exist
    // FMem:  FLowElemPointer: PByte; FCount, FCapacity_in_bytes: Integer; Array of <FItemSize
    FMem: TLazListClassesInternalMem;

    function GetDataPointerFast: TPItemT; inline;
    function GetItemPointer(Index: Integer): TPItemT; inline;
    function GetItemPointerFast(Index: Integer): TPItemT; inline;
    procedure SetCapacity(AValue: Integer); inline;
    function GetCapacity: Integer; inline;
    function GetCount: Integer; inline;

    function IndexOf(AnItem: TPItemT; AFirstIdx: integer): integer; inline; overload;
  protected
    FItemSize: TSizeT; // May be zero size
    FCapacity: TCapacityT; // For access by subclasses, if it contains fields
    FInitMem:  TInitMemT;  // For access by subclasses, if it contains fields

    procedure InternalMoveUp(AFromEnd, AToEnd: PByte; AByteCnt, AByteCap: Integer); inline;
    procedure InternalMoveDown(AFrom, ATo: PByte; AByteCnt: Integer; AUpperBound: PByte); inline;
    procedure MoveRowsUp(AFromIndex, AToIndex, ACount: Integer);
    procedure MoveRowsDown(AFromIndex, AToIndex, ACount: Integer);

    function  SetCapacityEx(AValue, AnInsertPos, AnInsertSize: Integer): TPItemT;
    property ItemPointerFast[Index: Integer]: TPItemT read GetItemPointerFast;
  public
    procedure Create;
    procedure Destroy;
    function  InsertRows(AIndex, ACount: Integer): TPItemT; inline;
    procedure DeleteRows(AIndex, ACount: Integer); inline;
// TODO: for pAGED: split Moverows into MoveRowUp / MoveRowsDown => internalMove... mostly knows the direction ahead
    procedure MoveRows(AFromIndex, AToIndex, ACount: Integer);
    procedure SwapEntries(AIndex1, AIndex2: Integer); inline;
    procedure DebugDump;
    function IndexOf(AnItem: TPItemT): integer;

    property Capacity: Integer read GetCapacity write SetCapacity;
    property Count: Integer read GetCount;
    property ItemPointer[Index: Integer]: TPItemT read GetItemPointer;
  end;

  { TGenLazRoundListVarSize }

  generic TGenLazRoundListVarSize<TPItemT, TInitMemT, TCapacityT> = object(
    specialize TGenLazRoundList<TPItemT, TLazListClassesVarItemSize, TInitMemT, TCapacityT>
  )
  public
    procedure Create(AnItemSize: Integer);
  end;

  generic TLazRoundBufferListObjBase<TPItemT, TSizeT> = object(
    specialize TGenLazRoundList<TPItemT, TSizeT, TLazListClassesMemInitNone, TLazListClassesCapacityExp0x8000>
  )
  end deprecated;

  TLazRoundBufferListObj = object(specialize TGenLazRoundListVarSize<Pointer, TLazListClassesMemInitNone, TLazListClassesCapacityExp0x8000>)
  end;


  { TGenLazRoundListFixedSize }

  generic TGenLazRoundListFixedSize<T, TInitMemT, TCapacityT> =
    object(specialize TGenLazRoundList<specialize TTypeToPointerGeneric<T>.PT,
                                       specialize TLazListClassesItemSize<T>,
                                       TInitMemT, TCapacityT>
  )
  end;

  generic TGenLazRoundListFixedType<T, TInitMemT, TCapacityT> = object(specialize TGenLazRoundListFixedSize<T, TInitMemT, TCapacityT>)
  private type
    PT = ^T;
  private
    function Get(Index: Integer): T;
    procedure Put(Index: Integer; AValue: T);
  public
    function IndexOf(AnItem: T): integer; overload;
    property Items[Index: Integer]: T read Get write Put; default;
  end;

  generic TLazRoundBufferListObjGen<T> = object(specialize TGenLazRoundListFixedType<T, TLazListClassesMemInitNone, TLazListClassesCapacityExp0x8000>)
  end;


implementation

{ TLazListClassesMemInitNone }

class procedure TLazListClassesMemInitNone.Init();
begin
  // nothing
end;

class procedure TLazListClassesMemInitNone.InitMem(AMem: Pointer; AnItemCount, AnItemSize: Integer
  );
begin
  // Nothing
end;

class procedure TLazListClassesMemInitNone.FinalizeMem(AMem: Pointer; AnItemCount,
  AnItemSize: Integer);
begin
  // Nothing
end;

{ TLazListClassesMemInitZero }

class procedure TLazListClassesMemInitZero.InitMem(AMem: Pointer; AnItemCount, AnItemSize: Integer
  );
begin
  FillChar(AMem^, AnItemCount * AnItemSize, 0);
end;

class procedure TLazListClassesMemInitZero.FinalizeMem(AMem: Pointer; AnItemCount,
  AnItemSize: Integer);
begin
  // Nothing
end;

{ TLazListClassesMemInitManagedRefCnt }

class procedure TLazListClassesMemInitManagedRefCnt.InitMem(AMem: Pointer; AnItemCount,
  AnItemSize: Integer);
begin
  FillChar(AMem^, AnItemCount * AnItemSize, 0);
end;

class procedure TLazListClassesMemInitManagedRefCnt.FinalizeMem(AMem: Pointer; AnItemCount,
  AnItemSize: Integer);
var
  i: Integer;
begin
  for i := 0 to AnItemCount-1 do begin
    PItemT(AMem)^ := Default(TItemT);
    inc(AMem, AnItemSize);
  end;
end;

{ TLazListClassesCapacityFixed }

class procedure TLazListClassesCapacityFixed.Init();
begin
  // nothing
end;

class function TLazListClassesCapacityFixed.GrowCapacity(ARequired, ACurrent: Integer): Integer;
begin
  assert(False, 'TLazListClassesCapacityFixed.GrowCapacity: False');
  Result := ARequired;
end;

class function TLazListClassesCapacityFixed.ShrinkCapacity(ARequired, ACurrent: Integer): Integer;
begin
  assert(False, 'TLazListClassesCapacityFixed.ShrinkCapacity: False');
  Result := ARequired;
end;

{ TLazListClassesCapacityExp0x8000 }

class function TLazListClassesCapacityExp0x8000.GrowCapacity(ARequired, ACurrent: Integer
  ): Integer;
begin
  Result := Min(ARequired * 2, ARequired + $8000);
end;

class function TLazListClassesCapacityExp0x8000.ShrinkCapacity(ARequired, ACurrent: Integer
  ): Integer;
begin
  assert(ARequired <= ACurrent, 'TLazListClassesCapacityExp0x8000.ShrinkCapacity: ARequired <= ACurrent');
  if ARequired * 4 < ACurrent then
    Result := ARequired * 2
  else
    Result := -1;
end;

{ TGenLazListClassesCapacityCallback }

procedure TGenLazListClassesCapacityCallback.Init();
begin
  FGrowProc := nil;
  FShrinkProc := nil;
  FFallBack.Init;
end;

function TGenLazListClassesCapacityCallback.GrowCapacity(ARequired, ACurrent: Integer): Integer;
begin
  if FGrowProc <> nil then
    Result := FGrowProc(ARequired)
  else
    Result := FFallBack.GrowCapacity(ARequired, ACurrent);
end;

function TGenLazListClassesCapacityCallback.ShrinkCapacity(ARequired, ACurrent: Integer
  ): Integer;
begin
  if FShrinkProc <> nil then
    Result := FShrinkProc(ARequired)
  else
    Result := FFallBack.ShrinkCapacity(ARequired, ACurrent);
end;

{ TLazListClassesInternalMem }

procedure TLazListClassesInternalMem.SetCapacity(AValue: Cardinal);
begin
  assert(FMem <> nil, 'TLazListClassesInternalMem.SetCapacity: FMem <> nil');
  FMem^.Capacity := AValue;
end;

function TLazListClassesInternalMem.GetCapacity: Cardinal;
begin
  if FMem = nil
  then Result := 0
  else Result := FMem^.Capacity;
end;

function TLazListClassesInternalMem.GetCount: Integer;
begin
  if FMem = nil
  then Result := 0
  else Result := FMem^.Count;
end;

procedure TLazListClassesInternalMem.SetCount(AValue: Integer);
begin
  assert(FMem <> nil, 'TLazListClassesInternalMem.SetCount: FMem <> nil');
  FMem^.Count := AValue;
end;

procedure TLazListClassesInternalMem.Init;
begin
  FMem := nil;
end;

procedure TLazListClassesInternalMem.Alloc(AByteSize: Integer);
begin
  Free;
  FMem := Getmem(SizeOf(TMemRecord) + AByteSize);
end;

procedure TLazListClassesInternalMem.Free;
begin
  if FMem <> nil then
    Freemem(FMem);
  FMem := nil;
end;

function TLazListClassesInternalMem.IsAllocated: Boolean;
begin
  Result := FMem <> nil;
end;


{ TGenLazRoundList }

function TGenLazRoundList.GetDataPointerFast: TPItemT;
begin
  Result := TPItemT(@FMem.FMem^.Data);
end;

function TGenLazRoundList.GetItemPointer(Index: Integer): TPItemT;
var
  c: Integer;
  MPtr: TLazListClassesInternalMem.PMemRecord;
begin
  MPtr := FMem.FMem;
  if MPtr = nil
  then Result := nil
  else begin
    assert(Index <= MPtr^.Capacity, 'TGenLazRoundList.GetItemPointer: Index <= MPtr^.Capacity');
    Index := MPtr^.FirstItem.Idx + Index;
    c := MPtr^.Capacity;
    if Index >= MPtr^.Capacity then
      Index := Index - c;
    Result := TPItemT(@MPtr^.Data + Index * FItemSize.ItemSize);
  end;
end;

function TGenLazRoundList.GetItemPointerFast(Index: Integer): TPItemT;
var
  c: Cardinal;
  MPtr: TLazListClassesInternalMem.PMemRecord;
begin
  MPtr := FMem.FMem;
  assert(Cardinal(Index) <= MPtr^.Capacity, 'TGenLazRoundList.GetItemPointerFast: Index <= c');
  Index := MPtr^.FirstItem.Idx + Index;
  c := MPtr^.Capacity;
  if Cardinal(Index) >= c then
    Index := Index - c;
  Result := TPItemT(@MPtr^.Data + Index * FItemSize.ItemSize);
end;

procedure TGenLazRoundList.SetCapacity(AValue: Integer);
begin
  SetCapacityEx(AValue, 0, 0);
end;

function TGenLazRoundList.GetCapacity: Integer;
begin
  Result := FMem.Capacity;
end;

function TGenLazRoundList.GetCount: Integer;
begin
  Result := FMem.Count;
end;

procedure TGenLazRoundList.InternalMoveUp(AFromEnd, AToEnd: PByte; AByteCnt,
  AByteCap: Integer);
var
  c: Integer;
  l: PByte;
begin
  assert(AFromEnd <> AToEnd, 'TGenLazRoundList.InternalMoveUp: AFrom <> ATo');
  l := @FMem.FMem^.Data;
  if AToEnd = l then AToEnd := l + AByteCap;
  if AFromEnd = l then AFromEnd := l + AByteCap;

  if AToEnd < AFromEnd then begin
    c := Min(AToEnd - l, AByteCnt);
    AFromEnd := AFromEnd - c;
    AToEnd := AToEnd - c;
    Move(AFromEnd^, AToEnd^, c);
    AByteCnt := AByteCnt - c;
    if AByteCnt = 0 then
      exit;
    AToEnd := l + AByteCap;
  end;

  c := Min(AFromEnd - l, AByteCnt);
  AFromEnd := AFromEnd - c;
  AToEnd := AToEnd - c;
  Move(AFromEnd^, AToEnd^, c);
  AByteCnt := AByteCnt - c;
  if AByteCnt = 0 then
    exit;
  AFromEnd := l + AByteCap;

  c := Min(AToEnd - l, AByteCnt);
  AFromEnd := AFromEnd - c;
  AToEnd := AToEnd - c;
  Move(AFromEnd^, AToEnd^, c);
  AByteCnt := AByteCnt - c;
  if AByteCnt = 0 then
    exit;
  AToEnd := l + AByteCap;

  Move((AFromEnd-AByteCnt)^, (AToEnd-AByteCnt)^, AByteCnt);
end;

procedure TGenLazRoundList.InternalMoveDown(AFrom, ATo: PByte; AByteCnt: Integer;
  AUpperBound: PByte);
var
  c: Integer;
  l: PByte;
begin
  assert(AFrom <> ATo, 'TGenLazRoundList.InternalMoveDown: AFrom <> ATo');
  l := @FMem.FMem^.Data;
  if ATo > AFrom then begin
    c := Min(AUpperBound - ATo, AByteCnt);
    Move(AFrom^, ATo^, c);
    AByteCnt := AByteCnt - c;
    if AByteCnt = 0 then
      exit;
    ATo := l; // ATo + c - AByteCap;
    AFrom := AFrom + c;
  end;

  c := Min(AUpperBound - AFrom, AByteCnt);
  Move(AFrom^, ATo^, c);
  AByteCnt := AByteCnt - c;
  if AByteCnt = 0 then
    exit;
  AFrom := l; // AFrom + c - AByteCap;
  ATo := ATo + c;

  c := Min(AUpperBound - ATo, AByteCnt);
  Move(AFrom^, ATo^, c);
  AByteCnt := AByteCnt - c;
  if AByteCnt = 0 then
    exit;
  ATo := l; // ATo + c - AByteCap;
  AFrom := AFrom + c;

  Move(AFrom^, ATo^, AByteCnt);
end;

procedure TGenLazRoundList.MoveRowsUp(AFromIndex, AToIndex, ACount: Integer);
var
  Cnt, CapBytes, c, Diff: Integer;
  BytesToMove: Integer;
  u, pFrom, pTo: PByte;
  Cap: Cardinal;
  MPtr: TLazListClassesInternalMem.PMemRecord;
begin
  assert((AFromIndex>=0) and (AToIndex>AFromIndex) and (AToIndex+ACount<=Count), 'TGenLazRoundList.MoveRowsUp: (AFromIndex>=0) and (AToIndex>AFromIndex) and (AToIndex+ACount<=Count)');

  MPtr := FMem.FMem;
  Cnt := MPtr^.Count;
  Cap := MPtr^.Capacity;
  CapBytes := Cap * Cardinal(FItemSize.ItemSize);

  if (ACount * 2) >= Cnt then begin
    // FirstItemIndex = FirstItemIndex - Diff; // move ALL up
    Diff := AToIndex-AFromIndex;
    u := @MPtr^.Data + CapBytes;
    // Save data from after Target; move it after Source
    InternalMoveDown(PByte(GetItemPointerFast(AToIndex+ACount)),
                     PByte(GetItemPointerFast(AFromIndex+ACount)),
                     (Cnt - (AToIndex+ACount)) * FItemSize.ItemSize, u);
    // Move data before SOURCE down (may be below 0 / wrap)
    InternalMoveDown(PByte(GetItemPointerFast(0)), PByte(GetItemPointerFast(Cap-Diff)),
                     AFromIndex * FItemSize.ItemSize, u);
    c := MPtr^.FirstItem.Idx - Diff;
    if c < 0 then
      c := Cap - Cardinal(-c);
    MPtr^.FirstItem.Idx := c;

    c := Cap - (AFromIndex + MPtr^.FirstItem.Idx);
    if c <= 0 then c := c + Cap;
    if c < Diff then begin
      FInitMem.InitMem(PByte(GetItemPointerFast(AFromIndex)), c, FItemSize.ItemSize);
      FInitMem.InitMem(@MPtr^.Data, Diff - c, FItemSize.ItemSize);
    end
    else
      FInitMem.InitMem(PByte(GetItemPointerFast(AFromIndex)), Diff, FItemSize.ItemSize);
  end
  else begin
    // normal move
    BytesToMove := FItemSize.ItemSize * ACount;
    pFrom := PByte(GetItemPointerFast(AFromIndex+ACount));
    pTo   := PByte(GetItemPointerFast(AToIndex+ACount));
    InternalMoveUp(pFrom, pTo, BytesToMove, CapBytes);

    Diff := min(ACount, AToIndex-AFromIndex);
    c := Cap - (AFromIndex + MPtr^.FirstItem.Idx);
    if c <= 0 then c := c + Cap;
    if c < Diff then begin
      FInitMem.InitMem(PByte(GetItemPointerFast(AFromIndex)), c, FItemSize.ItemSize);
      FInitMem.InitMem(@MPtr^.Data, Diff - c, FItemSize.ItemSize);
    end
    else
      FInitMem.InitMem(PByte(GetItemPointerFast(AFromIndex)), Diff, FItemSize.ItemSize);
  end;
  assert((MPtr^.FirstItem.Idx >= 0) and (MPtr^.FirstItem.Idx < Capacity), 'TGenLazRoundList.MoveRows: (MPtr^.FirstItem.Idx >= 0) and (MPtr^.FirstItem.Idx < Capacity)');
end;

procedure TGenLazRoundList.MoveRowsDown(AFromIndex, AToIndex, ACount: Integer);
var
  Cnt, CapBytes, c, Diff: Integer;
  BytesToMove, f: Integer;
  pFrom, pTo: PByte;
  Cap: Cardinal;
  MPtr: TLazListClassesInternalMem.PMemRecord;
begin
  assert((AFromIndex>AToIndex) and (AToIndex>=0) and (AFromIndex+ACount<=Count), 'TGenLazRoundList.MoveRowsDown: (AFromIndex>AToIndex) and (AToIndex>=0) and (AFromIndex+ACount<=Count)');

  MPtr := FMem.FMem;
  Cnt := MPtr^.Count;
  Cap := MPtr^.Capacity;
  CapBytes := Cap * Cardinal(FItemSize.ItemSize);

  if (ACount * 2) >= Cnt then begin
    // FirstItemIndex = FirstItemIndex + Diff; // move ALL down
    Diff := AFromIndex-AToIndex;
    // Save data in front of AToIndex; move it in front of AFromIndex;
    InternalMoveUp(PByte(GetItemPointerFast(AToIndex)), PByte(GetItemPointerFast(AFromIndex)),
                   AToIndex * FItemSize.ItemSize, CapBytes);
    // Move data after END-OF-SOURCE up (moving behind current count (wrap around capacity if needed))
    c := Cnt + Diff;
    if Cardinal(c) > Cap then
      c := Cardinal(c) - Cap;
    InternalMoveUp(PByte(GetItemPointerFast(Cnt)),
                   PByte(GetItemPointerFast(c)), // Cnt=Cap will be handled by GetItemPointerFast
                   (Cnt - (AFromIndex+ACount)) * FItemSize.ItemSize, CapBytes);
    c := MPtr^.FirstItem.Idx + Diff;
    if Cardinal(c) >= Cap then
      c := Cardinal(c) - Cap;
    MPtr^.FirstItem.Idx := c;

    f := AToIndex + ACount;
    c := Cap - (f + MPtr^.FirstItem.Idx);
    if c <= 0 then c := c + Cap;
    if c < Diff then begin
      FInitMem.InitMem(PByte(GetItemPointerFast(f)), c, FItemSize.ItemSize);
      FInitMem.InitMem(@MPtr^.Data, Diff - c, FItemSize.ItemSize);
    end
    else
      FInitMem.InitMem(PByte(GetItemPointerFast(AToIndex+ACount)), Diff, FItemSize.ItemSize);
  end
  else begin
    // normal move
    BytesToMove := FItemSize.ItemSize * ACount;
    pFrom := PByte(GetItemPointerFast(AFromIndex));
    pTo   := PByte(GetItemPointerFast(AToIndex));
    InternalMoveDown(pFrom, pTo, BytesToMove, @MPtr^.Data + CapBytes);

    Diff := AFromIndex-AToIndex;
    f := AFromIndex + max(0, ACount - Diff);
    Diff := min(ACount, Diff);
    c := Cap - (f + MPtr^.FirstItem.Idx);
    if c <= 0 then c := c + Cap;
    if c < Diff then begin
      FInitMem.InitMem(PByte(GetItemPointerFast(f)), c, FItemSize.ItemSize);
      FInitMem.InitMem(@MPtr^.Data, Diff - c, FItemSize.ItemSize);
    end
    else
      FInitMem.InitMem(PByte(GetItemPointerFast(f)), Diff, FItemSize.ItemSize);
  end;
  assert((MPtr^.FirstItem.Idx >= 0) and (MPtr^.FirstItem.Idx < Capacity), 'TGenLazRoundList.MoveRows: (MPtr^.FirstItem.Idx >= 0) and (MPtr^.FirstItem.Idx < Capacity)');
end;

function TGenLazRoundList.SetCapacityEx(AValue, AnInsertPos,
  AnInsertSize: Integer): TPItemT;
var
  NewMem: TLazListClassesInternalMem;
  Pos1, Cnt, NewCnt, siz, siz2: Integer;
  PTarget, PSource, m: PByte;
  NewMPtr, MPtr: TLazListClassesInternalMem.PMemRecord;
begin
  Result := nil;
  Cnt := FMem.Count;
  NewCnt := Cnt + AnInsertSize;
  if AValue < NewCnt then
    AValue := NewCnt;

  if AValue = 0 then begin
    FMem.Free;
    exit;
  end;

  if AnInsertSize = 0 then begin
    if (AValue = Capacity) then
      exit;
    AnInsertPos := 0;
  end;

  {%H-}NewMem.Init;
  NewMem.Alloc(AValue * FItemSize.ItemSize);

  NewMPtr := NewMem.FMem;
  Pos1 := Cardinal(AValue-NewCnt) div 2;
  PTarget := @NewMPtr^.Data + (Pos1 * FItemSize.ItemSize);

  NewMPtr^.FirstItem.Idx:= Pos1;
  NewMem.Count := NewCnt;
  NewMem.Capacity := AValue;
  assert((NewMPtr^.FirstItem.Idx >= 0) and (NewMPtr^.FirstItem.Idx {%H-}< NewMem.Capacity), 'TGenLazShiftList.InsertRowsEx: (NewMPtr^.FirstItem.Idx >= NewMem.NewMem+NewMem.DATA_OFFS) and (NewMPtr^.FirstItem.Idx < NewMem.NewMem+NewMem.DATA_OFFS + NewMem.Capacity)');

  if Cnt > 0 then begin
    MPtr := FMem.FMem;
    m := @MPtr^.Data;
    PSource := m + (MPtr^.FirstItem.Idx * FItemSize.ItemSize);
    m := m + FMem.Capacity * Cardinal(FItemSize.ItemSize);
    if AnInsertPos > 0 then begin
      siz := (AnInsertPos * FItemSize.ItemSize);
      siz2 := m - PSource;
      if siz > siz2 then begin
        Move(PSource^, PTarget^, siz2);
        Move(MPtr^.Data, (PTarget+siz2)^, siz - siz2);
      end
      else
        Move(PSource^, PTarget^, siz);
      Result := TPItemT(PTarget + siz);
    end
    else
      Result := TPItemT(PTarget);

    if AnInsertPos < Cnt then begin
      PSource := PByte(ItemPointer[AnInsertPos]);
      PTarget := PTarget + ((AnInsertPos + AnInsertSize) * FItemSize.ItemSize);
      siz := ((Cnt - AnInsertPos) * FItemSize.ItemSize);
      siz2 := m - PSource;
      if siz > siz2 then begin
        Move(PSource^, PTarget^, siz2);
        Move(MPtr^.Data, (PTarget+siz2)^, siz - siz2);
      end
      else
        Move(PSource^, PTarget^, siz);

    end;
    if AnInsertSize > 0 then
      FInitMem.InitMem(Result, AnInsertSize, FItemSize.ItemSize);
  end
  else begin
    assert(AnInsertPos=0, 'TGenLazShiftList.SetCapacityEx: AnInsertPos=0');
    if AnInsertSize > 0 then
      FInitMem.InitMem(PTarget, AnInsertSize, FItemSize.ItemSize);
    Result := TPItemT(PTarget);
  end;

  FMem.Free;
  FMem := NewMem;
end;

function TGenLazRoundList.InsertRows(AIndex, ACount: Integer): TPItemT;
var
  Cnt, Cap: Integer;
  siz, PSourceIdx, PTargetIdx, c, CapBytes: Integer;
  PTarget, PSource, m: PByte;
  MPtr: TLazListClassesInternalMem.PMemRecord;
begin
  Result := nil;
  if ACount = 0 then exit;
// TODO: MPTR up here
  Cnt := FMem.Count;
  Cap := FMem.Capacity;
  assert((ACount>0) and (AIndex>=0) and (AIndex<=Cnt), 'TLazShiftBufferListObj.InsertRows: (ACount>0) and (AIndex>=0) and (AIndex<=Cnt)');

  if Cnt + ACount > Cap then begin
    Result := SetCapacityEx(FCapacity.GrowCapacity(Cnt + ACount, Cap), AIndex, ACount);
    exit;
  end;

  MPtr := FMem.FMem;
  CapBytes := Cap * Cardinal(FItemSize.ItemSize);
  if (AIndex = 0) or (Cardinal(AIndex) < Cardinal(Cnt) div 2) then begin
    // use space at front of list
    PSourceIdx := MPtr^.FirstItem.Idx;
    PTargetIdx := PSourceIdx - ACount;
    if PtrInt(PTargetIdx) < 0 then
      PTargetIdx := PTargetIdx + Cap;
    MPtr^.FirstItem.Idx := PTargetIdx;
    FMem.Count := Cnt + ACount;

    PTarget := @MPtr^.Data + PTargetIdx * FItemSize.ItemSize;

    if AIndex > 0 then begin
      PSource := @MPtr^.Data + PSourceIdx * FItemSize.ItemSize;
      siz := AIndex * FItemSize.ItemSize;
      Result := TPItemT(PTarget + siz);
      m := @MPtr^.Data + CapBytes;
      if PByte(Result) >= m then
        Result := TPItemT(PByte(Result) - CapBytes);
      InternalMoveDown(PSource, PTarget, siz, m);
    end
    else
      Result := TPItemT(PTarget);
  end
  else
  begin
    // use space at end of list
    PSource := PByte(ItemPointerFast[Cnt]);
    PTarget := PSource + (ACount * FItemSize.ItemSize);
    if PTarget > @MPtr^.Data + CapBytes then
      PTarget := PTarget - CapBytes;

    FMem.Count := Cnt + ACount;

    if AIndex < Cnt then begin
      siz := (Cnt-AIndex) * FItemSize.ItemSize;
      m := @MPtr^.Data;
      Result := TPItemT(PSource - siz);
      if PByte(Result) < m then
        Result := TPItemT(PByte(Result) + CapBytes);
      InternalMoveUp(PSource, PTarget, siz, CapBytes);
    end
    else
      Result := TPItemT(PSource);
  end;

  c := Cap - (AIndex + MPtr^.FirstItem.Idx);
  if c <= 0 then c := c + Cap;
  if c < ACount then begin
    FInitMem.InitMem(PByte(GetItemPointerFast(AIndex)), c, FItemSize.ItemSize);
    FInitMem.InitMem(@MPtr^.Data, ACount - c, FItemSize.ItemSize);
  end
  else
    FInitMem.InitMem(PByte(GetItemPointerFast(AIndex)), ACount, FItemSize.ItemSize);

  assert((MPtr^.FirstItem.Idx >= 0) and (MPtr^.FirstItem.Idx {%H-}< FMem.Capacity), 'TGenLazShiftList.InsertRowsEx: (MPtr^.FirstItem.Ptr >= MPtr+FMem.DATA_OFFS) and (MPtr^.FirstItem.Ptr < FMem.FMem+FMem.DATA_OFFS + FMem.Capacity)');
end;

procedure TGenLazRoundList.DeleteRows(AIndex, ACount: Integer);
var
  Cnt, Cap, CapBytes, Middle, i, siz, siz2: Integer;
  PTarget, PSource, m: PByte;
  MPtr: TLazListClassesInternalMem.PMemRecord;
begin
  if ACount = 0 then exit;

  Cnt := FMem.Count;
  Cap := FMem.Capacity;
  CapBytes := Cap * Cardinal(FItemSize.ItemSize);
  assert((ACount>0) and (AIndex>=0) and (AIndex+ACount<=Cnt), 'TGenLazShiftList.DeleteRowsEx: (ACount>0) and (AIndex>=0) and (AIndex+ACount<=Cnt)');
  Middle := Cardinal(Cnt) div 2;

  MPtr := FMem.FMem;
  if (AIndex < Middle) or (AIndex = 0) then begin
    // make space at front of list
    PTarget := PByte(ItemPointerFast[AIndex+ACount]);
    PSource := PByte(ItemPointerFast[AIndex]);
    FInitMem.FinalizeMem(PSource, ACount, FItemSize.ItemSize);
    if AIndex > 0 then begin
      siz := AIndex * FItemSize.ItemSize;
      m := @MPtr^.Data;
      while siz > 0 do begin
        siz2 := Min(siz, PSource - m);
        siz2 := Min(siz2, PTarget - m);
        Move((PSource-siz2)^, (PTarget-siz2)^, siz2);
        siz := siz - siz2;
        dec(PSource, siz2);
        if PSource <= m then
          PSource := PSource + CapBytes;
        dec(PTarget, siz2);
        if PTarget <= m then
          PTarget := PTarget + CapBytes;
      end;
      if PTarget = m + CapBytes then
        PTarget := m;
    end;

    i := MPtr^.FirstItem.Idx + ACount;
    if i >= Cap then
      i := i - Cap;
    MPtr^.FirstItem.Idx := i;
    FMem.Count := Cnt - ACount;
  end
  else begin
    // make space at end of list
    FInitMem.FinalizeMem(PByte(ItemPointerFast[AIndex]), ACount, FItemSize.ItemSize);
    if AIndex < Cnt-ACount then begin
      PSource := PByte(ItemPointerFast[AIndex+ACount]);
      PTarget := PByte(ItemPointerFast[AIndex]);
      siz := (cnt - (AIndex+ACount)) * FItemSize.ItemSize;
      m := @MPtr^.Data + CapBytes;
      while siz > 0 do begin
        siz2 := Min(siz, m - PSource);
        siz2 := Min(siz2, m - PTarget);
        Move(PSource^, PTarget^, siz2);
        siz := siz - siz2;
        inc(PSource, siz2);
        if PSource >= m then
          PSource := PSource - CapBytes;
        inc(PTarget, siz2);
        if PTarget >= m then
          PTarget := PTarget - CapBytes;
      end;
    end;

    FMem.Count := Cnt - ACount;
  end;

  Cnt := FMem.Count;
  i := FCapacity.ShrinkCapacity(Cnt, Cap);
  if i >= 0 then
    SetCapacityEx(i, 0, 0)
  else
  if (Cnt = 0) then
    MPtr^.FirstItem.Idx:= 0;
  assert((not FMem.IsAllocated) or ((FMem.FMem^.FirstItem.Idx >= 0) and (FMem.FMem^.FirstItem.Idx {%H-}< FMem.Capacity)), 'TGenLazShiftList.DeleteRowsEx: (FMem.FMem^.FirstItem.Ptr >= FMem.FMem+FMem.DATA_OFFS) and (FMem.FMem^.FirstItem.Ptr < FMem.FMem+FMem.DATA_OFFS + FMem.Capacity)');
end;

function TGenLazRoundList.IndexOf(AnItem: TPItemT; AFirstIdx: integer): integer;
var
  p: Pointer;
  s, c, c2: Integer;
  MPtr: TLazListClassesInternalMem.PMemRecord;
begin
  c := FMem.Count;
  if AFirstIdx >= c then
    exit(-1);

  MPtr := FMem.FMem;
  s := FItemSize.ItemSize;
  c2 := MPtr^.Capacity - MPtr^.FirstItem.Idx;

  Result := AFirstIdx;
  if Result < c2 then begin
    p := ItemPointerFast[Result];
    while Result < c2 do begin
      if CompareMem(p, AnItem, s) then exit;
      inc(Result);
      p := p + FItemSize.ItemSize;
    end;
  end;

  p := ItemPointerFast[Result];
  while Result < c do begin
    if CompareMem(p, AnItem, s) then exit;
    inc(Result);
    p := p + FItemSize.ItemSize;
  end;

  Result := -1;
end;

procedure TGenLazRoundList.Create;
begin
  FCapacity.Init;
  FInitMem.Init;
  FMem.Init;
end;

procedure TGenLazRoundList.Destroy;
begin
  FMem.Free;
end;

procedure TGenLazRoundList.MoveRows(AFromIndex, AToIndex, ACount: Integer);
begin
  if AToIndex < AFromIndex then
    MoveRowsDown(AFromIndex, AToIndex, ACount)
  else
    MoveRowsUp(AFromIndex, AToIndex, ACount);
end;

procedure TGenLazRoundList.SwapEntries(AIndex1, AIndex2: Integer);
var
  t: PByte;
begin
  t := Getmem(FItemSize.ItemSize);
  Move(PByte(GetItemPointerFast(AIndex1))^, t^, FItemSize.ItemSize);
  Move(PByte(GetItemPointerFast(AIndex2))^, PByte(GetItemPointerFast(AIndex1))^, FItemSize.ItemSize);
  Move(t^, PByte(GetItemPointerFast(AIndex2))^, FItemSize.ItemSize);
  FreeMem(t);
end;

procedure TGenLazRoundList.DebugDump;
var i , c: integer; s:string;
begin
end;

function TGenLazRoundList.IndexOf(AnItem: TPItemT): integer;
//var
//  p: Pointer;
//  s, c, c2: Integer;
begin
  exit(IndexOf(AnItem, 0));
  ////////////////////
  //c := Count;
  //if c = 0 then
  //  exit(-1);
  //
  //s := FItemSize.ItemSize;
  //c2 := FMem.FMem^.Capacity - FMem.FMem^.FirstItem.Idx;
  //
  //p := ItemPointerFast[0];
  //Result := 0;
  //while Result < c2 do begin
  //  if CompareMem(p, AnItem, s) then exit;
  //  inc(Result);
  //  p := p + FItemSize.ItemSize;
  //end;
  //
  //p := ItemPointerFast[Result];
  //while Result < c do begin
  //  if CompareMem(p, AnItem, s) then exit;
  //  inc(Result);
  //  p := p + FItemSize.ItemSize;
  //end;
  // Result:=-1;
end;

{ TGenLazRoundListVarSize }

procedure TGenLazRoundListVarSize.Create(AnItemSize: Integer);
begin
  FItemSize.ItemSize := AnItemSize;
  inherited Create;
end;

{ TGenLazRoundListFixedType }

function TGenLazRoundListFixedType.Get(Index: Integer): T;
begin
  Result := ItemPointer[Index]^;
end;

procedure TGenLazRoundListFixedType.Put(Index: Integer; AValue: T);
begin
  ItemPointerFast[Index]^ := AValue;
end;

function TGenLazRoundListFixedType.IndexOf(AnItem: T): integer;
var
  p: PT;
  s, c, c2: Integer;
  MPtr: TLazListClassesInternalMem.PMemRecord;
begin
  c := FMem.Count;
  if c = 0 then
    exit(-1);

  MPtr := FMem.FMem;
  s := FItemSize.ItemSize;
  c2 := MPtr^.Capacity - MPtr^.FirstItem.Idx;

  p := ItemPointerFast[0];
  Result := 0;
  while Result < c2 do begin
    if p^ = AnItem then exit;
    inc(Result);
    p := p + FItemSize.ItemSize;
  end;

  p := ItemPointerFast[Result];
  while Result < c do begin
    if p^ = AnItem then exit;
    inc(Result);
    p := p + FItemSize.ItemSize;
  end;
  Result := -1;
end;


end.

