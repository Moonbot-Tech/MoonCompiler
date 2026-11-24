{ Indirect calls can expose the storage of an argument, or require a new
  temporary. Exercise both through real dispatch and independently observe
  the original storage. }

type
  PBreadthLong = ^LongInt;
  TBreadthAddressBase = class
    procedure Observe({$ifdef FPC}constref{$else}const [ref]{$endif} Value: LongInt); virtual; abstract;
    function Inspect({$ifdef FPC}constref{$else}const [ref]{$endif} Value: Double;
      Source: Pointer): Boolean; virtual; abstract;
  end;

  TBreadthAddressSaver = class(TBreadthAddressBase)
    Saved: PBreadthLong;
    Reads: Integer;
    procedure Observe({$ifdef FPC}constref{$else}const [ref]{$endif} Value: LongInt); override;
    function Inspect({$ifdef FPC}constref{$else}const [ref]{$endif} Value: Double;
      Source: Pointer): Boolean; override;
  end;

procedure TBreadthAddressSaver.Observe({$ifdef FPC}constref{$else}const [ref]{$endif} Value: LongInt);
begin
  Saved := @Value;
  Inc(Reads);
  If Reads = 3 then
    Saved^ := -9007;
end;

function TBreadthAddressSaver.Inspect({$ifdef FPC}constref{$else}const [ref]{$endif} Value: Double;
  Source: Pointer): Boolean;
begin
  Result := (Pointer(@Value) <> Source) and (Value = 1.625);
end;

function BreadthConstrefFrame(Reader: TBreadthAddressBase; Count: Integer): Int64;
type
  TFrame = packed record
    Guard: Byte;
    Value: LongInt;
    Fraction: Single;
  end;
var
  Frame: TFrame;
  I: Integer;
begin
  Frame.Guard := $C3;
  Frame.Value := 17;
  Frame.Fraction := OpaqueD(1.625);
  for I := 1 to Count do
  begin
    Inc(Frame.Value, I);
    Reader.Observe(Frame.Value);
  end;
  Check(Reader.Inspect(Frame.Fraction, @Frame.Fraction), 'breadth-constref-converts-into-temporary');
  Check((Frame.Guard = $C3) and (Frame.Fraction = 1.625), 'breadth-constref-packed-neighbors');
  Result := Frame.Value;
end;

procedure RunBreadthConstrefEscape;
var
  Reader: TBreadthAddressSaver;
  Value: Int64;
begin
  Reader := TBreadthAddressSaver.Create;
  try
    Value := BreadthConstrefFrame(Reader, Integer(OpaqueI(5)));
    Check(Value = -8998, 'breadth-constref-virtual-escaped-storage');
    Check(Reader.Reads = 5, 'breadth-constref-virtual-call-count');
    Mix(UInt64(Value));
  finally
    Reader.Free;
  end;
end;

type
  TBreadthRecordResult = record
    Header: Int64;
    Body: array[1..6] of Int64;
    Footer: Int64;
  end;

function BreadthChooseInline(ChooseLeft: Boolean; const Left, Right: TBreadthRecordResult): TBreadthRecordResult; inline;
begin
  If ChooseLeft then
    Result := Left
  else
    Result := Right;
end;

function BreadthEditRecord(const Src: TBreadthRecordResult; RaiseBeforeFooter: Boolean): TBreadthRecordResult;
var
  I: Integer;
begin
  Result.Header := 701;
  for I := Low(Src.Body) to High(Src.Body) do
    Result.Body[I] := Src.Body[High(Src.Body) + 1 - I] - I;
  If RaiseBeforeFooter then
    raise EAbort.Create('inline record consumer');
  Result.Footer := Src.Header + Src.Footer;
end;

procedure RunBreadthBranchRecordResult;
const
  Expected: array[1..6] of Int64 = (-31, -27, -23, -19, -15, -11);
var
  Left, Right, Dest: TBreadthRecordResult;
  Choice, I: Integer;
  Caught: Boolean;
begin
  Left.Header := 19;
  Left.Footer := 37;
  Right.Header := -61;
  Right.Footer := -73;
  for I := Low(Left.Body) to High(Left.Body) do
  begin
    Left.Body[I] := I * 3;
    Right.Body[I] := -I * 5;
  end;
  Choice := Integer(OpaqueI(7));
  Dest := BreadthChooseInline(Choice < 0, Left, Right);
  Check((Dest.Header = -61) and (Dest.Footer = -73), 'breadth-inline-record-selects-right');
  Dest := BreadthEditRecord(Dest, False);
  Check((Dest.Header = 701) and (Dest.Footer = -134), 'breadth-inline-record-rhs-reads-original-destination');
  for I := Low(Expected) to High(Expected) do
    Check(Dest.Body[I] = Expected[I], 'breadth-inline-record-reverse-payload');

  Caught := False;
  try
    { Consume the temporary through a value-returning call. A throwing
      producer cannot update the outer assignment or its source. }
    Dest := BreadthChooseInline(Choice > 0, BreadthEditRecord(Left, True), Right);
  except
    on EAbort do Caught := True;
  end;
  Check(Caught, 'breadth-inline-record-nested-producer-raises');
  Check((Dest.Header = 701) and (Dest.Footer = -134), 'breadth-inline-record-throw-retains-destination');
  Check((Left.Header = 19) and (Left.Body[6] = 18), 'breadth-inline-record-throw-retains-source');
  for I := Low(Expected) to High(Expected) do
    Check(Dest.Body[I] = Expected[I], 'breadth-inline-record-throw-retains-payload');
  Mix(UInt64(Dest.Footer));
  Dest := BreadthChooseInline(Choice > 0, Left, Right);
  Check((Dest.Header = 19) and (Dest.Footer = 37), 'breadth-inline-record-selects-left');
