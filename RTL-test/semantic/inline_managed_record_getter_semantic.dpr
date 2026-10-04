program inline_managed_record_getter_semantic;

{ A field or an element of a record with managed fields (a string, a dynamic
  array) that an inlined getter returns by value - L[I].Price of a
  TList<TQuote> - is read straight from the list's storage when its consumer
  only reads: the copy of the whole record, its initialization and its
  finalization are gone.  Each read sees the source as it is between a change
  right before the expression and a change right after it.  A routine taking
  the value as an argument still gets a copy that survives a source replaced
  inside the routine, and a record whose copy runs code of the program - its
  management operators, an interface's _AddRef/_Release, also in a nested
  record - keeps the copy: each read runs that code exactly as before. }

{$mode delphi}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  cwstring,
  {$endif UNIX}
  System.SysUtils,
  System.Generics.Collections;

type
  TIntArray = array of Integer;

  TQuote = record
    Id: Int64;
    Price: Double;
    Symbol: UnicodeString;
    Tags: TIntArray;
  end;

  TQuoteList = TList<TQuote>;

  TTriple = array[0..2] of UnicodeString;

  THolder = class
  public
    FQuotes: TQuoteList;
    FQuote: TQuote;
    function GetQuote: TQuote; inline;
    property Quote: TQuote read GetQuote;
    function Reads(const Key: UnicodeString): Integer; noinline;
  end;

  { the copy of these runs code of the program }
  TOperated = record
    Value: Integer;
    Text: UnicodeString;
    class operator Initialize(var R: TOperated);
    class operator Finalize(var R: TOperated);
    class operator AddRef(var R: TOperated);
  end;

  TAssigned = record
    Value: Integer;
    Text: UnicodeString;
    class operator Initialize(out Dest: TAssigned);
    class operator Finalize(var Dest: TAssigned);
    class operator Assign(var Dest: TAssigned; const [ref] Src: TAssigned);
  end;

  TWrapped = record
    Value: Integer;
    Inner: TOperated;
  end;

  { counts the references a copy of the record takes and gives back }
  TCounter = class(TObject, IInterface)
  public
    function QueryInterface({$ifdef FPC}constref{$else}const{$endif} IID: TGUID; out Obj): HResult; {$ifdef MSWINDOWS}stdcall{$else}cdecl{$endif};
    function _AddRef: Integer; {$ifdef MSWINDOWS}stdcall{$else}cdecl{$endif};
    function _Release: Integer; {$ifdef MSWINDOWS}stdcall{$else}cdecl{$endif};
  end;

  TWithIntf = record
    Value: Integer;
    Link: IInterface;
  end;

var
  Quotes: TQuoteList;
  Triples: TList<TTriple>;
  Holder: THolder;
  TextTrash: UnicodeString;
  ArrayTrash: TIntArray;
  Inits, Finals, Copies, AddRefs, Releases: Integer;

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create('INLINE_MANAGED_RECORD_GETTER_FAIL: ' + AMessage);
end;

function THolder.GetQuote: TQuote;
begin
  Result := FQuote;
end;

class operator TOperated.Initialize(var R: TOperated);
begin
  Inc(Inits);
  R.Value := 0;
end;

class operator TOperated.Finalize(var R: TOperated);
begin
  Inc(Finals);
end;

class operator TOperated.AddRef(var R: TOperated);
begin
  Inc(Copies);
end;

class operator TAssigned.Initialize(out Dest: TAssigned);
begin
  Inc(Inits);
  Dest.Value := 0;
end;

class operator TAssigned.Finalize(var Dest: TAssigned);
begin
  Inc(Finals);
end;

class operator TAssigned.Assign(var Dest: TAssigned; const [ref] Src: TAssigned);
begin
  Inc(Copies);
  Dest.Value := Src.Value;
  Dest.Text := Src.Text;
end;

function TCounter.QueryInterface({$ifdef FPC}constref{$else}const{$endif} IID: TGUID; out Obj): HResult; {$ifdef MSWINDOWS}stdcall{$else}cdecl{$endif};
begin
  Result := E_NOINTERFACE;
end;

function TCounter._AddRef: Integer; {$ifdef MSWINDOWS}stdcall{$else}cdecl{$endif};
begin
  Inc(AddRefs);
  Result := 1;
end;

