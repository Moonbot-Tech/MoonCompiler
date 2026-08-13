unit LazListClassesBase;

{$mode objfpc}{$H+}
{$WARN 3124 off : Inlining disabled}
interface
{$IFDEF LazListClassTestCase}
  {$INLINE off}
{$ELSE}
  {$INLINE on}
  {$Optimization AUTOINLINE}
  {$Optimization REMOVEEMPTYPROCS}
  {$Optimization DFA}
  (* DEADSTORE, DEADVALUES: important when calls to empty procs are removed *)
  {$Optimization DEADSTORE} // needs DFA
  {$Optimization DEADVALUES}
  {$Optimization CONSTPROP}
  {$Optimization CSE}
  // needs speed eval
  { $Optimization USELOADMODIFYSTORE}

  { $Optimization REGVAR}
  { $Optimization STACKFRAME}
{$ENDIF}
{$IMPLICITEXCEPTIONS off}

type
  {$WriteableConst off}

  { TLazListClassesMemInitNone }

  TLazListClassesMemInitNone = object
  public
    class procedure Init(); inline; static;

    (* InitMem: First init
       - for InsertRows
       - for emptied Source area of move (old data is NOT finalized, since it moved)
    *)
    class procedure InitMem(const {%H-}AMem: Pointer; const {%H-}AnItemCount: Integer; const {%H-}AnItemSize: Cardinal); inline; static;

    (* FinalizeMem: (e.g. decrease ref count)
       - Before DeleteRows
       - Before Move for Target area, finalize old data.
       - NOT in Item[x] := / "Item[x]" uses a typed assignment of the data
       - No need to actually init/clean the underlaying memory
    *)
    class procedure FinalizeMem(const {%H-}AMem: Pointer; const {%H-}AnItemCount: Integer; const {%H-}AnItemSize: Cardinal); inline; static;

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

  { TLazListClassesCapacityFixed }

  TLazListClassesCapacityFixed = object
  public type
    TCapacityTypeForMem = Cardinal;
    TCapacityTypeForObj = record end;
  public
    class procedure Init(); inline; static;
    class function GrowCapacity(const ARequired, {%H-}ACurrent: Integer): Integer; inline; static;
    class function ShrinkCapacity(const ARequired, {%H-}ACurrent: Integer): Integer; inline; static;

    class function ReadCapacity(const AMem: Pointer): Cardinal; inline; static;
  end;

  { TLazListClassesRangeNoIndexCheck }

  TLazListClassesRangeNoIndexCheck = object
  public
    generic class function CheckIndex<T>(const {%H-}AList: T; const {%H-}AnIndex: Integer; var {%H-}Res: Pointer): Boolean; inline; static;
    generic class function CheckInsert<T>(const {%H-}AList: T; var {%H-}AnIndex: Integer; var {%H-}Res: Pointer): Boolean; inline; static;
    generic class function CheckDelete<T>(const {%H-}AList: T; var {%H-}AnIndex, {%H-}ACount: Integer): Boolean; inline; static;
    generic class function CheckMove<T>(const {%H-}AList: T; var {%H-}AFromIndex, {%H-}AToIndex, {%H-}ACount: Integer): Boolean; inline; static;
    generic class function CheckSwap<T>(const {%H-}AList: T; var {%H-}AnIndex1, {%H-}AnIndex2: Integer): Boolean; inline; static;
  end;



  TLazListClassesConfig = class
  private type
    TLazListClassesItemSize   = object
    public const
      ItemSize = 0;
    end;

    TLazListClassesMemInit    = object(TLazListClassesMemInitNone)
    end;

    TLazListClassesCapacity   = object(TLazListClassesCapacityFixed)
    end;

    TLazListClassesIndexCheck = object(TLazListClassesRangeNoIndexCheck)
    end;
  end;


  generic __TGenLazListClassesInternalBase<_CONF_: TLazListClassesConfig> = object
  protected type
    TSizeT     = _CONF_.TLazListClassesItemSize;
    TInitMemT  = _CONF_.TLazListClassesMemInit;
    TCapacityT = _CONF_.TLazListClassesCapacity;
    TIdxCheckT = _CONF_.TLazListClassesIndexCheck;
  end;

implementation

{ TLazListClassesMemInitNone }

class procedure TLazListClassesMemInitNone.Init();
begin
  //
end;

class procedure TLazListClassesMemInitNone.InitMem(const AMem: Pointer;
  const AnItemCount: Integer; const AnItemSize: Cardinal);
begin
  //
end;

class procedure TLazListClassesMemInitNone.FinalizeMem(const AMem: Pointer;
  const AnItemCount: Integer; const AnItemSize: Cardinal);
begin
  //
end;

{ TLazListClassesCapacityFixed }

class procedure TLazListClassesCapacityFixed.Init();
begin
  // nothing
end;

class function TLazListClassesCapacityFixed.GrowCapacity(const ARequired, ACurrent: Integer
  ): Integer;
begin
  assert(False, 'TLazListClassesCapacityFixed.GrowCapacity: False');
  Result := ARequired;
end;

class function TLazListClassesCapacityFixed.ShrinkCapacity(const ARequired, ACurrent: Integer
  ): Integer;
begin
  assert(False, 'TLazListClassesCapacityFixed.ShrinkCapacity: False');
  Result := ARequired;
end;

type
    TMemRecord = record
      FirstItem: record
        case integer of
          1: (Ptr: PByte;);
          2: (Idx: Cardinal;);
        end;
      Count: Integer;
      Capacity: Cardinal;
      Data: byte; // Dummy byte: The address for the first byte of data. This is a dummy field (pbyte for pointer math)
    end;
    PMemRecord = ^TMemRecord;
class function TLazListClassesCapacityFixed.ReadCapacity(const AMem: Pointer): Cardinal;
begin
  Result := PMemRecord(AMem)^.Capacity;
end;

{ TLazListClassesRangeNoIndexCheck }

generic class function TLazListClassesRangeNoIndexCheck.CheckIndex<T>(const AList: T;
  const AnIndex: Integer; var Res: Pointer): Boolean;
begin
  Result := True;
end;

generic class function TLazListClassesRangeNoIndexCheck.CheckInsert<T>(const AList: T;
  var AnIndex: Integer; var Res: Pointer): Boolean;
begin
  Result := True;
end;

generic class function TLazListClassesRangeNoIndexCheck.CheckDelete<T>(const AList: T;
  var AnIndex, ACount: Integer): Boolean;
begin
  Result := True;
end;

generic class function TLazListClassesRangeNoIndexCheck.CheckMove<T>(const AList: T;
  var AFromIndex, AToIndex, ACount: Integer): Boolean;
begin
  Result := True;
end;

generic class function TLazListClassesRangeNoIndexCheck.CheckSwap<T>(const AList: T; var AnIndex1,
  AnIndex2: Integer): Boolean;
begin
  Result := True;
end;

end.

