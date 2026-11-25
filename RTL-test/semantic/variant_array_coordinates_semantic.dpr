program variant_array_coordinates_semantic;
{$ifdef FPC}{$mode delphi}{$endif}
{$apptype console}
uses SysUtils, Variants{$ifdef FPC}, VarUtils{$endif};
type
  TWatcher = class(TInterfacedObject)
    destructor Destroy; override;
  end;
var
  Released: Integer;
destructor TWatcher.Destroy;
begin
  Inc(Released);
  inherited;
end;
procedure Check(Ok: Boolean; const Detail: string);
begin
  if not Ok then begin WriteLn('FAIL ', Detail); Halt(1) end;
end;

procedure CheckTable(RowLow, ColLow: Integer);
var
  V, Snapshot: Variant;
  Row, Col, I: Integer;
  P: PInteger;
begin
  V := VarArrayCreate([RowLow, RowLow+1, ColLow, ColLow+2], varInteger);
  for Row := 0 to 1 do
    for Col := 0 to 2 do
      V[RowLow+Row,ColLow+Col] := 100*(Row+1)+Col+5;
  Snapshot := V;
  VarArrayRedim(V, ColLow+3);
  Check((VarArrayLowBound(V,1)=RowLow) and (VarArrayHighBound(V,1)=RowLow+1) and
    (VarArrayLowBound(V,2)=ColLow) and (VarArrayHighBound(V,2)=ColLow+3), 'grow bounds');
  for Row := 0 to 1 do begin
    for Col := 0 to 2 do
      Check(Integer(V[RowLow+Row,ColLow+Col])=100*(Row+1)+Col+5, 'coordinates preserved');
    Check(Integer(V[RowLow+Row,ColLow+3])=0, 'new cells initialized');
  end;
  P := VarArrayLock(V);
  try
    for I := 0 to 5 do begin
      Check(P^=100*(I mod 2+1)+I div 2+5, 'leftmost dimension contiguous');
      Inc(P);
    end;
  finally VarArrayUnlock(V) end;
  VarArrayRedim(V, ColLow);
  Check((Integer(V[RowLow+1,ColLow])=205) and (Integer(Snapshot[RowLow+1,ColLow+2])=207), 'shrink and snapshot');
end;

procedure CheckCube;
var V: Variant; I,J,K: Integer;
begin
  V := VarArrayCreate([-1,1,2,4,6,8],varInteger);
  for I := -1 to 1 do for J := 2 to 4 do for K := 6 to 8 do V[I,J,K] := I*100+J*10+K;
  for K := 8 downto 6 do for J := 4 downto 2 do for I := 1 downto -1 do
    Check(Integer(V[I,J,K])=I*100+J*10+K, 'independent 3D coordinates');
end;

procedure CheckLocks;
var V: Variant; P,Q: PInteger; Rejected: Boolean; I: Integer;
begin
  V := VarArrayCreate([-2,0],varInteger);
  V[-2] := 73;
  P := VarArrayLock(V);
  Q := VarArrayLock(V);
  Check(P=Q, 'nested lock pointer');
  for I := 1 to 2 do begin
    Rejected := False;
    try VarArrayRedim(V,3) except on E: EVariantError do Rejected := True end;
    Check(Rejected, 'resize with outstanding lock');
    Check((VarArrayHighBound(V,1)=0) and (P^=73), 'locked data preserved');
    VarArrayUnlock(V);
  end;
  VarArrayRedim(V,3);
  Check(Integer(V[-2])=73, 'resize after last unlock');
end;

procedure StoreOwner(var V: Variant);
var Owner: IInterface;
begin
  Owner := TWatcher.Create;
  V[1,5] := Owner;
end;

procedure CheckManaged;
var V: Variant;
begin
  V := VarArrayCreate([0,1,4,5],varUnknown);
  StoreOwner(V);
  Check(Released=0,'array owns interface');
  VarArrayRedim(V,6);
  Check(Released=0,'grow retains owner');
  VarArrayRedim(V,4);
  Check(Released=1,'shrink releases removed owner');
  VarClear(V);
  Check(Released=1,'owner finalized once');
  V := VarArrayCreate([0,1,4,5],varOleStr);
  V[1,4] := WideString('kept');
  V[0,5] := WideString('discarded');
  VarArrayRedim(V,4);
  Check(WideString(V[1,4])='kept','shrink keeps managed string');