function TCounter._Release: Integer; {$ifdef MSWINDOWS}stdcall{$else}cdecl{$endif};
begin
  Inc(Releases);
  Result := 1;
end;

{ Gives every quote fresh storage marked by Seed and fills storage of the same
  sizes with garbage, so that a read through a released source pointer sees 'Z'
  or -1 instead of the value it should have kept. }
procedure Replace(Seed: Integer);
var
  I, J: Integer;
  Q: TQuote;
  T: TTriple;
begin
  for I := 0 to Quotes.Count - 1 do
  begin
    Q.Id := Seed * 100 + I;
    Q.Price := Seed * 10 + I + 0.5;
    Q.Symbol := StringOfChar(Char(Ord('a') + Seed), 32 + I);
    Q.Tags := nil;
    SetLength(Q.Tags, 32);
    for J := 0 to High(Q.Tags) do
      Q.Tags[J] := Seed * 1000 + I * 100 + J;
    Quotes[I] := Q;
  end;
  for I := 0 to Triples.Count - 1 do
  begin
    for J := 0 to 2 do
      T[J] := StringOfChar(Char(Ord('a') + Seed), 16 + J);
    Triples[I] := T;
  end;
  Holder.FQuote.Symbol := StringOfChar(Char(Ord('a') + Seed), 12);
  Q := Default(TQuote);
  TextTrash := StringOfChar('Z', 40);
  SetLength(ArrayTrash, 0);
  SetLength(ArrayTrash, 32);
  for I := 0 to High(ArrayTrash) do
    ArrayTrash[I] := -1;
end;

{ consumers that read straight from the source }

function ListReads(L: TQuoteList; I: Integer; const Key: UnicodeString): Integer; noinline;
var
  S: UnicodeString;
begin
  Result := 0;
  Replace(1);
  if L[I].Price = 10 + I + 0.5 then
    Inc(Result, 1);
  if L[I].Symbol = Key then
    Inc(Result, 10);
  Inc(Result, Length(L[I].Symbol) * 100);
  Inc(Result, Ord(L[I].Symbol[2]) * 10000);
  Inc(Result, L[I].Tags[3] * 1000000);
  if L[I].Id = 100 + I then
    Inc(Result, 100000000);
  S := L[I].Symbol;
  Replace(2);
  Check(S = Key, 'string taken from a record field');
end;

function LoopReads(L: TQuoteList): Double; noinline;
var
  I: Integer;
begin
  Result := 0;
  Replace(1);
  for I := 0 to L.Count - 1 do
    Result := Result + L[I].Price;
  Replace(2);
end;

function THolder.Reads(const Key: UnicodeString): Integer;
var
  I: Integer;
begin
  Result := 0;
  Replace(1);
  for I := 0 to FQuotes.Count - 1 do
    if FQuotes[I].Symbol = StringOfChar('b', 32 + I) then
      Inc(Result);
  if Quote.Symbol = Key then
    Inc(Result, 10);
  Inc(Result, Length(Quote.Symbol) * 100);
  Replace(2);
end;

function TripleReads(const Key17: UnicodeString): Integer; noinline;
begin
  Result := 0;
  Replace(1);
  if Triples[0][1] = Key17 then
    Inc(Result);
  Inc(Result, Length(Triples[0][2]) * 10);
  Replace(2);
end;

{ consumers that keep a copy of their own }

procedure ConsumeText(const T: UnicodeString; const Expected: UnicodeString); noinline;
begin
  Replace(2);
  Check(T = Expected, 'const text argument');
end;

procedure ConsumeValues(const V: TIntArray; First: Integer); noinline;
begin
  Replace(2);
  Check((Length(V) = 32) and (V[0] = First) and (V[31] = First + 31), 'const array argument');
end;

procedure Escapes;
begin
  Replace(1);
  ConsumeText(Quotes[1].Symbol, StringOfChar('b', 33));
  Replace(1);
  ConsumeValues(Quotes[2].Tags, 1200);
  Replace(1);
  ConsumeText(Holder.Quote.Symbol, StringOfChar('b', 12));
  Replace(1);
  ConsumeText(Triples[0][0], StringOfChar('b', 16));
end;

