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
  SysUtils, SyncObjs;

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
{ How many times anything reached the bloodstream: a guard against the suite
  going blind while every digest still matches. }
function DevilFeedCount: Int64;
{ Bloodstream: everything a form observed on its way flows in here, whether or
  not anyone asserted about it.  The step is a bijection of the accumulator
  (xor, then multiply by an odd constant), so a single wrong bit anywhere can
  never cancel out - it avalanches into the final digest instead of dying at
  the edge of the case that produced it. }
procedure DevilFeed(Value: UInt64);
procedure DevilFeedText(const Value: AnsiString);
{ Порядковый канал.  Событие, чей порядок фиксирован языком, вливается сюда, и
  поскольку шаг накопителя некоммутативен, съеденный, задвоенный или
  переставленный шаг рвёт корневой дайджест — везде, а не только там, где
  кто-то догадался поставить сторож или вести трейл.  Ставить только там, где
  порядок действительно фиксирован: под потоковым ветвлением две ветви кормят
  поток вперемешку, и дайджест перестаёт быть свойством программы. }
procedure DevilStep(const Tag: AnsiString);
{ Сколько шагов прошло: как и число вливаний, это защита от ослепшего прибора —
  сборка, прошедшая меньше шагов, где-то потеряла событие. }
function DevilStepCount: Int64;
{ An observation that deliberately stays out of the bloodstream: used where the
  disagreement is already analysed, so a known defect cannot mask a new one by
  permanently colouring the root digest. }
procedure DevilNoteLoose(const Name: AnsiString; Value: UInt64);
{ Per-layer subtotal: the root digest says something broke, this says where. }
procedure DevilLayerBegin(const Layer: AnsiString);
procedure DevilLayerEnd;
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
    { Alive and Born are working counters: layers reset them around the piece
      they are measuring. These two are never reset by anyone, so the balance
      over the whole program stays meaningful. }
    class var EverBorn: Integer;
    class var EverGone: Integer;
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
  { unit startup writes its own trail: the shared one belongs to whichever
    layer is running, and would be overwritten long before shutdown }
  DevilUnitTrail: AnsiString;
  DevilTrailLock: TCriticalSection;
  DevilLayerDigest: UInt64 = FnvOffset;
  { how many times anything reached the bloodstream: if the optimizer ever
    decides a feed is dead, or a layer stops feeding, the suite goes blind
    while every digest still matches. This is the guard against that. }
  DevilFeeds: Int64 = 0;
  { сколько событий прошло порядковым каналом: сборка, прошедшая меньше шагов,
    где-то потеряла событие, даже если дайджесты сошлись }
  DevilSteps: Int64 = 0;
  DevilLayerName: AnsiString;

procedure DevilTrailReset;
function DevilTrailHash: UInt64;
function DevilTrailText: AnsiString;
procedure DevilTrailAdd(C: AnsiChar);
procedure DevilUnitTrailAdd(C: AnsiChar);
procedure DevilCheckTrail(const Name, Actual, Expected: AnsiString);
function DevilTextHash(const Text: AnsiString): UInt64;
procedure DevilNoteText(const Name, Value: AnsiString);

implementation

{ The runtime is the measuring instrument, not the thing measured: it must not
  dissolve into the forms under test.  Keeping it out of the inliner also keeps
  dvl-0017 (an internal error when a small managed routine is inlined into a
  finally block) from taking down every layer that writes a trail. }
{$ifdef FPC}{$push}{$optimization noautoinline}{$endif}

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
  DevilLayerDigest := (DevilLayerDigest xor V) * FnvPrime;
end;

procedure DevilCheckU(const Name: AnsiString; Actual, Expected: UInt64);
begin
  Inc(DevilChecks);
  { a check is a feed as well: otherwise a layer that only asserts and never
    observes would look like a dead bloodstream }
  Inc(DevilFeeds);
  DevilDigest := (DevilDigest xor Actual) * FnvPrime;
  DevilLayerDigest := (DevilLayerDigest xor Actual) * FnvPrime;
  if Actual = Expected then
    Exit;
  if DevilFailures < DevilMaxFailures then
    DevilTrailLock.Enter;
    try
      WriteLn('DEVIL_FAILURE ', string(Name), ' actual=', IntToHex(Actual, 16),
      ' expected=', IntToHex(Expected, 16));
    finally
      DevilTrailLock.Leave;
    end;
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

procedure DevilFeed(Value: UInt64);
begin
  Inc(DevilFeeds);
  DevilDigest := (DevilDigest xor Value) * FnvPrime;
  DevilLayerDigest := (DevilLayerDigest xor Value) * FnvPrime;
end;

