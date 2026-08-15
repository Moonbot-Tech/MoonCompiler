{ Devil support declarations: shared by every generated layer. }

type
  EDvlSignal = class(Exception);

  TDvlProc = reference to procedure;

  TDvlPoint = record
    X: Integer;
    Y: Integer;
  end;


  TDvlIntFunc = reference to function(X: Integer): Integer;

  TDvlCounter<T> = class
  public
    class var Value: Integer;
    class procedure Bump;
  end;

  TDvlOps = class
  public
    class function Echo<T>(const AValue: T): T; static;
    class procedure Swap<T>(var A, B: T); static;
    class function First<A, B>(const AValue: A; const BValue: B): A; static;
  end;

  TDvlSeeded = class
  public
    Value: Integer;
    constructor Create; virtual;
  end;

  TDvlFactory<T: TDvlSeeded, constructor> = class
    class function Make: T; static;
  end;

  TDvlManagedBox<T> = record
    Value: T;
  end;


  TDvlTracked = record
    Value: Integer;
    class operator Initialize({$ifdef FPC}var{$else}out{$endif} Dest: TDvlTracked);
    class operator Finalize(var Dest: TDvlTracked);
{$ifdef FPC}
    class operator Copy(constref Src: TDvlTracked; var Dest: TDvlTracked);
{$else}
    class operator Assign(var Dest: TDvlTracked; const [ref] Src: TDvlTracked);
{$endif}
  end;
  TDvlTrackedArray = array of TDvlTracked;


  IDvlAlpha = interface
    ['{6B1D2C30-8A44-4C0E-9E21-5D77A1B90001}']
    function AlphaValue: Integer;
  end;

  IDvlBeta = interface
    ['{6B1D2C30-8A44-4C0E-9E21-5D77A1B90002}']
    function BetaValue: Integer;
  end;

  TDvlDual = class(TInterfacedObject, IDvlAlpha, IDvlBeta)
  private
    FSeed: Integer;
  public
    class var Alive: Integer;
    constructor Create(ASeed: Integer);
    destructor Destroy; override;
    function AlphaValue: Integer;
    function BetaValue: Integer;
  end;

  TDvlBox = record
    Fi8: ShortInt;
    Fu8: Byte;
    Fi16: SmallInt;
    Fu16: Word;
    Fi32: Integer;
    Fu32: Cardinal;
    Fi64: Int64;
    Fu64: UInt64;
  end;

  TDvlGuard = class(TInterfacedObject)
  public
    class var Alive: Integer;
    constructor Create;
    destructor Destroy; override;
  end;

  TDvlHolder = class
  private
    FBox: TDvlBox;
    function GetI8: ShortInt;
    procedure SetI8(Value: ShortInt);
    function GetU8: Byte;
    procedure SetU8(Value: Byte);
    function GetI16: SmallInt;
    procedure SetI16(Value: SmallInt);
    function GetU16: Word;
    procedure SetU16(Value: Word);
    function GetI32: Integer;
    procedure SetI32(Value: Integer);
    function GetU32: Cardinal;
    procedure SetU32(Value: Cardinal);
    function GetI64: Int64;
    procedure SetI64(Value: Int64);
    function GetU64: UInt64;
    procedure SetU64(Value: UInt64);
  public
    property Propi8: ShortInt read GetI8 write SetI8;
    property Propu8: Byte read GetU8 write SetU8;
    property Propi16: SmallInt read GetI16 write SetI16;
    property Propu16: Word read GetU16 write SetU16;
    property Propi32: Integer read GetI32 write SetI32;
    property Propu32: Cardinal read GetU32 write SetU32;
    property Propi64: Int64 read GetI64 write SetI64;
    property Propu64: UInt64 read GetU64 write SetU64;
  end;

constructor TDvlGuard.Create;
begin
  inherited Create;
  Inc(Alive);
end;

destructor TDvlGuard.Destroy;
begin
  Dec(Alive);
  inherited Destroy;
end;

function TDvlHolder.GetI8: ShortInt;
begin
  Result := FBox.Fi8;
end;

procedure TDvlHolder.SetI8(Value: ShortInt);
begin
  FBox.Fi8 := Value;
end;

function TDvlHolder.GetU8: Byte;
begin
  Result := FBox.Fu8;
end;

procedure TDvlHolder.SetU8(Value: Byte);
begin
  FBox.Fu8 := Value;
end;

function TDvlHolder.GetI16: SmallInt;
begin
  Result := FBox.Fi16;
end;

procedure TDvlHolder.SetI16(Value: SmallInt);
begin
  FBox.Fi16 := Value;
end;

function TDvlHolder.GetU16: Word;
begin
  Result := FBox.Fu16;
end;

procedure TDvlHolder.SetU16(Value: Word);
begin
  FBox.Fu16 := Value;
end;

function TDvlHolder.GetI32: Integer;
begin
  Result := FBox.Fi32;
end;

procedure TDvlHolder.SetI32(Value: Integer);
begin
  FBox.Fi32 := Value;
