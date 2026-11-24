{ RTL consumers make argument width, callback payloads and exception frames observable. }

procedure RunBreadthFormattedArguments;
var
  Settings: TFormatSettings;
  Price, ParsedPrice: Currency;
  Text: string;
  ParsedRatio: Double;
begin
  Settings := Default(TFormatSettings);
  Settings.DecimalSeparator := ',';
  Settings.ThousandSeparator := '_';
  Price := OpaqueI(-94);
  Price := Price - 0.125;
  Text := Format('%d|%.3f|%.2f|%s', [OpaqueI(73000000039), Price, OpaqueD(7.25), UnicodeString('tag')], Settings);
  Check(Text = '73000000039|-94,125|7,25|tag', 'breadth-format-consumes-mixed-varrec-tags');
  ParsedPrice := 0;
  Check(TryStrToCurr(Copy(Text, 13, 7), ParsedPrice, Settings), 'breadth-format-currency-parse-with-explicit-settings');
  Check(ParsedPrice = -94.125, 'breadth-format-currency-roundtrip');
  ParsedRatio := 0;
  Check(TryStrToFloat(Copy(Text, 21, 4), ParsedRatio, Settings) and (ParsedRatio = 7.25),
    'breadth-format-float-roundtrip');
  Mix(DoubleBits(ParsedRatio));
end;

type
  TBreadthSortValue = class
    Key: Int64;
    Tie: Integer;
  end;

function BreadthCompareStrings(List: TStringList; A, B: Integer): Integer;
var
  L, R: TBreadthSortValue;
begin
  L := TBreadthSortValue(List.Objects[A]);
  R := TBreadthSortValue(List.Objects[B]);
  If L.Key < R.Key then
    Exit(-1);
  If L.Key > R.Key then
    Exit(1);
  Result := L.Tie - R.Tie;
end;

procedure RunBreadthStringSortPayload;
const
  Keys: array[0..4] of Int64 = (4294967297, -4294967295, 1, -4294967295, 4294967297);
  Ties: array[0..4] of Integer = (71, 19, 43, -11, -37);
  Expected: array[0..4] of Integer = (3, 1, 2, 4, 0);
var
  List: TStringList;
  Values: array[0..4] of TBreadthSortValue;
  I: Integer;
begin
  List := TStringList.Create;
  try
    List.OwnsObjects := True;
    for I := Low(Keys) to High(Keys) do begin
      List.Add(IntToStr(I));
      Values[I] := TBreadthSortValue.Create;
      List.Objects[I] := Values[I];
      Values[I].Key := OpaqueI(Keys[I]);
      Values[I].Tie := Integer(OpaqueI(Ties[I]));
    end;
    List.CustomSort(BreadthCompareStrings);
    for I := Low(Expected) to High(Expected) do begin
      Check(List.Objects[I] = Values[Expected[I]], 'breadth-custom-sort-keeps-object-payload');
      Check(List[I] = IntToStr(Expected[I]), 'breadth-custom-sort-keeps-string-payload');
      Mix(UInt64(TBreadthSortValue(List.Objects[I]).Tie));
    end;
  finally
    List.Free;
  end;
end;

function BreadthRecursiveUnwind(Level, StopAt: Integer; var Trace: Integer): TCrossEntry;
var
  Child: TCrossEntry;
  LabelText: AnsiString;
begin
  LabelText := AnsiChar(Ord('a') + Level);
  try
    If Level = StopAt then
      raise EAbort.Create('recursive unwind boundary');
    If Level = 0 then begin
      Result.Code := 13;
      Result.Text := LabelText;
    end else begin
      Child := BreadthRecursiveUnwind(Level - 1, StopAt, Trace);
      Result.Code := Child.Code * 10 + Level;
      Result.Text := LabelText + Child.Text;
    end;
  finally
    Trace := Trace * 10 + Ord(LabelText[1]) - Ord('a') + 1;
  end;
end;

procedure RunBreadthRecursiveUnwind;
var
  Actual, Staged: TCrossEntry;
  Trace: Integer;
  Caught: Boolean;
begin
  Trace := 0;
  Actual := BreadthRecursiveUnwind(Integer(OpaqueI(4)), -1, Trace);
  Check((Actual.Code = 131234) and (Actual.Text = AnsiString('edcba')), 'breadth-recursive-managed-return');
  Check(Trace = 12345, 'breadth-recursive-finally-live-frame-normal');
  Trace := 0;
  Caught := False;
  try
    Staged := BreadthRecursiveUnwind(Integer(OpaqueI(4)), 2, Trace);
    Actual := Staged;
  except
    on EAbort do Caught := True;
  end;
  Check(Caught and (Trace = 345), 'breadth-recursive-finally-live-frame-on-exception');
  Check((Actual.Code = 131234) and (Actual.Text = AnsiString('edcba')), 'breadth-recursive-exception-retains-previous-result');
  Mix(UInt64(Trace));
end;

procedure RunBreadthConsumerForms;
begin
  RunBreadthFormattedArguments;
  RunBreadthStringSortPayload;
  RunBreadthRecursiveUnwind;
end;
