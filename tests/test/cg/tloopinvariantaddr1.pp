{ %OPT=-O3 }

program tloopinvariantaddr1;

{$mode delphi}
{$R-}{$Q-}

uses
  SysUtils;

type
  TCounter = record
    Value: Int64;
    Padding: array[0..7] of Int64;
  end;

  TWorker = class
  private
    FIndex: Integer;
  public
    procedure Bump(Count: Integer);
    procedure BumpChangingIndex(Count: Integer);
    procedure BumpThroughAlias(Count: Integer);
    procedure BumpThroughPointer(Count: Integer);
    procedure BumpChecked(Count: Integer);
  end;

var
  Counters: array[0..1] of TCounter;

function SumGuardedStaticArray(FirstIndex, LastIndex: Integer): Integer;
const
  Values: array[0..15] of Integer =
    (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16);
var
  I: Integer;
begin
  Result := 0;
  for I := FirstIndex to LastIndex do
    If (I >= Low(Values)) and (I <= High(Values)) then
      Inc(Result, Values[I]);
end;

function SumGuardedStaticArrayBackward(FirstIndex,
  LastIndex: Integer): Integer;
const
  Values: array[0..15] of Integer =
    (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16);
var
  I: Integer;
begin
  Result := 0;
  for I := LastIndex downto FirstIndex do
    If (I >= Low(Values)) and (I <= High(Values)) then
      Inc(Result, Values[I]);
end;

procedure TWorker.Bump(Count: Integer);
var
  I: Integer;
begin
  { INVARIANT_ADDRESS_LOOP_BEGIN }
  for I := 1 to Count do
    Inc(Counters[FIndex].Value);
  { INVARIANT_ADDRESS_LOOP_END }
end;

procedure TWorker.BumpChangingIndex(Count: Integer);
var
  I: Integer;
begin
  for I := 1 to Count do
  begin
    Inc(Counters[FIndex].Value);
    FIndex := 1 - FIndex;
  end;
end;

procedure TWorker.BumpThroughAlias(Count: Integer);
var
  Alias: TWorker;
  I: Integer;
begin
  Alias := Self;
  for I := 1 to Count do
  begin
    Inc(Counters[FIndex].Value);
    Alias.FIndex := 1 - Alias.FIndex;
  end;
end;

procedure TWorker.BumpThroughPointer(Count: Integer);
var
  I: Integer;
  IndexPointer: PInteger;
begin
  IndexPointer := @FIndex;
  for I := 1 to Count do
  begin
    Inc(Counters[FIndex].Value);
    IndexPointer^ := 1 - IndexPointer^;
  end;
end;

{$R+}
procedure TWorker.BumpChecked(Count: Integer);
var
  I: Integer;
begin
  for I := 1 to Count do
    Inc(Counters[FIndex].Value);
end;
{$R-}

var
  Worker: TWorker;
  RangeRaised: Boolean;
begin
  FillChar(Counters, SizeOf(Counters), 0);
  If SumGuardedStaticArray(-1100, 1100) <> 136 then
    Halt(7);
  If SumGuardedStaticArrayBackward(-1100, 1100) <> 136 then
    Halt(8);
  Worker := TWorker.Create;
  try
    Worker.FIndex := 1;
    Worker.Bump(0);
    Worker.Bump(3);
    If (Counters[0].Value <> 0) or (Counters[1].Value <> 3) then
      Halt(1);

    Worker.FIndex := 0;
    Worker.BumpChangingIndex(4);
    If (Counters[0].Value <> 2) or (Counters[1].Value <> 5) then
      Halt(2);

    Worker.FIndex := 0;
    Worker.BumpThroughAlias(4);
    If (Counters[0].Value <> 4) or (Counters[1].Value <> 7) then
      Halt(4);

    Worker.FIndex := 0;
    Worker.BumpThroughPointer(4);
    If (Counters[0].Value <> 6) or (Counters[1].Value <> 9) then
      Halt(5);

    Worker.FIndex := 7;
    Worker.BumpChecked(0);
    RangeRaised := False;
    try
      Worker.BumpChecked(1);
    except
      on ERangeError do
        RangeRaised := True;
    end;
    If not RangeRaised then
      Halt(6);
  finally
    Worker.Free;
  end;
end.
