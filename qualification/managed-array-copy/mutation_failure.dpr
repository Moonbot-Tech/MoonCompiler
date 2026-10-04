program mutation_failure;
{$ifdef FPC}{$mode delphiunicode}{$endif}
{$APPTYPE CONSOLE}

uses
  {$ifdef FPC}mormot.core.fpcx64mm,{$endif}
  SysUtils, Variants;

type
  ERefused = class(Exception);
  TCounter = class(TObject, IInterface)
    Refs: Integer;
    function QueryInterface({$ifdef FPC}constref{$else}const{$endif} IID: TGUID; out Obj): HResult; {$ifdef MSWINDOWS}stdcall{$else}cdecl{$endif};
    function _AddRef: Integer; {$ifdef MSWINDOWS}stdcall{$else}cdecl{$endif};
    function _Release: Integer; {$ifdef MSWINDOWS}stdcall{$else}cdecl{$endif};
  end;
  TPair = record
    First, Second: IInterface;
  end;
  TStaticPair = array[0..1] of IInterface;
  TProbeVariant = class(TCustomVariantType)
    procedure Clear(var V: TVarData); override;
    procedure Copy(var Dest: TVarData; const Source: TVarData; const Indirect: Boolean); override;
  end;

var
  Calls, FailAt, Tokens, NextToken, Checks, Occupied: Integer;
  TokenLive: array[1..256] of Boolean;
  VariantType: TProbeVariant;
  AfterWrite: Boolean;

procedure Check(Value: Boolean; const Name: string);
begin
  Inc(Checks);
  If not Value then begin
    Writeln('FAIL ', Name);
    Halt(1);
  end;
end;

procedure BeforeCopy;
begin
  Inc(Calls);
  If Calls = FailAt then
    raise ERefused.Create('copy refused');
end;

function TCounter.QueryInterface({$ifdef FPC}constref{$else}const{$endif} IID: TGUID; out Obj): HResult; {$ifdef MSWINDOWS}stdcall{$else}cdecl{$endif};
begin
  Result := E_NOINTERFACE;
end;

function TCounter._AddRef: Integer; {$ifdef MSWINDOWS}stdcall{$else}cdecl{$endif};
begin
  BeforeCopy;
  Inc(Refs);
  Result := Refs;
end;

function TCounter._Release: Integer; {$ifdef MSWINDOWS}stdcall{$else}cdecl{$endif};
begin
  Dec(Refs);
  Result := Refs;
end;

procedure TProbeVariant.Clear(var V: TVarData);
begin
  Check((V.VInteger > 0) and TokenLive[V.VInteger], 'Variant releases an owned token once');
  TokenLive[V.VInteger] := False;
  Dec(Tokens);
  V.VType := varEmpty;
end;

procedure TProbeVariant.Copy(var Dest: TVarData; const Source: TVarData; const Indirect: Boolean);
begin
  If Indirect then
    RaiseInvalidOp;
  If not AfterWrite then
    BeforeCopy;
  Inc(NextToken);
  Inc(Tokens);
  TokenLive[NextToken] := True;
  Dest.VType := VarType;
  Dest.VInteger := NextToken;
  If AfterWrite then
    BeforeCopy;
end;

procedure Probe(Kind, Operation, Failure: Integer);
var
  A, B: TArray<IInterface>;
  R, S: TArray<TPair>;
  P, Q: TArray<TStaticPair>;
  V, W: TArray<Variant>;
  Item: TCounter;
  I, InitialRefs, InitialLength, ResultLength, ExpectedLength: Integer;
  Caught: Boolean;
  {$ifdef FPC}BeforeHeap, AfterHeap: TMMFragmentationStatus;{$endif}