end;
procedure CheckEmptyAndByRef;
var V, AliasArray, SecondAlias: Variant;
begin
  V := VarArrayCreate([4,5,-3,-2],varInteger);
  AliasArray := VarArrayRef(V);
  Check(VarArrayDimCount(AliasArray)=2,'borrowed rank');
  VarArrayRedim(AliasArray,-4);
  Check((VarArrayLowBound(V,2)=-3) and (VarArrayHighBound(V,2)=-4), 'empty last dimension');
  VarArrayRedim(AliasArray,-2);
  Check((Integer(V[4,-3])=0) and (Integer(V[5,-2])=0), 'regrow through by-reference array');
  V[5,-2] := 91;
  Check(Integer(AliasArray[5,-2])=91, 'by-reference coordinates');
  SecondAlias:=VarArrayRef(AliasArray);
  SecondAlias[5,-2]:=113;
  VarClear(SecondAlias);
  VarClear(AliasArray);
  Check(Integer(V[5,-2])=113,'nested and cleared references preserve owner');
{$ifdef FPC}
  { A Variant-element array is copied on assignment, including a returned
    VarArrayRef temporary. Clearing the temporary must preserve the source. }
  V:=VarArrayCreate([1,2],varVariant);
  V[1]:=WideString('owner');
  V[2]:=19;
  AliasArray:=VarArrayRef(V);
  AliasArray[2]:=37;
  Check((Integer(AliasArray[2])=37) and (Integer(V[2])=19),'independent variant-element copy');
  VarClear(AliasArray);
  Check((WideString(V[1])='owner') and (Integer(V[2])=19),'borrowed temporary preserves original cells');
{$endif}
end;

{$ifdef FPC}
procedure StoreNativeString(var V: Variant; const Text: AnsiString);
var Cell: PVariant;
begin
  Cell:=VarArrayLock(V);
  try
    Inc(Cell);
    Cell^:=Text;
  finally VarArrayUnlock(V) end;
end;

procedure CheckVariantArrayCopies;
var
  V, Clone: Variant;
  CopyDescriptor: PVarArray;
  Text: AnsiString;
  RefCount: SizeInt;
  RawBound: TVarArrayBound;
  Upper: LongInt;
  Rejected: Boolean;
  Bounds: array[0..129] of SizeInt;
  Coords: array[0..64] of LongInt;
  I: Integer;
begin
  RawBound.LowBound:=High(LongInt);
  RawBound.ElementCount:=2;
  Rejected:=False;
  try
    V:=VarArrayCreate(PVarArrayBoundArray(@RawBound),1,varInteger);
  except on E: EVariantError do Rejected:=True end;
  Check(Rejected,'descriptor with an unrepresentable last index is rejected');
  V:=VarArrayCreate([High(LongInt),High(LongInt)],varInteger);
  Check(VarUtils.SafeArrayRedim(VarArrayAsPSafeArray(V),RawBound)=0,'native descriptor accepts count');
  Check(VarUtils.SafeArrayGetUBound(VarArrayAsPSafeArray(V),1,Upper)=VAR_OVERFLOW,'native upper bound reports overflow');
  for I:=0 to High(Coords) do begin
    Coords[I]:=I-33;
    Bounds[I*2]:=Coords[I];
    Bounds[I*2+1]:=Coords[I];
  end;
  V:=VarArrayCreate(Bounds,varVariant);
  VarArrayPut(V,WideString('65 axes'),Coords);
  Clone:=V;
  Check((WideString(VarArrayGet(Clone,Coords))='65 axes') and VarSameValue(V,Clone),'copy and comparison of high rank');

  V:=VarArrayCreate([High(LongInt)-1,High(LongInt)],varVariant);
  V[High(LongInt)]:=WideString('last');
  Clone:=V;
  Check((WideString(Clone[High(LongInt)])='last') and VarSameValue(V,Clone),'copy includes maximum signed index');
  CopyDescriptor:=nil;
  Check(VarUtils.SafeArrayCopy(VarArrayAsPSafeArray(V),CopyDescriptor)=0,'copy raw descriptor');
  VarClear(Clone);
  TVarData(Clone).VType:=varArray or varVariant;
  TVarData(Clone).VArray:=CopyDescriptor;
  VarClear(V);
  Check(WideString(Clone[High(LongInt)])='last','raw copy owns its managed cells');
{$ifdef UNIX}
  V:=VarArrayCreate([0,-1,0,2147483646,0,2147483646,0,2147483646],varByte);
  Check((VarArrayDimCount(V)=4) and (VarArrayHighBound(V,1)=-1),'empty dimension makes the product zero');
  V:=VarArrayCreate([0,1],varVariant);
  Text:=AnsiString('reference ')+IntToStr(73);
  RefCount:=StringRefCount(Text);
  StoreNativeString(V,Text);
  Check(StringRefCount(Text)>RefCount,'array retains native string');
  VarArrayRedim(V,0);
  Check(StringRefCount(Text)=RefCount,'shrinking releases native string in a Variant cell');
{$endif}
end;
{$endif}

