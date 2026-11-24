{ Exceptions from the hidden enumeration protocol itself must retire its receiver. }

type
  IBreadthCursor = interface
    ['{99E37043-A12C-404D-A66E-24128361FBC8}']
    function MoveNext: Boolean;
    function Read: TCrossEntry;
    property Current: TCrossEntry read Read;
  end;

  TBreadthCursor = class(TInterfacedObject, IBreadthCursor)
  private
    FPosition, FFailurePoint: Integer;
  public
    class var Releases, Calls: Integer;
    constructor Create(FailurePoint: Integer);
    destructor Destroy; override;
    function MoveNext: Boolean;
    function Read: TCrossEntry;
  end;

  TBreadthCursorSource = record
    FailurePoint: Integer;
    function GetEnumerator: IBreadthCursor;
  end;

constructor TBreadthCursor.Create(FailurePoint: Integer);
begin
  inherited Create;
  FFailurePoint := FailurePoint;
end;

destructor TBreadthCursor.Destroy;
begin
  Inc(Releases);
  inherited;
end;

function TBreadthCursor.MoveNext: Boolean;
begin
  Inc(FPosition);
  Calls := Calls * 10 + 1;
  If (FPosition = 2) and (FFailurePoint = 1) then
    raise EAbort.Create('move');
  Result := FPosition <= 2;
end;

function TBreadthCursor.Read: TCrossEntry;
begin
  Calls := Calls * 10 + 2;
  If (FPosition = 2) and (FFailurePoint = 2) then
    raise EAbort.Create('read');
  Result.Code := FPosition * 47;
  Result.Text := AnsiString('row' + IntToStr(FPosition));
end;

function TBreadthCursorSource.GetEnumerator: IBreadthCursor;
begin
  Result := TBreadthCursor.Create(FailurePoint);
end;

procedure BreadthWalkCursor(FailurePoint: Integer; out Seen: AnsiString; out Sum: Int64; out Fault: string);
var
  Source: TBreadthCursorSource;
  Item: TCrossEntry;
begin
  Source.FailurePoint := FailurePoint;
  Sum := 0;
  Fault := '';
  try
    for Item in Source do begin
      Seen := Seen + Item.Text;
      Sum := Sum + Item.Code;
    end;
  except
    on E: EAbort do Fault := E.Message;
  end;
end;

procedure RunBreadthEnumeratorFailures;
const
  Traces: array[0..2] of Integer = (12121, 121, 1212);
  Visible: array[0..2] of AnsiString = ('row1row2', 'row1', 'row1');
  Sums: array[0..2] of Int64 = (141, 47, 47);
  Faults: array[0..2] of string = ('', 'move', 'read');
var
  I: Integer;
  Seen: AnsiString;
  Sum: Int64;
  Fault: string;
begin
  TBreadthCursor.Releases := 0;
  for I := Low(Traces) to High(Traces) do begin
    TBreadthCursor.Calls := 0;
    BreadthWalkCursor(Integer(OpaqueI(I)), Seen, Sum, Fault);
    Check((TBreadthCursor.Calls = Traces[I]) and (Fault = Faults[I]), 'breadth-interface-enumerator-hidden-fault-origin');
    Check((Seen = Visible[I]) and (Sum = Sums[I]), 'breadth-interface-enumerator-only-publishes-complete-items');
    Check(TBreadthCursor.Releases = I + 1, 'breadth-interface-enumerator-receiver-released-on-each-exit');
    Mix(UInt64(TBreadthCursor.Calls));
  end;
end;