begin
  {$ifdef FPC}BeforeHeap := CurrentHeapFragmentationStatus;{$endif}
  Item := TCounter.Create;
  FailAt := 0;
  NextToken := 0;
  case Kind of
    0: begin
      SetLength(A, 4);
      for I := 0 to 3 do
        If (Occupied = 0) or ((Occupied = 1) and (I = 0)) then
          A[I] := Item;
      If Operation in [0, 3, 7] then
        B := A;
    end;
    1: begin
      SetLength(R, 4);
      for I := 0 to 3 do begin
        R[I].First := Item;
        R[I].Second := Item;
      end;
      If Operation in [0, 3, 7] then
        S := R;
    end;
    2: begin
      SetLength(P, 4);
      for I := 0 to 3 do begin
        P[I][0] := Item;
        P[I][1] := Item;
      end;
      If Operation in [0, 3, 7] then
        Q := P;
    end;
    3: begin
      SetLength(V, 4);
      for I := 0 to 3 do begin
        Inc(NextToken);
        Inc(Tokens);
        TokenLive[NextToken] := True;
        TVarData(V[I]).VType := VariantType.VarType;
        TVarData(V[I]).VInteger := NextToken;
      end;
      If Operation in [0, 3, 7] then
        W := V;
    end;
  end;
  InitialRefs := Item.Refs + Tokens;
  InitialLength := 0;
  If Operation in [0, 3, 7] then
    InitialLength := 4;
  ExpectedLength := 0;
  case Operation of
    0: ExpectedLength := 3;
    1, 3: ExpectedLength := 8;
    2: ExpectedLength := 12;
    4: ExpectedLength := 8;
    5: ExpectedLength := 12;
    6, 7: ExpectedLength := 5;
  end;
  Calls := 0;
  FailAt := Failure;
  Caught := False;
  try
    case Kind of
      0: case Operation of
        0: Delete(B, 1, 1);
        1, 3: B := A + A;
        2: B := A + A + A;
        4: A := A + A;
        5: A := A + A + A;
        6: Insert(A[0], A, 2);
        7: Insert(A[0], B, 2);
      end;
      1: case Operation of
        0: Delete(S, 1, 1);
        1, 3: S := R + R;
        2: S := R + R + R;
        4: R := R + R;
        5: R := R + R + R;
        6: Insert(R[0], R, 2);
        7: Insert(R[0], S, 2);
      end;
      2: case Operation of
        0: Delete(Q, 1, 1);
        1, 3: Q := P + P;
        2: Q := P + P + P;
        4: P := P + P;
        5: P := P + P + P;
        6: Insert(P[0], P, 2);
        7: Insert(P[0], Q, 2);
      end;
      3: case Operation of
        0: Delete(W, 1, 1);
        1, 3: W := V + V;
        2: W := V + V + V;
        4: V := V + V;
        5: V := V + V + V;
        6: Insert(V[0], V, 2);
        7: Insert(V[0], W, 2);
      end;
    end;
  except
    on ERefused do
      Caught := True;
  end;
  FailAt := 0;
  Check(Caught = ((Failure > 0) and (Calls >= Failure)), 'exception reaches the caller');
  If Operation in [4, 5, 6] then
    InitialLength := 4;
  case Kind of
    0: If Operation in [4, 5, 6] then ResultLength := Length(A) else ResultLength := Length(B);
    1: If Operation in [4, 5, 6] then ResultLength := Length(R) else ResultLength := Length(S);
    2: If Operation in [4, 5, 6] then ResultLength := Length(P) else ResultLength := Length(Q);
    3: If Operation in [4, 5, 6] then ResultLength := Length(V) else ResultLength := Length(W);
  end;
  If Caught then begin
    Check(ResultLength = InitialLength, 'failed copy keeps the old length');
    Check(Item.Refs + Tokens = InitialRefs, 'failed copy returns acquired references');
  end else
    Check(ResultLength = ExpectedLength, 'successful operation length');
  { Reading the source after an append failure catches a stale carrier, even
    if its freed header happened to retain the old length. }
  case Kind of
    0: Check(((A[0] <> nil) = (Occupied <> 2)) and ((A[3] <> nil) = (Occupied = 0)), 'interface source survived');
    1: Check((R[0].First <> nil) and (R[3].Second <> nil), 'record source survived');
    2: Check((P[0][0] <> nil) and (P[3][1] <> nil), 'static array source survived');
    3: Check(TokenLive[TVarData(V[0]).VInteger] and TokenLive[TVarData(V[3]).VInteger], 'Variant source survived');
  end;
  A := nil;
  B := nil;
  R := nil;
  S := nil;
  P := nil;
  Q := nil;
  V := nil;
  W := nil;
  Check((Item.Refs = 0) and (Tokens = 0), 'all references returned');
  Item.Free;
  {$ifdef FPC}
  AfterHeap := CurrentHeapFragmentationStatus;
  Check(BeforeHeap.LiveSmallBytes + BeforeHeap.LiveMediumBytes + BeforeHeap.LiveLargeBytes =
    AfterHeap.LiveSmallBytes + AfterHeap.LiveMediumBytes + AfterHeap.LiveLargeBytes, 'all carriers returned');
  {$endif}
