program dynarray_setlength_paths_semantic;

{$ifdef FPC}
  {$mode delphi}
{$endif}

{ SetLength of a dynamic array has two routines behind it: the transactional one for records,
  objects and static arrays, which may carry a custom Initialize or Assign operator, and the
  straight one for every other element type (numbers, strings, interfaces, dynamic arrays).
  Every element kind goes through the same situations here - fresh, growing, shrinking, growing
  while shared, shrinking while shared - and must end with the right contents, the right reference
  counts and the right number of operator calls, whichever routine served it.
  Interfaces run user code as well (_AddRef, _Release) and no routine rolls that back; what does
  hold is checked at the end: when _AddRef raises in the middle of the copy of a shared array, both
  arrays are as they were. }

uses
  {$ifdef FPC}
  mormot.core.fpcx64mm,
  {$ifdef UNIX}cthreads,cwstring,{$endif UNIX}
  {$endif}
  SysUtils;

type
  TPlainRecord = record      // managed field, no operator: a record all the same, the transactional routine
    Name: string;
    Value: Integer;
  end;

  TInitRecord = record       // custom Initialize
    Value: Integer;
    class var Initialized, Finalized: Integer;
    class operator Initialize(out Dest: TInitRecord);
    class operator Finalize(var Dest: TInitRecord);
  end;

  TAssignRecord = record     // custom Assign: runs when a shared array is copied
    Value: Integer;
    class var Assigned_: Integer;
    class operator Assign(var Dest: TAssignRecord; const [ref] Source: TAssignRecord);
  end;

  TInitPair = array[0..1] of TInitRecord; // a static array of custom records is a custom element too

  TCounted = class(TInterfacedObject)
  public
    class var Alive: Integer;
    constructor Create;
    destructor Destroy; override;
  end;

  ERefused = class(Exception);

  // an interface whose _AddRef raises once it is armed: user code inside SetLength
  TRefusing = class(TObject, IInterface)
  public
    class var Armed: Boolean;
    class var Count: Integer;
    function QueryInterface({$ifdef FPC}constref{$else}const{$endif} IID: TGUID; out Obj): HResult; {$ifdef MSWINDOWS}stdcall{$else}cdecl{$endif};
    function _AddRef: Integer; {$ifdef MSWINDOWS}stdcall{$else}cdecl{$endif};
    function _Release: Integer; {$ifdef MSWINDOWS}stdcall{$else}cdecl{$endif};
  end;

class operator TInitRecord.Initialize(out Dest: TInitRecord);
begin
  Inc(Initialized);
  Dest.Value := 7;
end;

class operator TInitRecord.Finalize(var Dest: TInitRecord);
begin
  Inc(Finalized);
end;

class operator TAssignRecord.Assign(var Dest: TAssignRecord; const [ref] Source: TAssignRecord);
begin
  Inc(Assigned_);
  Dest.Value := Source.Value + 1000;
end;

constructor TCounted.Create;
begin
  inherited Create;
  Inc(Alive);
end;

destructor TCounted.Destroy;
begin
  Dec(Alive);
  inherited Destroy;
end;

function TRefusing.QueryInterface({$ifdef FPC}constref{$else}const{$endif} IID: TGUID; out Obj): HResult; {$ifdef MSWINDOWS}stdcall{$else}cdecl{$endif};
begin
  Result := E_NOINTERFACE;
end;

function TRefusing._AddRef: Integer; {$ifdef MSWINDOWS}stdcall{$else}cdecl{$endif};
begin
  if Armed then
    raise ERefused.Create('no more references');
  Inc(Count);
  Result := Count;
end;

function TRefusing._Release: Integer; {$ifdef MSWINDOWS}stdcall{$else}cdecl{$endif};
begin
  Dec(Count);
  Result := Count;
end;

procedure Check(Condition: Boolean; const Name: string);
begin
  if not Condition then
  begin
    WriteLn('FAIL ', Name);
    Halt(1);
  end;
end;

procedure Doubles;
var
  A, B: array of Double;
  I: Integer;