procedure DevilFeedText(const Value: AnsiString);
var
  I: Integer;
begin
  DevilFeed(UInt64(Length(Value)));
  for I := 1 to Length(Value) do
    DevilFeed(UInt64(Ord(Value[I])));
end;

procedure DevilStep(const Tag: AnsiString);
var
  I: Integer;
  Mixed: UInt64;
begin
  Inc(DevilSteps);
  { метка сворачивается тем же биективным шагом, что и всё остальное: место
    события в последовательности становится частью корня }
  Mixed := UInt64(DevilSteps);
  for I := 1 to Length(Tag) do
    Mixed := (Mixed xor UInt64(Ord(Tag[I]))) * FnvPrime;
  DevilFeed(Mixed);
end;

function DevilStepCount: Int64;
begin
  Result := DevilSteps;
end;

procedure DevilLayerBegin(const Layer: AnsiString);
begin
  DevilLayerName := Layer;
  DevilLayerDigest := FnvOffset;
end;

procedure DevilLayerEnd;
begin
  DevilTrailLock.Enter;
  try
    WriteLn('DEVIL_LAYER ', string(DevilLayerName), '=',
      IntToHex(DevilLayerDigest, 16));
  finally
    DevilTrailLock.Leave;
  end;
end;

procedure DevilNoteLoose(const Name: AnsiString; Value: UInt64);
begin
  DevilTrailLock.Enter;
  try
    WriteLn('DEVIL_NOTE ', string(Name), '=', IntToHex(Value, 16));
  finally
    DevilTrailLock.Leave;
  end;
end;

procedure DevilNote(const Name: AnsiString; Value: UInt64);
begin
  DevilFeed(Value);
  DevilTrailLock.Enter;
  try
    WriteLn('DEVIL_NOTE ', string(Name), '=', IntToHex(Value, 16));
  finally
    DevilTrailLock.Leave;
  end;
end;

constructor TDvlTagged.Create(ATag: AnsiChar);
begin
  inherited Create;
  FTag := ATag;
  Inc(Alive);
  Inc(Born);
  Inc(EverBorn);
end;

destructor TDvlTagged.Destroy;
begin
  Dec(Alive);
  Inc(EverGone);
  DevilTrail := DevilTrail + FTag;
  inherited Destroy;
end;

procedure DevilTrailReset;
begin
  DevilTrail := '';
end;

procedure DevilNoteText(const Name, Value: AnsiString);
begin
  DevilTrailLock.Enter;
  try
    WriteLn('DEVIL_TRAIL ', string(Name), '=', string(Value));
  finally
    DevilTrailLock.Leave;
  end;
end;

procedure DevilTrailAdd(C: AnsiChar);
begin
  { a branching chain stage runs its continuation on two threads at once, and
    both of them mark the trail: without the lock the marks race and the trail
    comes out short, differently on every build }
  DevilTrailLock.Enter;
  try
    DevilTrail := DevilTrail + C;
  finally
    DevilTrailLock.Leave;
  end;
end;

procedure DevilUnitTrailAdd(C: AnsiChar);
begin
  DevilUnitTrail := DevilUnitTrail + C;
end;

function DevilTrailText: AnsiString;
begin
  Result := DevilTrail;
end;

function DevilTextHash(const Text: AnsiString): UInt64;
var
  I: Integer;
begin
  Result := FnvOffset;
  for I := 1 to Length(Text) do
    Result := (Result xor UInt64(Ord(Text[I]))) * FnvPrime;
end;

function DevilTrailHash: UInt64;
begin
  Result := DevilTextHash(DevilTrail);
end;

{ The order of steps is fixed by the language, so a trail is asserted, not
  observed.  The text goes out beside the verdict: a hash tells you that the
  order broke, the text tells you how. }
procedure DevilCheckTrail(const Name, Actual, Expected: AnsiString);
begin
  DevilNoteText(Name, Actual);
  DevilCheckU(Name, DevilTextHash(Actual), DevilTextHash(Expected));
end;

function DevilFeedCount: Int64;
begin
  Result := DevilFeeds;
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

{$ifdef FPC}{$pop}{$endif}

initialization
  DevilTrailLock := TCriticalSection.Create;

finalization
  { one invariant over the whole program: every tagged object any layer ever
    created has to be gone by the time the program shuts down. A leak anywhere
    - a chain that dropped a frame, a record that was finalized twice, an
    interface the optimizer released early - lands here. }
  DevilCheckU('devil-tagged-balance',
    UInt64(Cardinal(TDvlTagged.EverBorn - TDvlTagged.EverGone)), 0);
  FreeAndNil(DevilTrailLock);

end.
