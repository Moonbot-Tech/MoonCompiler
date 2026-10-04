program contract;
{$mode delphiunicode}
uses SysUtils, contractbase;
type
  TChild = class(TEmpty)
    constructor Plain(N: NativeInt);
    constructor SideEffect;
    constructor Local;
    constructor OutValue(out S: UnicodeString);
    constructor NonemptyParent;
    constructor ThrowBody;
  end;
  TDefaultChild = class(TDefault)
    constructor Child;
  end;
constructor TChild.Plain(N: NativeInt);
begin
  inherited Empty;
  Value := N;
end;
constructor TChild.SideEffect;
begin
  inherited Scalar(Actual);
  Value := 53;
end;
constructor TChild.Local;
begin
  inherited ManagedLocal;
end;
constructor TChild.OutValue(out S: UnicodeString);
begin
  inherited OutText(S);
end;
constructor TChild.NonemptyParent;
begin
  inherited NonEmpty;
  Inc(Value);
end;
constructor TChild.ThrowBody;
begin
  inherited Empty;
  raise Exception.Create('body');
end;
constructor TDefaultChild.Child;
begin
  inherited Empty;
end;
function BuildInline(N: NativeInt): TChild; inline;
begin
  Result := TChild.Plain(N);
end;
procedure Check(B: Boolean; const Name: UnicodeString);
begin
  if not B then begin
    WriteLn('FAIL ', Name);
    Halt(1);
  end;
end;
var
  P: TEmpty;
  C: TChild;
  D: TDefaultChild;
  V: TVirtual;
  VC: TVirtualClass;
  Old: TLegacy;
  Text: UnicodeString;
  SavedAfter, Caught: Integer;
begin
  P := TEmpty.Empty;
  Check((P <> nil) and (P.Value = 0), 'empty allocating constructor');
  SavedAfter := AfterCalls;
  P.Empty;
  P.ReenterEmpty;
  Check(AfterCalls = SavedAfter + 2, 'mode minus one retains callbacks');
  P.Free;
  C := BuildInline(103);
  Check(C.Value = 103, 'inlined caller allocates and initializes');
  C.Free;
  C := TChild.SideEffect;
  Check((C.Value = 53) and (ActualCalls = 1), 'actual evaluated once');
  C.Free;
  C := TChild.Local;
  Check((LocalInit = 1) and (LocalDone = 1), 'managed local lifecycle');
  C.Free;
  Text := 'must be cleared';
  C := TChild.OutValue(Text);
  Check(Text = '', 'managed out formal');
  C.Free;
  C := TChild.NonemptyParent;
  Check((C.Value = 44) and (BodyCalls = 1), 'nonempty inherited body');
  C.Free;
  D := TDefaultChild.Child;
  Check(D.Magic = 719, 'auto property initialization outside source body');
  D.Free;
  VC := TVirtual;
  V := VC.Empty;
  Check((V <> nil) and (V.Marker = 0), 'empty virtual allocating target');
  V.Free;
  VC := TVirtualChild;
  V := VC.Empty;
  Check(V.Marker = 31, 'virtual override target');
  V.Free;
  Old.Init;
  Old.Touch;
  Check(Old.Value = 71, 'old style object vmt initialized');
  SavedAfter := AfterCalls;
  Caught := 0;
  try C := TChild.ThrowBody; except on E: Exception do Inc(Caught); end;
  Check((Caught = 1) and (AfterCalls = SavedAfter) and (Allocations = Releases), 'body failure cleanup');
  FailAfter := True;
  Caught := 0;
  try C := TChild.Plain(7); except on E: Exception do Inc(Caught); end;
  FailAfter := False;
  Check((Caught = 1) and (Allocations = Releases), 'after construction failure cleanup');
  FailAllocation := True;
  SavedAfter := AfterCalls;
  C := TChild.Plain(8);
  FailAllocation := False;
  Check((C = nil) and (AfterCalls = SavedAfter), 'nil NewInstance skips body');
  WriteLn('CONSTRUCTOR_STAGE2_PASS ', Allocations, ' ', Releases, ' ', AfterCalls, ' ', BeforeCalls, ' ', Destructions, ' ', BodyCalls, ' ', ActualCalls, ' ', LocalInit, ' ', LocalDone);
end.
