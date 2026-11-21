program record_copy_probe;
{$APPTYPE CONSOLE}
{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$INLINE ON}
uses SysUtils, Generics.Collections, System.Diagnostics;
type
  TRec = record
    V: array[0..7] of UInt64;
  end;
  TRecList = TList<TRec>;
  THolder = class
    Value: TRec;
  end;
var
  G: TRec;
  Sink: UInt64;
  GetterCalls: Integer;
  IndexValue: Integer;
  Checks: Integer;
  FailGetter: Boolean;
  FailIndex: Boolean;

procedure Check(Condition: Boolean; const Name: string);
begin
  Inc(Checks);
  if not Condition then
  begin
    Writeln('FAIL ', Name);
    Halt(10);
  end;
end;

function GetList(L: TRecList): TRecList;
begin
  Inc(GetterCalls);
  if FailGetter then raise Exception.Create('getter');
  Result := L;
end;

function GetIndex: Integer;
begin
  Inc(GetterCalls);
  if FailIndex then raise Exception.Create('index getter');
  Result := IndexValue;
end;

function SameRecord(const A, B: TRec): Boolean;
begin
  Result := CompareMem(@A, @B, SizeOf(TRec));
end;

function Digest(const R: TRec): UInt64;
var I: Integer;
begin
  Result := 0;
  for I := 0 to 7 do
    Result := Result + R.V[I];
end;

function PlainReturn(const R: TRec): TRec;
begin
  Result := R;
end;
function InlineReturn(const R: TRec): TRec; inline;
begin
  Result := R;
end;

function ItemsLocal(L: TRecList; K: Integer): UInt64;
var F: TRec;
begin
  F := L.Items[K];
  Result := Digest(F);
end;

procedure ItemsVar(L: TRecList; K: Integer; var F: TRec);
begin
  F := L.Items[K];
end;

procedure ItemsField(L: TRecList; K: Integer; H: THolder);
begin
  H.Value := L.Items[K];
end;

procedure ItemsGlobal(L: TRecList; K: Integer);
begin
  G := L.Items[K];
end;

function ItemsResult(L: TRecList; K: Integer): TRec;
begin
  Result := L.Items[K];
end;

function DirectLocal(L: TRecList; K: Integer): UInt64;
var F: TRec;
begin
  if (K < 0) or (K >= L.Count) then
    raise EArgumentOutOfRangeException.Create('index');
  F := L.List[K];
  Result := Digest(F);
end;

procedure InlineVar(const R: TRec; var F: TRec);
begin
  F := InlineReturn(R);
end;

procedure ChainItems(L: TRecList; K: Integer; var F: TRec);
begin
  F := GetList(L).Items[K];
end;

procedure IndexItems(L: TRecList; var F: TRec);
begin
  F := L.Items[GetIndex];
end;

function InlineBranch(const R: TRec; Choose: Boolean): TRec; inline;
begin
  if Choose then Result := R else Result := G;
end;

procedure BranchVar(const R: TRec; Choose: Boolean; var F: TRec);
begin
  F := InlineBranch(R, Choose);
end;

procedure AssignRecord(const R: TRec; var F: TRec);
begin
  F := R;
end;

function GlobalValue: TRec; inline;
begin
  Result := G;
end;

function MutatingConsumer(const R: TRec): UInt64;
begin
  G.V[0] := 1000;
  Result := Digest(R);
end;

function SnapshotToCall: UInt64;
begin
  Result := MutatingConsumer(GlobalValue);
end;

function AliasReturn(const R: TRec): TRec;
begin
  Result := R;
  Result.V[0] := 999;
  Result.V[1] := R.V[0];
end;

function ThrowAfterWrite(const R: TRec): TRec;
begin
  Result := R;
  Result.V[0] := 999;
  raise Exception.Create('after write');
end;

procedure ThrowToVar(const R: TRec; var F: TRec);
begin
  F := ThrowAfterWrite(R);
end;

function PlainLocal(const R: TRec): UInt64;
var F: TRec;
begin
  F := PlainReturn(R);
  Result := Digest(F);
end;

procedure PlainVar(const R: TRec; var F: TRec);
begin
  F := PlainReturn(R);
end;

function PlainResult(const R: TRec): TRec;
begin
  Result := PlainReturn(R);
end;

var
  L: TRecList;
  H: THolder;
  R, F, Expected: TRec;
  I: Integer;
  Raised: Boolean;
  Started: Int64;
  Iterations: Integer;
  BenchCase: string;