begin
  SetLength(A, 64);
  for I := 0 to 63 do
    Check(A[I] = 0, 'double fresh zero');
  for I := 0 to 63 do
    A[I] := I + 0.5;
  SetLength(A, 200);
  Check((A[63] = 63.5) and (A[64] = 0) and (A[199] = 0), 'double grow');
  SetLength(A, 10);
  Check((Length(A) = 10) and (A[9] = 9.5), 'double shrink');
  B := A;
  SetLength(A, 300);
  Check((Length(B) = 10) and (B[9] = 9.5) and (A[9] = 9.5) and (A[10] = 0) and (A[299] = 0), 'double grow shared');
  A[0] := -1;
  Check(B[0] = 0.5, 'double shared copy is unique');
  B := A;
  SetLength(A, 5);
  Check((Length(B) = 300) and (Length(A) = 5) and (A[4] = 4.5), 'double shrink shared');
  SetLength(A, 0);
  Check(A = nil, 'double zero length');
end;

procedure Strings;
var
  A, B: array of string;
  S: string;
  I: Integer;
begin
  S := 'value' + IntToStr(Random(10)); // on the heap, with a reference count
  SetLength(A, 16);
  for I := 0 to 15 do
    Check(A[I] = '', 'string fresh empty');
  for I := 0 to 15 do
    A[I] := S;
  Check(StringRefCount(S) = 17, 'string references after fill');
  SetLength(A, 40);
  Check((A[15] = S) and (A[16] = '') and (A[39] = ''), 'string grow');
  SetLength(A, 4);
  Check(StringRefCount(S) = 5, 'string shrink finalizes the tail');
  B := A;
  SetLength(A, 8);
  Check((Length(B) = 4) and (A[3] = S) and (A[4] = '') and (StringRefCount(S) = 9), 'string grow shared adds references');
  B := A;
  SetLength(A, 2);
  Check((Length(B) = 8) and (StringRefCount(S) = 7), 'string shrink shared');
  A := nil;
  B := nil;
  Check(StringRefCount(S) = 1, 'string references all returned');
end;

procedure Interfaces;
var
  A, B: array of IInterface;
  I: Integer;
begin
  SetLength(A, 8);
  for I := 0 to 7 do
    A[I] := TCounted.Create;
  Check(TCounted.Alive = 8, 'interface objects alive');
  SetLength(A, 20);
  Check((A[8] = nil) and (TCounted.Alive = 8), 'interface grow');
  SetLength(A, 3);
  Check(TCounted.Alive = 3, 'interface shrink releases');
  B := A;
  SetLength(A, 6);
  Check((TCounted.Alive = 3) and (A[2] = B[2]) and (A[3] = nil), 'interface grow shared');
  B := nil;
  A := nil;
  Check(TCounted.Alive = 0, 'interface all released');
end;

procedure PlainRecords;
var
  A, B: array of TPlainRecord;
  S: string;
begin
  S := 'name' + IntToStr(Random(10));
  SetLength(A, 5);
  Check((A[4].Name = '') and (A[4].Value = 0), 'plain record fresh');
  A[0].Name := S;
  A[0].Value := 1;
  SetLength(A, 50);
  Check((A[0].Name = S) and (A[49].Name = '') and (A[49].Value = 0), 'plain record grow');
  B := A;
  SetLength(A, 60);
  Check((StringRefCount(S) = 3) and (A[0].Value = 1) and (Length(B) = 50), 'plain record grow shared');
  B := A;
  SetLength(A, 1);
  Check((Length(B) = 60) and (A[0].Name = S), 'plain record shrink shared');
  A := nil;
  B := nil;
  Check(StringRefCount(S) = 1, 'plain record references returned');
end;

procedure InitRecords;
var
  A, B: array of TInitRecord;
  P: array of TInitPair;
