unit devil_runtime;

{ Devil runtime: check bookkeeping, opacity barriers and the byte-level
  reference helpers every generated layer uses.

  Two rules the whole complex is built on:

  1. A check never compares against a value captured from some compiler run.
     It compares either two independently lowered computations of the same
     value, or one computation against a constant produced by the generator's
     own arithmetic model.
  2. A failing check reports name, actual and expected, and never stops the
     run: one form must not hide the rest. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$if FPC_FULLVERSION >= 30301}
    {$modeswitch anonymousfunctions}
    {$modeswitch functionreferences}
    {$define HAS_ANON}
  {$ifend}
  {$ifdef HAS_INLINEVAR}
    {$modeswitch INLINEVARS}
  {$endif}
{$else}
  {$define HAS_ANON}
  {$define HAS_INLINEVAR}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils;

const
  DevilMaxFailures = 4096;
  FnvOffset = UInt64($CBF29CE484222325);
  FnvPrime = UInt64($100000001B3);

var
  DevilChecks: Int64 = 0;
  DevilDigest: UInt64 = FnvOffset;
  DevilFailures: Integer = 0;
  { stays zero at runtime; the compiler cannot prove it }
  DevilZero: UInt64 = 0;

{ opacity barriers: force a value through a runtime path so constant
  folding cannot pre-compute the form under test }
function OpaqueU(V: UInt64): UInt64;
function OpaqueI(V: Int64): Int64;
function OpaqueI32(V: Integer): Integer;
function OpaqueD(V: Double): Double;

{ raw bit views, used to compare values without going through arithmetic }
function DoubleBits(D: Double): UInt64;
function SingleBits(S: Single): UInt32;

{ reference lowering helpers: the model side of a metamorphic pair computes
  with explicit masks so it shares no code path with the form under test }
function MaskTo(V: UInt64; Bits: Integer): UInt64;
function SignExtendTo(V: UInt64; Bits: Integer): Int64;

procedure DevilMix(V: UInt64);
procedure DevilCheckU(const Name: AnsiString; Actual, Expected: UInt64);
procedure DevilCheckBool(const Name: AnsiString; Condition: Boolean);
procedure DevilNote(const Name: AnsiString; Value: UInt64);
function DevilReport(const Prefix: AnsiString; Seed: UInt64): Integer;

{ Lifetime tracing: a tagged object appends its tag when it is destroyed, so
  the order of finalization becomes an observable string.  The order itself is
  not always specified by the language, so it is reported as an observation
  and compared between compilers rather than against a hard-coded answer. }
type
  TDvlTagged = class(TInterfacedObject)
  private
    FTag: AnsiChar;
  public
    class var Alive: Integer;
    class var Born: Integer;
    constructor Create(ATag: AnsiChar);
    destructor Destroy; override;
    property Tag: AnsiChar read FTag;
  end;

  TDvlTaggedRec = record
    A, B, C: IInterface;
    S: AnsiString;
    N: Integer;
  end;

var
  DevilTrail: AnsiString;

procedure DevilTrailReset;
function DevilTrailHash: UInt64;
function DevilTrailText: AnsiString;
procedure DevilTrailAdd(C: AnsiChar);
procedure DevilNoteText(const Name, Value: AnsiString);

implementation

function OpaqueU(V: UInt64): UInt64;
begin
  Result := V xor DevilZero;
end;

function OpaqueI(V: Int64): Int64;
begin
  Result := Int64(UInt64(V) xor DevilZero);
end;

function OpaqueI32(V: Integer): Integer;
begin
  Result := Integer(UInt32(UInt64(UInt32(V)) xor DevilZero));
end;

function OpaqueD(V: Double): Double;
var
  B: UInt64;
begin
  Move(V, B, SizeOf(B));
  B := B xor DevilZero;
  Move(B, V, SizeOf(V));
  Result := V;
end;

function DoubleBits(D: Double): UInt64;
begin
  Move(D, Result, SizeOf(Result));
end;

function SingleBits(S: Single): UInt32;
begin
  Move(S, Result, SizeOf(Result));
end;

function MaskTo(V: UInt64; Bits: Integer): UInt64;
begin
  if Bits >= 64 then
    Result := V
  else
    Result := V and ((UInt64(1) shl Bits) - 1);
end;

function SignExtendTo(V: UInt64; Bits: Integer): Int64;
var
  M: UInt64;
begin
  if Bits >= 64 then
    Exit(Int64(V));
  V := MaskTo(V, Bits);
  M := UInt64(1) shl (Bits - 1);
  Result := Int64((V xor M) - M);
end;

procedure DevilMix(V: UInt64);
begin
  DevilDigest := (DevilDigest xor V) * FnvPrime;
end;

procedure DevilCheckU(const Name: AnsiString; Actual, Expected: UInt64);
begin
  Inc(DevilChecks);
  DevilDigest := (DevilDigest xor Actual) * FnvPrime;
  if Actual = Expected then
    Exit;
  if DevilFailures < DevilMaxFailures then
    WriteLn('DEVIL_FAILURE ', string(Name), ' actual=', IntToHex(Actual, 16),
      ' expected=', IntToHex(Expected, 16));
  Inc(DevilFailures);
end;

procedure DevilCheckBool(const Name: AnsiString; Condition: Boolean);
begin
  Inc(DevilChecks);
  DevilDigest := (DevilDigest xor UInt64(Ord(Condition))) * FnvPrime;
  if Condition then
    Exit;
  if DevilFailures < DevilMaxFailures then
    WriteLn('DEVIL_FAILURE ', string(Name), ' actual=0 expected=1');
  Inc(DevilFailures);
end;

procedure DevilNote(const Name: AnsiString; Value: UInt64);
begin
  WriteLn('DEVIL_NOTE ', string(Name), '=', IntToHex(Value, 16));
end;

constructor TDvlTagged.Create(ATag: AnsiChar);
begin
  inherited Create;
  FTag := ATag;
  Inc(Alive);
  Inc(Born);
end;

destructor TDvlTagged.Destroy;
begin
  Dec(Alive);
  DevilTrail := DevilTrail + FTag;
  inherited Destroy;
end;

procedure DevilTrailReset;
begin
  DevilTrail := '';
end;

procedure DevilNoteText(const Name, Value: AnsiString);
begin
  WriteLn('DEVIL_TRAIL ', string(Name), '=', string(Value));
end;

procedure DevilTrailAdd(C: AnsiChar);
begin
  DevilTrail := DevilTrail + C;
end;

function DevilTrailText: AnsiString;
begin
  Result := DevilTrail;
end;

function DevilTrailHash: UInt64;
var
  I: Integer;
begin
  Result := FnvOffset;
  for I := 1 to Length(DevilTrail) do
    Result := (Result xor UInt64(Ord(DevilTrail[I]))) * FnvPrime;
end;

function DevilReport(const Prefix: AnsiString; Seed: UInt64): Integer;
begin
  DevilDigest := (DevilDigest xor UInt64(DevilChecks)) * FnvPrime;
  if DevilFailures > 0 then
  begin
    WriteLn(string(Prefix), '_FAIL seed=', Seed, ' failures=', DevilFailures,
      ' checks=', DevilChecks, ' digest=', IntToHex(DevilDigest, 16));
    Result := 1;
  end
  else
  begin
    WriteLn(string(Prefix), '_PASS seed=', Seed, ' checks=', DevilChecks,
      ' digest=', IntToHex(DevilDigest, 16));
    Result := 0;
  end;
end;

end.