begin
  if SizeOf(TRec) <> 64 then Halt(1);
  for I := 0 to 7 do R.V[I] := I + 1;
  L := TRecList.Create;
  H := THolder.Create;
  try
    L.Add(R);
    Sink := ItemsLocal(L, 0) + DirectLocal(L, 0);
    ItemsVar(L, 0, F);
    Sink := Sink + Digest(F);
    Check(SameRecord(F, R), 'var result');
    ItemsField(L, 0, H);
    Sink := Sink + Digest(H.Value);
    Check(SameRecord(H.Value, R), 'field result');
    ItemsGlobal(L, 0);
    Sink := Sink + Digest(G);
    Check(SameRecord(G, R), 'global result');
    F := ItemsResult(L, 0);
    Sink := Sink + Digest(F);
    Check(SameRecord(F, R), 'function result');
    InlineVar(R, F);
    Sink := Sink + Digest(F);
    Check(SameRecord(F, R), 'inline result');
    Sink := Sink + PlainLocal(R);
    PlainVar(R, F);
    Sink := Sink + Digest(F);
    Check(SameRecord(F, R), 'ordinary var result');
    F := PlainResult(R);
    Sink := Sink + Digest(F);
    Check(SameRecord(F, R), 'ordinary result forwarding');
    if Sink <> 360 then Halt(2);
    ChainItems(L, 0, F);
    Check(SameRecord(F, R), 'receiver call result');
    IndexItems(L, F);
    Check(SameRecord(F, R), 'index call result');
    if GetterCalls <> 2 then Halt(5);
    BranchVar(R, True, F);
    Check(SameRecord(F, R), 'conditional result true');
    G.V[7] := 1234;
    BranchVar(R, False, F);
    Check(SameRecord(F, G), 'conditional result false');
    AssignRecord(R, F);
    Check(SameRecord(F, R), 'record assignment');
    for I := -1 to 1 do
      if I <> 0 then
      begin
        F := R;
        Raised := False;
        try ItemsVar(L, I, F);
        except on E: EArgumentOutOfRangeException do Raised := True;
        end;
        Check(Raised and SameRecord(F, R), 'index rejects before destination write');
        Raised := False;
        try ChainItems(L, I, F);
        except on E: EArgumentOutOfRangeException do Raised := True;
        end;
        Check(Raised and SameRecord(F, R), 'receiver call retains index check');
        Raised := False;
        IndexValue := I;
        try IndexItems(L, F);
        except on E: EArgumentOutOfRangeException do Raised := True;
        end;
        IndexValue := 0;
        Check(Raised and SameRecord(F, R), 'index call retains index check');
      end;
    F := R;
    Raised := False;
    FailGetter := True;
    try ChainItems(L, 0, F);
    except on E: Exception do Raised := E.Message = 'getter';
    end;
    FailGetter := False;
    Check(Raised and SameRecord(F, R), 'receiver exception before destination write');
    Raised := False;
    FailIndex := True;
    try IndexItems(L, F);
    except on E: Exception do Raised := E.Message = 'index getter';
    end;
    FailIndex := False;
    Check(Raised and SameRecord(F, R), 'index exception before destination write');
    G := R;
    Check(SnapshotToCall = 36, 'const consumer reads snapshot');
    Check(G.V[0] = 1000, 'const consumer actually changes source');
    F := R;
    F := AliasReturn(F);
    Expected := R;
    Expected.V[0] := 999;
    Expected.V[1] := 1;
    Check(SameRecord(F, Expected), 'result cannot overwrite aliased input');
    F := R;
    Raised := False;
    try ThrowToVar(R, F);
    except on E: Exception do Raised := E.Message = 'after write';
    end;
    Check(Raised and SameRecord(F, R), 'function exception preserves var destination');
    Writeln('RECORD_COPY_PROBE_PASS ', Sink);
    Writeln('SEMANTIC_CHECKS ', Checks);
    if ParamCount <> 0 then
    begin
      Sink := 0;
      Iterations := 50000000;
      if ParamCount > 1 then Iterations := StrToInt(ParamStr(2));
      BenchCase := ParamStr(1);
      Started := TStopwatch.GetTimeStamp;
      if BenchCase = 'chain' then
        for I := 1 to Iterations do
        begin
          ChainItems(L, 0, F);
          Sink := Sink + F.V[0];
        end
      else if BenchCase = 'index' then
        for I := 1 to Iterations do
        begin
          IndexItems(L, F);
          Sink := Sink + F.V[0];
        end
      else if BenchCase = 'simple' then
        for I := 1 to Iterations do
        begin
          ItemsVar(L, 0, F);
          Sink := Sink + F.V[0];
        end
      else Halt(12);
      Writeln('BENCH ', TStopwatch.GetTimeStamp - Started, ' ', TStopwatch.Frequency, ' ', Sink);
      if Sink <> UInt64(Iterations) then Halt(11);
    end;
  finally
    H.Free;
    L.Free;
  end;
end.
