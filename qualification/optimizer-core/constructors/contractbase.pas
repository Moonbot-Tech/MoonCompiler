unit contractbase;
{$mode delphiunicode}
{$modeswitch autoproperties}
interface
uses SysUtils;
var
  Allocations, Releases, AfterCalls, BeforeCalls, Destructions: Integer;
  BodyCalls, ActualCalls, LocalInit, LocalDone: Integer;
  FailAllocation, FailAfter, FailLocal: Boolean;
type
  TGuard = record
    Value: NativeInt;
    class operator Initialize(out Dest: TGuard);
    class operator Finalize(var Dest: TGuard);
  end;
  TEmpty = class
    Value: NativeInt;
    constructor Empty;
    constructor Scalar(N: NativeInt);
    constructor ManagedLocal;
    constructor OutText(out S: UnicodeString);
    constructor NonEmpty;
    class function NewInstance: TObject; override;
    procedure FreeInstance; override;
    procedure AfterConstruction; override;
    procedure BeforeDestruction; override;
    destructor Destroy; override;
    procedure ReenterEmpty;
  end;
  TDefault = class
    property Magic: NativeInt = 719;
    constructor Empty;
  end;
  TVirtual = class
    Marker: Integer;
    constructor Empty; virtual;
  end;
  TVirtualChild = class(TVirtual)
    constructor Empty; override;
  end;
  TVirtualClass = class of TVirtual;
  TLegacy = object
    Value: NativeInt;
    constructor Init;
    procedure Touch; virtual;
  end;
function Actual: NativeInt;
implementation
class operator TGuard.Initialize(out Dest: TGuard);
begin
  Inc(LocalInit);
  if FailLocal then raise Exception.Create('local initialization');
  Dest.Value := 917;
end;
class operator TGuard.Finalize(var Dest: TGuard);
begin
  if Dest.Value <> 917 then Halt(21);
  Inc(LocalDone);
end;
constructor TEmpty.Empty;
begin
end;
constructor TEmpty.Scalar(N: NativeInt);
begin
end;
constructor TEmpty.ManagedLocal;
var Guard: TGuard;
begin
  if Guard.Value <> 917 then Halt(22);
end;
constructor TEmpty.OutText(out S: UnicodeString);
begin
end;
constructor TEmpty.NonEmpty;
begin
  Inc(BodyCalls);
  Value := 43;
end;
class function TEmpty.NewInstance: TObject;
begin
  if FailAllocation then Exit(nil);
  Result := inherited NewInstance;
  Inc(Allocations);
end;
procedure TEmpty.FreeInstance;
begin
  Inc(Releases);
  inherited FreeInstance;
end;
procedure TEmpty.AfterConstruction;
begin
  Inc(AfterCalls);
  if FailAfter then raise Exception.Create('after construction');
  inherited AfterConstruction;
end;
procedure TEmpty.BeforeDestruction;
begin
  Inc(BeforeCalls);
  inherited BeforeDestruction;
end;
destructor TEmpty.Destroy;
begin
  Inc(Destructions);
  inherited Destroy;
end;
procedure TEmpty.ReenterEmpty;
begin
  Empty;
end;
constructor TDefault.Empty;
begin
end;
constructor TVirtual.Empty;
begin
end;
constructor TVirtualChild.Empty;
begin
  inherited Empty;
  Marker := 31;
end;
constructor TLegacy.Init;
begin
end;
procedure TLegacy.Touch;
begin
  Value := 71;
end;
function Actual: NativeInt;
begin
  Inc(ActualCalls);
  Result := 23;
end;
end.
