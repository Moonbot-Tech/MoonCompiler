program string_literal_materialize_semantic;

{ dvl-0031: Delphi (DCC64 36.0) keeps a shared string literal (refcount -1)
  only when the assignment target lives in the current stack frame: a plain
  local, a value parameter, or a static array element/record field chain
  rooted in one.  Every escaping storage class - globals, threadvars, object
  fields, dynamic arrays, heap records, var/out parameters, function results
  and captured locals - owns a materialized heap copy (refcount 1).  The pin
  walks the full storage matrix and checks the observable refcounts plus the
  functional consequence: mutating an owned copy never leaks into other
  holders of the same literal. }

{$APPTYPE CONSOLE}

{$ifdef FPC}
{$mode delphi}{$H+}
{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}
{$endif FPC}

uses
  {$ifdef FPC}
  mormot.core.fpcx64mm,
  {$endif FPC}
  {$ifdef UNIX}
  cthreads,
  cwstring,
  {$endif UNIX}
  SysUtils;

type
  TRefProbe = reference to function: NativeInt;

  THolder = class
  public
    FText: UnicodeString;
  end;

  TInner = record
    Arr: array[0..1] of UnicodeString;
  end;

  TRec = record
    Text: UnicodeString;
    Inner: TInner;
  end;
  PRec = ^TRec;

const
  TypedConstText: UnicodeString = 'typed-const-lit';

var
  GlobalText: UnicodeString;
  GlobalOther: UnicodeString;
  GlobalAnsi: AnsiString;
  GlobalArray: array[0..1] of UnicodeString;
  GlobalRec: TRec;

threadvar
  ThreadText: UnicodeString;

procedure Check(Condition: Boolean; const MessageText: string);
begin
  If not Condition then
    raise Exception.Create(MessageText);
end;

procedure CheckLocalStaysShared;
var
  LocalText: UnicodeString;
  LocalAnsi: AnsiString;
  LocalRec: TRec;
  LocalArray: array[0..1] of UnicodeString;
begin
  LocalText := 'local-lit';
  Check(StringRefCount(LocalText) = -1, 'plain local keeps shared literal');
  LocalAnsi := 'local-ansi-lit';
  Check(StringRefCount(LocalAnsi) = -1, 'plain ansi local keeps shared literal');
  LocalRec.Text := 'lrec-lit';
  Check(StringRefCount(LocalRec.Text) = -1,
    'local record field keeps shared literal');
  LocalArray[0] := 'larr-lit';
  Check(StringRefCount(LocalArray[0]) = -1,
    'local static array element keeps shared literal');
  LocalRec.Inner.Arr[0] := 'nested-lit';
  Check(StringRefCount(LocalRec.Inner.Arr[0]) = -1,
    'nested local record/array chain keeps shared literal');
end;

procedure AssignValuePar(ParText: UnicodeString);
begin
  ParText := 'value-par-lit';
  Check(StringRefCount(ParText) = -1, 'value parameter keeps shared literal');
end;

procedure AssignVarPar(var ParText: UnicodeString);
begin
  ParText := 'var-par-lit';
  Check(StringRefCount(ParText) = 1, 'var parameter owns a copy');
end;

procedure AssignOutPar(out ParText: UnicodeString);
begin
  ParText := 'out-par-lit';
  Check(StringRefCount(ParText) = 1, 'out parameter owns a copy');
end;

function MakeViaResult: UnicodeString;
begin
  Result := 'result-lit';
end;

function MakeViaName: UnicodeString;
begin
  MakeViaName := 'name-result-lit';
end;

function MakeCapturedProbe: TRefProbe;
var
  CapturedText: UnicodeString;
begin
  CapturedText := 'captured-lit';
  Result := function: NativeInt
    begin
      Result := StringRefCount(CapturedText);
    end;
end;

procedure CheckOwnedTargets;
var
  Holder: THolder;
  HeapRec: PRec;
  DynTexts: array of UnicodeString;
  Probe: TRefProbe;
begin
  GlobalText := 'global-lit';
  Check(StringRefCount(GlobalText) = 1, 'global owns a copy');
  GlobalAnsi := 'global-ansi-lit';
  Check(StringRefCount(GlobalAnsi) = 1, 'ansi global owns a copy');

  ThreadText := 'threadvar-lit';
  Check(StringRefCount(ThreadText) = 1, 'threadvar owns a copy');

  GlobalArray[0] := 'array-lit';
  Check(StringRefCount(GlobalArray[0]) = 1, 'static array element owns a copy');

  SetLength(DynTexts, 1);
  DynTexts[0] := 'dyn-lit';
  Check(StringRefCount(DynTexts[0]) = 1, 'dynamic array element owns a copy');

  GlobalRec.Text := 'grec-lit';
  Check(StringRefCount(GlobalRec.Text) = 1, 'global record field owns a copy');

  New(HeapRec);
  try
    HeapRec^.Text := 'heap-rec-lit';
    Check(StringRefCount(HeapRec^.Text) = 1, 'heap record field owns a copy');
  finally
    Dispose(HeapRec);
  end;

  Holder := THolder.Create;
  try
    Holder.FText := 'field-lit';
    Check(StringRefCount(Holder.FText) = 1, 'object field owns a copy');
  finally
    FreeAndNil(Holder);
  end;

  Check(StringRefCount(MakeViaResult) = 1, 'function result owns a copy');
  Check(StringRefCount(MakeViaName) = 1, 'name-assigned result owns a copy');

  Probe := MakeCapturedProbe();
  Check(Probe() = 1, 'captured local owns a copy');
end;

procedure CheckTypedConstSource;
begin
  Check(StringRefCount(TypedConstText) = -1, 'typed const holds shared literal');
  GlobalText := TypedConstText;
  Check(StringRefCount(GlobalText) = 1,
    'assignment from typed const materializes at run time');
end;

procedure CheckMutationIsolation;
var
  LocalText: UnicodeString;
begin
  LocalText := 'poke-me';
  GlobalText := 'poke-me';
  GlobalOther := 'poke-me';
  PWideChar(Pointer(GlobalText))[0] := 'X';
  Check(GlobalText = 'Xoke-me', 'owned copy accepts in-place mutation');
  Check(GlobalOther = 'poke-me', 'sibling global unaffected by mutation');
  Check(LocalText = 'poke-me', 'shared local unaffected by mutation');

  GlobalAnsi := 'poke-ansi';
  PAnsiChar(Pointer(GlobalAnsi))[0] := 'X';
  Check(GlobalAnsi = 'Xoke-ansi', 'owned ansi copy accepts in-place mutation');
end;

procedure CheckClassicRefcounting;
var
  AliasText: UnicodeString;
begin
  GlobalText := 'share-me';
  AliasText := GlobalText;
  Check(StringRefCount(GlobalText) = 2, 'heap assignment still shares');
  AliasText := '';
  Check(StringRefCount(GlobalText) = 1, 'release drops shared count');
  GlobalText := Copy('copy-lit', 1, 8);
  Check(StringRefCount(GlobalText) = 1, 'Copy of a literal owns storage');
end;

begin
  try
    CheckLocalStaysShared;
    AssignValuePar('seed');
    GlobalText := 'seed-var';
    AssignVarPar(GlobalText);
    AssignOutPar(GlobalText);
    CheckOwnedTargets;
    CheckTypedConstSource;
    CheckMutationIsolation;
    CheckClassicRefcounting;
    WriteLn('STRING_LITERAL_MATERIALIZE_OK');
  except
    on E: Exception do begin
      WriteLn('STRING_LITERAL_MATERIALIZE_FAIL ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
