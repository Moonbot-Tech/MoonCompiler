{$if defined(HAS_ANON) and defined(HAS_INLINEVAR)}
{ Escaping closures retain different managed locals with the same spelling. }

type
  TBreadthScopedAction = reference to function(Delta: Integer): TCrossEntry;
  TBreadthScopedRecord = record
    Owner: IInterface;
    Value: TCrossEntry;
  end;
  TBreadthScopedString = record
    Text: UnicodeString;
    Owner: IInterface;
  end;

procedure BreadthMakeShadowedClosures(out RecordAction, TextAction: TBreadthScopedAction);
begin
  begin
    var Cell: TBreadthScopedRecord;
    Cell.Owner := TIntersectionOwner.Create;
    Cell.Value.Code := OpaqueI(70000000051);
    Cell.Value.Text := 'entry';
    RecordAction := function(Delta: Integer): TCrossEntry
      begin
        Inc(Cell.Value.Code, Delta);
        Cell.Value.Text := Cell.Value.Text + AnsiChar(Ord('a') + Delta);
        try
          Result := Cell.Value;
        finally
          Cell.Value.Text := Cell.Value.Text + '!';
        end;
        Check(Cell.Owner <> nil, 'breadth-shadowed-record-closure-still-owns-capture');
      end;
  end;
  begin
    var Cell: TBreadthScopedString;
    Cell.Owner := TIntersectionOwner.Create;
    Cell.Text := 'text';
    TextAction := function(Delta: Integer): TCrossEntry
      begin
        Cell.Text := Cell.Text + WideChar(Ord('A') + Delta);
        Result.Code := Length(Cell.Text) * 37;
        Result.Text := AnsiString(Cell.Text);
        Check(Cell.Owner <> nil, 'breadth-shadowed-text-closure-still-owns-capture');
      end;
  end;
end;

procedure BreadthExerciseShadowedClosures;
var
  Edit, Append: TBreadthScopedAction;
  First, Second, Current: TCrossEntry;
begin
  BreadthMakeShadowedClosures(Edit, Append);
  First := Edit(Integer(OpaqueI(1)));
  Check((First.Code = 70000000052) and (First.Text = 'entryb'), 'breadth-shadowed-closure-first-capture-keeps-result-copy');
  Second := Append(Integer(OpaqueI(5)));
  Check((Second.Code = 185) and (Second.Text = 'textF'), 'breadth-shadowed-closure-second-capture-has-own-layout');
  Current := Edit(Integer(OpaqueI(3)));
  Check((Current.Code = 70000000055) and (Current.Text = 'entryb!d') and (First.Text = 'entryb'),
    'breadth-shadowed-closure-retains-same-field-after-finally');
  Mix(UInt64(Current.Code));
  Current := Append(Integer(OpaqueI(7)));
  Check((Current.Code = 222) and (Current.Text = 'textFH') and (Second.Text = 'textF'),
    'breadth-shadowed-closure-retains-independent-managed-text');
  Mix(UInt64(Current.Code));
  Check(TIntersectionOwner.Destroyed = 0, 'breadth-shadowed-closures-hold-both-captures-after-maker-scope');
end;

procedure RunBreadthShadowedClosure;
begin
  TIntersectionOwner.Destroyed := 0;
  BreadthExerciseShadowedClosures;
  Check(TIntersectionOwner.Destroyed = 2, 'breadth-shadowed-closures-release-both-captures');
end;


function BreadthMakeHandlerClosure(var Finalizers: Integer): TBreadthScopedAction;
var
  Fault: TBreadthOwnedError;
begin
  Fault := TBreadthOwnedError.Create('from-handler');
  Fault.Owner := TIntersectionOwner.Create;
  Fault.Number := Integer(OpaqueI(-315));
  try
    try
      raise Fault;
    except
      on E: TBreadthOwnedError do begin
        var Cell: TBreadthScopedRecord;
        Cell.Owner := E.Owner;
        Cell.Value.Code := 17000000053 + E.Number;
        Cell.Value.Text := AnsiString(E.Message);
        Result := function(Delta: Integer): TCrossEntry
          begin
            Check(Cell.Owner <> nil, 'breadth-handler-closure-owns-exception-payload');
            Inc(Cell.Value.Code, Int64(Delta) * 107);
            Cell.Value.Text := Cell.Value.Text + AnsiChar(Ord('0') + Delta);
            Result := Cell.Value;
          end;
        Exit;
      end;
    end;
  finally
    Inc(Finalizers);
  end;
end;

procedure BreadthExerciseHandlerClosure;
var
  Read: TBreadthScopedAction;
  First, Second: TCrossEntry;
  Finalizers: Integer;
begin
  Finalizers := 0;
  Read := BreadthMakeHandlerClosure(Finalizers);
  Check((Finalizers = 1) and (ExceptObject = nil) and (TBreadthOwnedError.Destroyed = 1),
    'breadth-handler-closure-exit-cleans-handler-and-finally');
  Check(TIntersectionOwner.Destroyed = 0, 'breadth-handler-closure-payload-outlives-exception');
  First := Read(Integer(OpaqueI(3)));
  Second := Read(Integer(OpaqueI(7)));
  Check((First.Code = 17000000059) and (First.Text = 'from-handler3'), 'breadth-handler-closure-first-captured-value');
  Check((Second.Code = 17000000808) and (Second.Text = 'from-handler37'), 'breadth-handler-closure-mutates-retained-value');
  Mix(UInt64(Second.Code));
end;

procedure RunBreadthHandlerClosure;
begin
  TIntersectionOwner.Destroyed := 0;
  TBreadthOwnedError.Destroyed := 0;
  BreadthExerciseHandlerClosure;
  Check((TBreadthOwnedError.Destroyed = 1) and (TIntersectionOwner.Destroyed = 1),
    'breadth-handler-closure-releases-payload-separately-from-exception');
end;
{$ifend}
