{ An indexed property call uses one receiver and one evaluation per index
  while adapting a packed field, a virtual method and a VarRec consumer. }

type
  TBreadthIndexedCells = class
  private
    FData: packed record
      Guard: Byte;
      Item: Int64;
    end;
  protected
    function GetCell(Row: SmallInt; Col: Byte): Int64; virtual;
    procedure SetCell(Row: SmallInt; Col: Byte; Value: Int64); virtual;
  public
    Trace: Integer;
    property Cells[Row: SmallInt; Col: Byte]: Int64 read GetCell write SetCell; default;
  end;

  TBreadthSpecialCells = class(TBreadthIndexedCells)
  protected
    function GetCell(Row: SmallInt; Col: Byte): Int64; override;
  end;

function TBreadthIndexedCells.GetCell(Row: SmallInt; Col: Byte): Int64;
begin
  Trace := Trace * 10 + 2;
  Result := FData.Item + Row * 1024 + Col;
end;

procedure TBreadthIndexedCells.SetCell(Row: SmallInt; Col: Byte; Value: Int64);
begin
  Trace := Trace * 10 + 1;
  FData.Item := Value + Row * 1024 + Col;
end;

function TBreadthSpecialCells.GetCell(Row: SmallInt; Col: Byte): Int64;
begin
  Result := inherited GetCell(Row, Col) + 9;
  Trace := Trace * 10 + 3;
end;

function BreadthCountedReceiver(var Calls: Integer; Value: TBreadthIndexedCells): TBreadthIndexedCells;
begin
  Inc(Calls);
  Result := Value;
end;

function BreadthCountedIndex(var Calls: Integer; Value: Integer): Integer;
begin
  Inc(Calls);
  Result := Value;
end;

procedure BreadthConsumeIndexedCell(const Slots: array of const);
begin
  Check((Length(Slots) = 1) and (Slots[0].VType = vtInt64) and (Slots[0].VInt64^ = 72000003941),
    'breadth-indexed-property-passes-wide-cell-in-int64-argument-descriptor');
end;

procedure RunBreadthIndexedPropertyEffects;
var
  Cells: TBreadthIndexedCells;
  ReceiverCalls, RowCalls, ColumnCalls: Integer;
begin
  Cells := TBreadthSpecialCells.Create;
  try
    Cells.FData.Guard := $D7;
    ReceiverCalls := 0;
    RowCalls := 0;
    ColumnCalls := 0;
    BreadthCountedReceiver(ReceiverCalls, Cells)[SmallInt(BreadthCountedIndex(RowCalls, -309)),
      Byte(BreadthCountedIndex(ColumnCalls, 251))] := OpaqueI(72000320003);
    Check((ReceiverCalls = 1) and (RowCalls = 1) and (ColumnCalls = 1) and (Cells.Trace = 1),
      'breadth-indexed-property-assignment-evaluates-address-operands-once');
    BreadthConsumeIndexedCell([BreadthCountedReceiver(ReceiverCalls, Cells)
      [SmallInt(BreadthCountedIndex(RowCalls, 0)), Byte(BreadthCountedIndex(ColumnCalls, 94))]]);
    Check((ReceiverCalls = 2) and (RowCalls = 2) and (ColumnCalls = 2) and (Cells.Trace = 123),
      'breadth-indexed-property-argument-uses-derived-and-inherited-getter-once');
    Check(Cells.FData.Guard = $D7, 'breadth-indexed-property-preserves-packed-neighbor');
    Mix(UInt64(Cells.Trace));
  finally
    Cells.Free;
  end;
end;