end;

{$ifdef FPC}
var
  OriginalManager: TMemoryManager;
  RefusedCarrier: Pointer;

function RefuseReallocation(var P: Pointer; Size: PtrUInt): Pointer;
begin
  If (RefusedCarrier <> nil) and (P = RefusedCarrier) then begin
    RefusedCarrier := nil;
    raise ERefused.Create('reallocation refused');
  end;
  Result := OriginalManager.ReallocMem(P, Size);
end;
{$endif}

procedure ProbeUniqueInsert;
var
  A: TArray<IInterface>;
  Items: array[0..3] of TCounter;
  Expected: array[0..3] of Pointer;
  Source, Position, I, OldIndex, Failure: Integer;
  Before: Pointer;
  Caught: Boolean;
  {$ifdef FPC}Manager: TMemoryManager;{$endif}
begin
  for Source := 0 to 3 do
    for Position := 0 to 4 do
      for Failure := 0 to {$ifdef FPC}2{$else}1{$endif} do begin
        FailAt := 0;
        SetLength(A, 4);
        for I := 0 to 3 do begin
          Items[I] := TCounter.Create;
          A[I] := Items[I];
          Expected[I] := Pointer(A[I]);
        end;
        Before := Pointer(A);
        Calls := 0;
        If Failure = 1 then
          FailAt := 1;
        {$ifdef FPC}
        GetMemoryManager(OriginalManager);
        Manager := OriginalManager;
        If Failure = 2 then begin
          RefusedCarrier := Before - 2 * SizeOf(NativeInt);
          Manager.ReallocMem := RefuseReallocation;
          SetMemoryManager(Manager);
        end;
        {$endif}
        Caught := False;
        try
          try
            Insert(A[Source], A, Position);
          except
            on ERefused do
              Caught := True;
          end;
        finally
          {$ifdef FPC}SetMemoryManager(OriginalManager);{$endif}
          FailAt := 0;
        end;
        Check(Caught = (Failure <> 0), 'unique Insert reports acquisition or allocation failure');
        If Caught then begin
          Check((Pointer(A) = Before) and (Length(A) = 4), 'unique Insert failure keeps its carrier');
          for I := 0 to 3 do begin
            Check(Pointer(A[I]) = Expected[I], 'rollback does not clear the source');
            Check(Items[I].Refs = 1, 'rollback releases only the extra reference');
          end;
        end else begin
          Check(Length(A) = 5, 'unique Insert grows by one');
          for I := 0 to 4 do begin
            If I = Position then
              OldIndex := Source
            else If I < Position then
              OldIndex := I
            else
              OldIndex := I - 1;
            Check(Pointer(A[I]) = Expected[OldIndex], 'aliased Insert preserves element order');
          end;
        end;
        A := nil;
        for I := 0 to 3 do begin
          Check(Items[I].Refs = 0, 'unique Insert returns every reference');
          Items[I].Free;
        end;
      end;
end;

var
  Kind, Operation, Failure: Integer;
begin
  VariantType := TProbeVariant.Create;
  for Kind := 0 to 3 do
    for Operation := 0 to 7 do
      for Failure := 0 to 3 do begin
        AfterWrite := False;
        Occupied := 0;
        Probe(Kind, Operation, Failure);
        If Kind = 0 then
          for Occupied := 1 to 2 do
            Probe(Kind, Operation, Failure);
        If Kind = 3 then begin
          AfterWrite := True;
          Probe(Kind, Operation, Failure);
        end;
      end;
  VariantType.Free;
  ProbeUniqueInsert;
  Writeln('MUTATION_FAILURE_PASS ', Checks);
end.