{$if defined(FPC) and defined(UNIX)}
var
  SavedMM, TestMM: TMemoryManager;
  Tracked: Pointer;
  ThrowOnResize, Refused: Boolean;

function FailResize(var P: Pointer; Size: PtrUInt): Pointer;
begin
  if P=Tracked then begin
    Refused:=True;
    if ThrowOnResize then OutOfMemoryError;
    Exit(nil);
  end;
  Result:=SavedMM.ReAllocMem(P,Size);
end;

function RefuseCopy(Size: PtrUInt): Pointer;
begin
  if Size=257*SizeOf(Integer) then begin
    Refused:=True;
    Exit(nil);
  end;
  Result:=SavedMM.AllocMem(Size);
end;

procedure CheckCopyFailure;
var V, CopyOfV: Variant; Failed: Boolean;
begin
  V:=VarArrayCreate([0,256],varInteger);
  V[3]:=7;
  GetMemoryManager(SavedMM);
  TestMM:=SavedMM;
  TestMM.AllocMem:=@RefuseCopy;
  Failed:=False;
  Refused:=False;
  SetMemoryManager(TestMM);
  try
    try CopyOfV:=V except on E: EVariantError do Failed:=True end;
  finally SetMemoryManager(SavedMM) end;
  Check(Failed and Refused,'refused copy reports failure');
  Check(VarIsEmpty(CopyOfV),'failed copy publishes no active result');
  VarArrayRedim(V,257);
  CopyOfV:=V;
  Check((Integer(CopyOfV[3])=7) and (Integer(CopyOfV[257])=0),'failed copy releases source lock and permits retry');
end;

procedure CheckResizeFailure(RaiseError: Boolean);
var V: Variant; Failed: Boolean;
begin
  V:=VarArrayCreate([-1,1],varInteger);
  V[0]:=73;
  Tracked:=VarArrayLock(V);
  VarArrayUnlock(V);
  GetMemoryManager(SavedMM);
  TestMM:=SavedMM;
  TestMM.ReAllocMem:=@FailResize;
  ThrowOnResize:=RaiseError;
  Refused:=False;
  Failed:=False;
  SetMemoryManager(TestMM);
  try
    try VarArrayRedim(V,5) except on E: Exception do Failed:=True end;
  finally SetMemoryManager(SavedMM) end;
  Check(Refused and Failed,'failed growth reported');
  Check((VarArrayHighBound(V,1)=1) and (Integer(V[0])=73),'failed growth preserves shape and cells');
  Refused:=False;
  SetMemoryManager(TestMM);
  try VarArrayRedim(V,0) finally SetMemoryManager(SavedMM) end;
  Check(Refused and (VarArrayHighBound(V,1)=0) and (Integer(V[0])=73),'logical shrink retains capacity on refusal');
  VarArrayRedim(V,5);
  Check((Integer(V[0])=73) and (Integer(V[1])=0),'retry after allocation refusal');
end;
{$ifend}
begin
  CheckTable(-2,5);
  CheckTable(0,0);
  CheckCube;
  CheckLocks;
  CheckManaged;
  CheckEmptyAndByRef;
{$ifdef FPC}
  CheckVariantArrayCopies;
{$endif}
{$if defined(FPC) and defined(UNIX)}
  CheckCopyFailure;
  CheckResizeFailure(False);
  CheckResizeFailure(True);
{$ifend}
  WriteLn('VARIANT_ARRAY_COORDINATES_PASS');
end.