{ each read of a record whose copy runs code of the program runs it as before:
  the temp's initialization, the copy and the finalization }
function OperatedRead(L: TList<TOperated>; I: Integer): Integer; noinline;
begin
  Result := L[I].Value;
end;

function AssignedRead(L: TList<TAssigned>; I: Integer): Integer; noinline;
begin
  Result := L[I].Value;
end;

function WrappedRead(L: TList<TWrapped>; I: Integer): Integer; noinline;
begin
  Result := L[I].Inner.Value;
end;

function IntfRead(L: TList<TWithIntf>; I: Integer): Integer; noinline;
begin
  Result := L[I].Value;
end;

procedure CopyingRecords;
var
  Ops: TList<TOperated>;
  Asg: TList<TAssigned>;
  Wrp: TList<TWrapped>;
  Itf: TList<TWithIntf>;
  O: TOperated;
  A: TAssigned;
  W: TWrapped;
  R: TWithIntf;
  Counters: array[0..2] of TCounter;
  I, V, I0, F0, C0: Integer;
begin
  Ops := TList<TOperated>.Create;
  Asg := TList<TAssigned>.Create;
  Wrp := TList<TWrapped>.Create;
  Itf := TList<TWithIntf>.Create;
  try
    for I := 0 to 2 do
    begin
      O.Value := 10 + I;
      O.Text := 'o';
      Ops.Add(O);
      A.Value := 20 + I;
      A.Text := 'a';
      Asg.Add(A);
      W.Value := I;
      W.Inner.Value := 30 + I;
      Wrp.Add(W);
      R.Value := 40 + I;
      Counters[I] := TCounter.Create;
      R.Link := Counters[I];
      Itf.Add(R);
    end;
    R.Link := nil;

    I0 := Inits; F0 := Finals; C0 := Copies;
    V := OperatedRead(Ops, 1);
    Check(V = 11, 'operated value');
    { a record copy runs Initialize of the temp and Finalize at its end;
      AddRef belongs to the other copies (a value parameter) }
    Check((Inits - I0 = 1) and (Finals - F0 = 1),
      Format('operated record: init %d final %d', [Inits - I0, Finals - F0]));

    I0 := Inits; F0 := Finals; C0 := Copies;
    V := AssignedRead(Asg, 2);
    Check(V = 22, 'assigned value');
    Check((Inits - I0 = 1) and (Copies - C0 = 1) and (Finals - F0 = 1),
      Format('assigned record: init %d copy %d final %d', [Inits - I0, Copies - C0, Finals - F0]));

    I0 := Inits; F0 := Finals; C0 := Copies;
    V := WrappedRead(Wrp, 0);
    Check(V = 30, 'wrapped value');
    Check((Inits - I0 = 1) and (Finals - F0 = 1),
      Format('wrapped record: init %d final %d', [Inits - I0, Finals - F0]));

    I0 := AddRefs; F0 := Releases;
    V := IntfRead(Itf, 2);
    Check(V = 42, 'interface record value');
    Check((AddRefs - I0 = 1) and (Releases - F0 = 1),
      Format('interface record: addref %d release %d', [AddRefs - I0, Releases - F0]));
  finally
    Itf.Free;
    Wrp.Free;
    Asg.Free;
    Ops.Free;
  end;
  for I := 0 to 2 do
    Counters[I].Free;
end;

var
  I: Integer;
  Q: TQuote;
  T: TTriple;
begin
  Quotes := TQuoteList.Create;
  Triples := TList<TTriple>.Create;
  Holder := THolder.Create;
  Holder.FQuotes := Quotes;
  try
    for I := 0 to 3 do
      Quotes.Add(Q);
    Triples.Add(T);
    Replace(0);
    Check(ListReads(Quotes, 1, StringOfChar('b', 33)) =
      1 + 10 + 33 * 100 + Ord('b') * 10000 + 1103 * 1000000 + 100000000, 'list reads');
    Check(LoopReads(Quotes) = 4 * 10.5 + 6, 'loop reads');
    Check(Holder.Reads(StringOfChar('b', 12)) = 4 + 10 + 12 * 100, 'field list and record getter reads');
    Check(TripleReads(StringOfChar('b', 17)) = 1 + 18 * 10, 'static array of strings');
    Escapes;
    CopyingRecords;
  finally
    Holder.Free;
    Triples.Free;
    Quotes.Free;
  end;
  WriteLn('INLINE_MANAGED_RECORD_GETTER_SEMANTIC_PASS');
end.