end;

{$excessprecision off}
function BreadthSingleNarrow(A, B: Single): Double;
begin
  Result := (A + B) - A;
end;

{$excessprecision on}
function BreadthSingleWide(A, B: Single): Double;
{$ifdef FPC}
  {$if FPC_FULLVERSION <= 30204}
var
  WideA: Double;
  {$endif}
{$endif}
begin
{$ifdef FPC}
  {$if FPC_FULLVERSION <= 30204}
  { The stable upstream compiler does not widen this pair via the directive.
    A real Double store expresses the same intermediate contract there. }
  WideA := A;
  Result := (WideA + B) - WideA;
  {$else}
  Result := (A + B) - A;
  {$endif}
{$else}
  Result := (A + B) - A;
{$endif}
end;

procedure RunBreadthFloatIntermediateWidth;
var
  A, B: Single;
  ResultNarrow: Double;
begin
  A := OpaqueD(16777216.0);
  B := OpaqueD(1.0);
  ResultNarrow := BreadthSingleNarrow(A, B);
  Check(ResultNarrow = 0.0, 'breadth-fp-excess-off-internal-rounding');
  Check(BreadthSingleWide(A, B) = 1.0, 'breadth-fp-excess-on-wider-intermediate');
  Mix(DoubleBits(ResultNarrow));
end;

type
  TBreadthReadOffset = function(Ticket: Int64; Key: Double): Double; cdecl;

  TBreadthFloatPair = record
    Left, Right: Double;
  end;

function BreadthAddOffset(Ticket: Int64; Key: Double): Double; cdecl;
begin
  Result := Key + Ticket * 0.125;
end;

function BreadthSubtractOffset(Ticket: Int64; Key: Double): Double; cdecl;
begin
  Result := Key - Ticket * 0.125;
end;

function BreadthFloatRegisterFlow(A, B, C, D, E, F: Double; Ticket: Int64; G, H, I, J, K, L: Double;
  Offset: TBreadthReadOffset): TBreadthFloatPair; cdecl;
var
  Correction: Double;
begin
  Correction := Offset(Ticket, H);
  Result.Left := (A + Correction) + 2 * (C - Correction) + 3 * E * Correction
    + 5 * (G + Correction) + 7 * (I - E) + 11 * (K - Correction);
  Result.Right := (B - Correction) + 3 * (D + Correction) + 5 * F * Correction
    + 7 * (H + Correction) + 11 * (J - B) + 13 * (L + Correction);
end;

procedure RunBreadthFloatRegisterFlow;
const
  LeftExpected: array[0..1] of Double = (461.4375, 262.0625);
  RightExpected: array[0..1] of Double = (-651.84375, -312.90625);
var
  Row: Integer;
  Offset: TBreadthReadOffset;
  Actual: TBreadthFloatPair;
begin
  for Row := Low(LeftExpected) to High(LeftExpected) do begin
    If OpaqueI(Row) = 0 then
      Offset := BreadthAddOffset
    else
      Offset := BreadthSubtractOffset;
    Actual := BreadthFloatRegisterFlow(OpaqueD(1.25), OpaqueD(-3.5), OpaqueD(7.75), OpaqueD(-9.25),
      OpaqueD(11.5), OpaqueD(-13.75), OpaqueI(29), OpaqueD(17.125), OpaqueD(-4.5), OpaqueD(19.875),
      OpaqueD(-23.25), OpaqueD(29.5), OpaqueD(-31.75), Offset);
    Check(Actual.Left = LeftExpected[Row], 'breadth-wide-fp-call-keeps-even-arguments');
    Check(Actual.Right = RightExpected[Row], 'breadth-wide-fp-call-keeps-odd-arguments');
    Mix(DoubleBits(Actual.Left));
    Mix(DoubleBits(Actual.Right));
  end;
end;

procedure RunBreadthCallForms;
begin
  RunBreadthConstrefEscape;
  RunBreadthBranchRecordResult;
  RunBreadthFloatIntermediateWidth;
  RunBreadthFloatRegisterFlow;
end;