end;

function TDvlHolder.GetU32: Cardinal;
begin
  Result := FBox.Fu32;
end;

procedure TDvlHolder.SetU32(Value: Cardinal);
begin
  FBox.Fu32 := Value;
end;

function TDvlHolder.GetI64: Int64;
begin
  Result := FBox.Fi64;
end;

procedure TDvlHolder.SetI64(Value: Int64);
begin
  FBox.Fi64 := Value;
end;

function TDvlHolder.GetU64: UInt64;
begin
  Result := FBox.Fu64;
end;

procedure TDvlHolder.SetU64(Value: UInt64);
begin
  FBox.Fu64 := Value;
end;

function DvlRawi8(V: ShortInt): UInt64;
begin
  Result := UInt64(Byte(V));
end;

function DvlRawu8(V: Byte): UInt64;
begin
  Result := UInt64(V);
end;

function DvlRawi16(V: SmallInt): UInt64;
begin
  Result := UInt64(Word(V));
end;

function DvlRawu16(V: Word): UInt64;
begin
  Result := UInt64(V);
end;

function DvlRawi32(V: Integer): UInt64;
begin
  Result := UInt64(Cardinal(V));
end;

function DvlRawu32(V: Cardinal): UInt64;
begin
  Result := UInt64(V);
end;

function DvlRawi64(V: Int64): UInt64;
begin
  Result := UInt64(V);
end;

function DvlRawu64(V: UInt64): UInt64;
begin
  Result := V;
end;

function DvlEchoi8(V: ShortInt): ShortInt;
begin
  Result := V;
end;

function DvlEchou8(V: Byte): Byte;
begin
  Result := V;
end;

function DvlEchoi16(V: SmallInt): SmallInt;
begin
  Result := V;
end;

function DvlEchou16(V: Word): Word;
begin
  Result := V;
end;

function DvlEchoi32(V: Integer): Integer;
begin
  Result := V;
end;

function DvlEchou32(V: Cardinal): Cardinal;
begin
  Result := V;
end;

function DvlEchoi64(V: Int64): Int64;
begin
  Result := V;
end;

function DvlEchou64(V: UInt64): UInt64;
begin
  Result := V;
end;

procedure DvlLoadi8(var Dest: ShortInt; Value: ShortInt);
begin
  Dest := Value;
end;

procedure DvlLoadu8(var Dest: Byte; Value: Byte);
begin
  Dest := Value;
end;

procedure DvlLoadi16(var Dest: SmallInt; Value: SmallInt);
begin
  Dest := Value;
end;

procedure DvlLoadu16(var Dest: Word; Value: Word);
begin
  Dest := Value;
end;

procedure DvlLoadi32(var Dest: Integer; Value: Integer);
begin
  Dest := Value;
end;

procedure DvlLoadu32(var Dest: Cardinal; Value: Cardinal);
begin
  Dest := Value;
end;

procedure DvlLoadi64(var Dest: Int64; Value: Int64);
begin
  Dest := Value;
end;

procedure DvlLoadu64(var Dest: UInt64; Value: UInt64);
begin
  Dest := Value;
end;

function DvlPassConsti8(const V: ShortInt): ShortInt;
begin
  Result := V;
end;

function DvlPassConstu8(const V: Byte): Byte;
begin
  Result := V;
end;

function DvlPassConsti16(const V: SmallInt): SmallInt;
begin
  Result := V;
end;

function DvlPassConstu16(const V: Word): Word;
begin
  Result := V;
end;

function DvlPassConsti32(const V: Integer): Integer;
begin
  Result := V;
end;

function DvlPassConstu32(const V: Cardinal): Cardinal;
begin
  Result := V;
end;

function DvlPassConsti64(const V: Int64): Int64;
begin
  Result := V;
end;

function DvlPassConstu64(const V: UInt64): UInt64;
begin
  Result := V;
end;

threadvar
  DvlThreadLocal: Integer;

var
  DvlThreadLock: TObject;
  DvlThreadCounter: Int64;
  DvlThreadFailures: Int64;
  DvlFlowCalls: Integer;

function DvlFlowTrue: Boolean;
begin
  Inc(DvlFlowCalls);
  Result := True;
end;

function DvlFlowFalse: Boolean;
begin
  Inc(DvlFlowCalls);
  Result := False;
end;


function DvlRttiFieldValue(Instance: TObject; const FieldName: string): Integer;
var
  Context: TRttiContext;
  F: TRttiField;
begin
  Result := -1;
  Context := TRttiContext.Create;
  try
    F := Context.GetType(Instance.ClassType).GetField(FieldName);
    if F <> nil then
      Result := F.GetValue(Instance).AsInteger;
  finally
    Context.Free;
  end;
end;

procedure DvlRttiFieldSet(Instance: TObject; const FieldName: string;
  Value: Integer);
var
  Context: TRttiContext;
  F: TRttiField;
