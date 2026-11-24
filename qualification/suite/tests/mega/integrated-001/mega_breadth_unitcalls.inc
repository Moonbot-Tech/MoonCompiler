{ A callback signature and its managed intermediates cross a compiled-unit inline boundary. }

type
  TBreadthUnitReceiver = class
    Calls: Integer;
    RejectSecond: Boolean;
    function Apply(const Input: TBreadthUnitStamp; Step: Int64; Scale: Double): TBreadthUnitStamp;
  end;

function TBreadthUnitReceiver.Apply(const Input: TBreadthUnitStamp; Step: Int64; Scale: Double): TBreadthUnitStamp;
begin
  Inc(Calls);
  If RejectSecond and (Calls = 2) then
    raise EAbort.Create('unit callback rejected');
  Result.Data := Input.Data * 2 + Step + Trunc(Scale * 8.0) + 29;
  Result.LabelText := Input.LabelText + ':' + AnsiChar(Ord('0') + Calls);
end;

procedure RunBreadthCompiledCallback;
var
  Receiver: TBreadthUnitReceiver;
  FromUnit, Current, Pending: TBreadthUnitStamp;
  Caught: Boolean;
begin
  Receiver := TBreadthUnitReceiver.Create;
  try
    FromUnit.Data := OpaqueI(50000000007);
    FromUnit.LabelText := 'input';
    Current := BreadthMapUnitStamp(FromUnit, OpaqueI(-9000000021), OpaqueD(1.75), Receiver.Apply);
    Check((Receiver.Calls = 2) and (Current.Data = 173000000049) and (Current.LabelText = 'input:1:2'),
      'breadth-compiled-unit-indirect-method-preserves-managed-intermediate');
    Check((FromUnit.Data = 50000000007) and (FromUnit.LabelText = 'input'), 'breadth-compiled-unit-preserves-original-record');
    Receiver.Calls := 0;
    Receiver.RejectSecond := True;
    Caught := False;
    try
      Pending := BreadthMapUnitStamp(FromUnit, OpaqueI(-9000000021), OpaqueD(1.75), Receiver.Apply);
      Current := Pending;
    except
      on E: EAbort do Caught := E.Message = 'unit callback rejected';
    end;
    Check(Caught and (Receiver.Calls = 2), 'breadth-compiled-unit-second-callback-unwinds-to-caller');
    Check((Current.Data = 173000000049) and (Current.LabelText = 'input:1:2'),
      'breadth-compiled-unit-unwind-keeps-previously-published-result');
    Mix(UInt64(Current.Data));
  finally
    Receiver.Free;
  end;
end;
