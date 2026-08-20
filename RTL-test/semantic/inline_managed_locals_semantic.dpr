program inline_managed_locals_semantic;

{ Routines with managed locals inline, and the locals keep the measured
  Delphi lifetime.

  The audit's b668f07b repair kept every such routine out of the inliner -
  safe, but a call plus an implicit-finally frame remained for bodies that
  optimize to a single instruction (the AddOne shape runs ~6x faster
  inlined).  The inliner now converts the callee's managed locals into
  managed caller temps, wraps the inlined body in an implicit try..finally
  that finalizes them in reverse declaration order, and releases the slots
  to normal after the frame (the finally funclet is generated after the
  main pass and still references them).  Unreferenced locals get no temp
  at all.

  Every trail below is byte-identical to DCC64 36.0 with inlining on:
  the destructor fires at the inlined return point (before the statement
  after the call), two locals die in reverse, Exit routes through the
  cleanup, an exception finalizes the local during unwind BEFORE the
  caller's handler, and nested inlining keeps the inner/outer order. }

{$mode delphiunicode}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}cthreads,cwstring,{$endif UNIX}
  SysUtils;

var
  Trail: AnsiString = '';
  RecordInitializations: Integer = 0;
  RecordFinalizations: Integer = 0;

type
  TTag = class(TInterfacedObject)
  private
    FTag: AnsiChar;
  public
    constructor Create(ATag: AnsiChar);
    destructor Destroy; override;
  end;

  TTrackedRecord = record
    Value: Integer;
    class operator Initialize(var Dest: TTrackedRecord);
    class operator Finalize(var Dest: TTrackedRecord);
  end;

  TTrackedAggregate = record
    Prefix: Integer;
    Item: TTrackedRecord;
  end;

class operator TTrackedRecord.Initialize(var Dest: TTrackedRecord);
begin
  Inc(RecordInitializations);
  Dest.Value := 0;
end;

class operator TTrackedRecord.Finalize(var Dest: TTrackedRecord);
begin
  Inc(RecordFinalizations);
  Dest.Value := 0;
end;

constructor TTag.Create(ATag: AnsiChar);
begin
  inherited Create;
  FTag := ATag;
end;

destructor TTag.Destroy;
begin
  Trail := Trail + FTag;
  inherited Destroy;
end;

procedure UseTag(ATag: AnsiChar); inline;
var
  L: IInterface;
begin
  L := TTag.Create(ATag);
  Trail := Trail + '.';
end;

procedure AppendGlobal(ATag: AnsiChar); inline;
begin
  Trail := Trail + ATag;
end;

procedure TwoLocals; inline;
var
  A, B: IInterface;
begin
  A := TTag.Create('a');
  B := TTag.Create('b');
  Trail := Trail + '.';
end;

procedure WithExit(Flag: Boolean); inline;
var
  L: IInterface;
begin
  L := TTag.Create('e');
  if Flag then
  begin
    Trail := Trail + '!';
    Exit;
  end;
  Trail := Trail + '.';
end;

procedure WithRaise; inline;
var
  L: IInterface;
begin
  L := TTag.Create('r');
  raise Exception.Create('boom');
end;

procedure Inner; inline;
var
  L: IInterface;
begin
  L := TTag.Create('i');
  Trail := Trail + '.';
end;

procedure Outer; inline;
var
  L: IInterface;
begin
  L := TTag.Create('o');
  Inner;
  Trail := Trail + '+';
end;

procedure UseTrackedRecord; inline;
var
  R: TTrackedRecord;
begin
  R.Value := 7;
  if R.Value <> 7 then
    Halt(2);
end;

procedure UseTrackedAggregate; inline;
var
  R: TTrackedAggregate;
  Items: array[0..1] of TTrackedRecord;
begin
  R.Prefix := 1;
  R.Item.Value := 2;
  Items[0].Value := 3;
  Items[1].Value := 4;
  if R.Prefix + R.Item.Value + Items[0].Value + Items[1].Value <> 10 then
    Halt(3);
end;

var
  Fails: Integer = 0;
  i: Integer;
  InitBefore,
  FinalizeBefore: Integer;

procedure Check(const Name, Want: AnsiString);
begin
  if Trail <> Want then
  begin
    WriteLn('FAIL ', Name, ' got=', Trail, ' want=', Want);
    Inc(Fails);
  end;
  Trail := '';
end;

begin
  Trail := '';
  AppendGlobal('g');
  Check('late-managed-temp-guard', 'g');
  for i := 1 to 3 do
  begin
    UseTag(AnsiChar(Ord('a') + i - 1));
    Trail := Trail + '|';
  end;
  Check('loop-reentry', '.a|.b|.c|');
  TwoLocals;
  Check('reverse-order', '.ba');
  WithExit(True);
  Check('exit-path', '!e');
  try
    WithRaise;
  except
    Trail := Trail + 'x';
  end;
  Check('unwind-before-handler', 'rx');
  Outer;
  Check('nested-inline', '.i+o');
  InitBefore := RecordInitializations;
  FinalizeBefore := RecordFinalizations;
  UseTrackedRecord;
  if (RecordInitializations <> InitBefore + 1) or
     (RecordFinalizations <> FinalizeBefore + 1) then
  begin
    WriteLn('FAIL custom-record-callsite init=',
      RecordInitializations - InitBefore, ' fini=',
      RecordFinalizations - FinalizeBefore);
    Inc(Fails);
  end;
  InitBefore := RecordInitializations;
  FinalizeBefore := RecordFinalizations;
  UseTrackedAggregate;
  if (RecordInitializations <> InitBefore + 3) or
     (RecordFinalizations <> FinalizeBefore + 3) then
  begin
    WriteLn('FAIL custom-aggregate-callsite init=',
      RecordInitializations - InitBefore, ' fini=',
      RecordFinalizations - FinalizeBefore);
    Inc(Fails);
  end;
  if Fails <> 0 then
    Halt(1);
  WriteLn('INLINE_MANAGED_SEMANTIC_OK');
end.