begin
  TInitRecord.Initialized := 0;
  TInitRecord.Finalized := 0;
  SetLength(A, 6);
  Check((TInitRecord.Initialized = 6) and (A[5].Value = 7), 'custom initialize fresh');
  A[0].Value := 1;
  SetLength(A, 10);
  Check((TInitRecord.Initialized = 10) and (A[0].Value = 1) and (A[9].Value = 7), 'custom initialize grows new items only');
  SetLength(A, 4);
  Check(TInitRecord.Finalized = 6, 'custom finalize on shrink');
  B := A;
  SetLength(A, 5);
  Check((Length(B) = 4) and (A[0].Value = 1) and (A[4].Value = 7), 'custom initialize grow shared');
  A := nil;
  B := nil;
  // 11 items were initialized; the 4 copied ones live in both arrays and are finalized in both
  // (a copy is not an Initialize): 6 on the shrink + 5 + 4
  Check((TInitRecord.Initialized = 11) and (TInitRecord.Finalized = 15), 'custom initialize and finalize counts');
  TInitRecord.Initialized := 0;
  TInitRecord.Finalized := 0;
  SetLength(P, 3);
  Check((TInitRecord.Initialized = 6) and (P[2][1].Value = 7), 'static array of custom records fresh');
  SetLength(P, 5);
  Check(TInitRecord.Initialized = 10, 'static array of custom records grow');
  P := nil;
  Check(TInitRecord.Finalized = 10, 'static array of custom records finalized');
end;

procedure AssignRecords;
var
  A, B: array of TAssignRecord;
begin
  TAssignRecord.Assigned_ := 0;
  SetLength(A, 4);
  A[0].Value := 1;
  SetLength(A, 9);
  Check((TAssignRecord.Assigned_ = 0) and (A[0].Value = 1), 'unique growth moves, it does not assign');
  B := A;
  SetLength(A, 12);
  Check((TAssignRecord.Assigned_ = 9) and (A[0].Value = 1001) and (B[0].Value = 1), 'shared growth copies with Assign');
  B := A;
  SetLength(A, 2);
  Check((TAssignRecord.Assigned_ = 11) and (Length(B) = 12), 'shared shrink copies the kept items with Assign');
end;

procedure Nested;
var
  A, B: array of array of string;
  S: string;
begin
  S := 'cell' + IntToStr(Random(10));
  SetLength(A, 3, 4);
  Check((Length(A) = 3) and (Length(A[2]) = 4) and (A[2][3] = ''), 'nested fresh');
  A[1][1] := S;
  SetLength(A, 5, 6);
  Check((Length(A[4]) = 6) and (Length(A[1]) = 6) and (A[1][1] = S) and (A[1][5] = ''), 'nested grow');
  B := A;
  SetLength(A, 2, 2);
  Check((Length(B) = 5) and (Length(A) = 2) and (A[1][1] = S), 'nested shrink shared');
  A := nil;
  B := nil;
  Check(StringRefCount(S) = 1, 'nested references returned');
end;

procedure RaisingAddRef;
var
  A, B: array of IInterface;
  Item: TRefusing;
  Raised: Boolean;
  I: Integer;
begin
  Item := TRefusing.Create;
  try
    SetLength(A, 6);
    for I := 0 to 5 do
      A[I] := Item;
    B := A;
    TRefusing.Armed := True;
    Raised := False;
    try
      SetLength(A, 10); // a shared array: the copy takes a reference of every item
    except
      on ERefused do
        Raised := True;
    end;
    TRefusing.Armed := False;
    Check(Raised, 'raising _AddRef reaches the caller');
    Check((Length(A) = 6) and (Length(B) = 6) and (Pointer(A) = Pointer(B)), 'raising _AddRef leaves both arrays as they were');
    for I := 0 to 5 do
      Check(A[I] = IInterface(Item), 'raising _AddRef keeps the items');
    A := nil;
    B := nil;
  finally
    Item.Free;
  end;
end;

begin
  Doubles;
  Strings;
  Interfaces;
  RaisingAddRef;
  PlainRecords;
  InitRecords;
  AssignRecords;
  Nested;
  WriteLn('DYNARRAY_SETLENGTH_PATHS_SEMANTIC_OK');
end.