begin
  Context := TRttiContext.Create;
  try
    F := Context.GetType(Instance.ClassType).GetField(FieldName);
    if F <> nil then
      F.SetValue(Instance, TValue.From<Integer>(Value));
  finally
    Context.Free;
  end;
end;

function DvlRttiFieldCount(Info: Pointer): Integer;
var
  Context: TRttiContext;
begin
  Context := TRttiContext.Create;
  try
    Result := Length(Context.GetType(Info).GetFields);
  finally
    Context.Free;
  end;
end;

function DvlRttiAttributeCount(Info: Pointer): UInt64;
var
  Context: TRttiContext;
begin
  Context := TRttiContext.Create;
  try
    Result := UInt64(Length(Context.GetType(Info).GetAttributes));
  finally
    Context.Free;
  end;
end;

function DvlRttiTypeNameMatches(Info: Pointer; const Expected: string): Boolean;
var
  Context: TRttiContext;
begin
  Context := TRttiContext.Create;
  try
    Result := SameText(Context.GetType(Info).Name, Expected);
  finally
    Context.Free;
  end;
end;

function DvlRttiTypeCount: UInt64;
var
  Context: TRttiContext;
begin
  Context := TRttiContext.Create;
  try
    Result := UInt64(Length(Context.GetTypes));
  finally
    Context.Free;
  end;
end;

function DvlRttiHasType(Info: Pointer): Boolean;
var
  Context: TRttiContext;
  T: TRttiType;
begin
  Result := False;
  Context := TRttiContext.Create;
  try
    for T in Context.GetTypes do
      if T.Handle = Info then
        Exit(True);
  finally
    Context.Free;
  end;
end;

class procedure TDvlCounter<T>.Bump;
begin
  Inc(Value);
end;

class function TDvlOps.Echo<T>(const AValue: T): T;
begin
  Result := AValue;
end;

class procedure TDvlOps.Swap<T>(var A, B: T);
var
  Tmp: T;
begin
  Tmp := A;
  A := B;
  B := Tmp;
end;

class function TDvlOps.First<A, B>(const AValue: A; const BValue: B): A;
begin
  Result := AValue;
end;

constructor TDvlSeeded.Create;
begin
  inherited Create;
  Value := 5;
end;

class function TDvlFactory<T>.Make: T;
begin
  Result := T.Create;
end;

var
  DvlConstraintSlot: Integer = 0;

procedure DvlConstraintProbe;
var
  Obj: TDvlSeeded;
begin
  Obj := TDvlFactory<TDvlSeeded>.Make;
  DvlConstraintSlot := Obj.Value;
  Obj.Free;
end;

function DvlConstraintValue: UInt64;
begin
  Result := UInt64(DvlConstraintSlot);
end;

procedure DvlManagedBoxRoundTrip;
var
  Box: TDvlManagedBox<IInterface>;
begin
  Box.Value := TDvlTagged.Create('g');
  Box.Value := nil;
end;

function DvlGenericAdd(A, B: Integer): Integer;
begin
  Result := TDvlOps.First<Integer, Integer>(A + B, 0);
end;


var
  DvlTrackedInitCount: Integer;
  DvlTrackedFiniCount: Integer;
  DvlTrackedCopyCount: Integer;

class operator TDvlTracked.Initialize({$ifdef FPC}var{$else}out{$endif} Dest: TDvlTracked);
begin
  Dest.Value := 5;
  Inc(DvlTrackedInitCount);
end;

class operator TDvlTracked.Finalize(var Dest: TDvlTracked);
begin
  Inc(DvlTrackedFiniCount);
end;

{$ifdef FPC}
class operator TDvlTracked.Copy(constref Src: TDvlTracked; var Dest: TDvlTracked);
{$else}
class operator TDvlTracked.Assign(var Dest: TDvlTracked; const [ref] Src: TDvlTracked);
{$endif}
begin
  Dest.Value := Src.Value + 100;
  Inc(DvlTrackedCopyCount);
end;


constructor TDvlDual.Create(ASeed: Integer);
begin
  inherited Create;
  FSeed := ASeed;
  Inc(Alive);
end;

destructor TDvlDual.Destroy;
begin
  Dec(Alive);
  inherited Destroy;
end;

function TDvlDual.AlphaValue: Integer;
begin
  Result := FSeed * 2;
end;

function TDvlDual.BetaValue: Integer;
begin
  Result := FSeed + 1000;
end;

procedure DvlTrackedReset;
begin
  DvlTrackedInitCount := 0;
  DvlTrackedFiniCount := 0;
  DvlTrackedCopyCount := 0;
end;

function DvlTrackedInit: Integer;
begin
  Result := DvlTrackedInitCount;
end;

function DvlTrackedFini: Integer;
begin
  Result := DvlTrackedFiniCount;
end;

function DvlCountArgs(const A: array of const): Integer;
begin
  Result := Length(A);
end;

function DvlSumOpen(const A: array of Integer): Integer;
var
  K: Integer;
begin
  Result := 0;
  for K := Low(A) to High(A) do
    Result := Result + A[K];
end;
