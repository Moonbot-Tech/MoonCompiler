program record_init_unwind_paths_semantic;

{ C-003 construction ownership on the non-array paths:
  - a standalone local record unwinds its constructed field prefix when a
    later field's Initialize raises (plain InitializeRecord used to leak
    everything here);
  - a failing outer custom Initialize does not keep the automatically
    constructed fields (stronger than DCC64, which leaks them);
  - the open-array value-parameter copy owns content AND raw buffer: a
    raise from the user's Assign finalizes every constructed element and
    releases the heap buffer (the bundled MM teardown census fails closed
    on any leaked block, so the repeat loop below would turn a buffer leak
    into a red run). }

{$mode delphiunicode}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}cthreads,cwstring,{$endif UNIX}
  SysUtils;

var
  Trail: AnsiString = '';
  InitSeq: Integer = 0;
  Boom: Integer = 0;
  AssignBoom: Boolean = False;

type
  TProbe = record
    Tag: Integer;
    class operator Initialize(var R: TProbe);
    class operator Finalize(var R: TProbe);
  end;

  TNested = record
    A, B, C: TProbe;
  end;

  TOuter = record
    A: TProbe;
    class operator Initialize(var R: TOuter);
    class operator Finalize(var R: TOuter);
  end;

  TRes = record
    Slot: Integer;
    class operator Initialize(out Dest: TRes);
    class operator Finalize(var Dest: TRes);
    class operator Assign(var Dest: TRes; const [ref] Src: TRes);
  end;

  THolder = class
  public
    FP: TProbe;
  end;

class operator TProbe.Initialize(var R: TProbe);
begin
  Inc(InitSeq);
  R.Tag := InitSeq;
  Trail := Trail + 'I' + IntToStr(InitSeq) + ';';
  if InitSeq = Boom then
    raise Exception.Create('boom');
end;

class operator TProbe.Finalize(var R: TProbe);
begin
  Trail := Trail + 'F' + IntToStr(R.Tag) + ';';
end;

class operator TOuter.Initialize(var R: TOuter);
begin
  Trail := Trail + 'OI;';
  if Boom = 99 then
    raise Exception.Create('outer boom');
end;

class operator TOuter.Finalize(var R: TOuter);
begin
  Trail := Trail + 'OF;';
end;

class operator TRes.Initialize(out Dest: TRes);
begin
  Dest.Slot := 100;
  Trail := Trail + 'i;';
end;

class operator TRes.Finalize(var Dest: TRes);
begin
  Trail := Trail + 'f' + IntToStr(Dest.Slot) + ';';
end;

class operator TRes.Assign(var Dest: TRes; const [ref] Src: TRes);
begin
  if AssignBoom and (Src.Slot = 20) then
    begin
      Trail := Trail + 'A!;';
      raise Exception.Create('assign boom');
    end;
  Dest.Slot := Src.Slot + 1;
  Trail := Trail + 'a;';
end;

procedure Check(const Name, Want: AnsiString);
begin
  if Trail <> Want then
    begin
      WriteLn('FAIL ', Name, ' got=', Trail, ' want=', Want);
      Halt(1);
    end;
  Trail := '';
  InitSeq := 0;
end;

procedure LocalNested;
var
  N: TNested;
begin
  N.A.Tag := N.A.Tag; { silence unused }
end;

procedure LocalOuter;
var
  R: TOuter;
begin
  R.A.Tag := R.A.Tag;
end;

procedure TakeRes(A: array of TRes);
begin
  Trail := Trail + 'y' + IntToStr(Length(A)) + ';';
end;

procedure TwoRes(A, B: TRes);
begin
  Trail := Trail + 'y' + IntToStr(A.Slot) + ':' + IntToStr(B.Slot) + ';';
end;

procedure TwoResInline(A, B: TRes); inline;
begin
  Trail := Trail + 'z' + IntToStr(A.Slot) + ':' + IntToStr(B.Slot) + ';';
end;

procedure TwoLocalsInline; inline;
var
  P, Q: TProbe;
begin
  Trail := Trail + 'w;';
  P.Tag := P.Tag;
  Q.Tag := Q.Tag;
end;

procedure CallOpenArray;
var
  Src: array[0..1] of TRes;
begin
  Src[0].Slot := 10;
  Src[1].Slot := 20;
  Trail := Trail + '|';
  TakeRes(Src);
  Trail := Trail + '|';
end;

procedure CallTwoRes;
var
  S1, S2: TRes;
begin
  S1.Slot := 10;
  S2.Slot := 20;
  Trail := Trail + '|';
  TwoRes(S1, S2);
  Trail := Trail + '|';
end;

procedure CallTwoResInline;
var
  S1, S2: TRes;
begin
  S1.Slot := 10;
  S2.Slot := 20;
  Trail := Trail + '|';
  TwoResInline(S1, S2);
  Trail := Trail + '|';
end;

var
  H: THolder;
  Round: Integer;
begin
  { standalone local: a later field's Initialize raises -> the constructed
    prefix is finalized in reverse, the raising field is not }
  Boom := 2;
  try
    LocalNested;
  except
    Trail := Trail + 'caught;';
  end;
  Check('local-field-throw', 'I1;I2;F1;caught;');

  { standalone local: the outer custom Initialize raises -> the
    automatically constructed fields are finalized, OF is not run }
  Boom := 99;
  try
    LocalOuter;
  except
    Trail := Trail + 'caught;';
  end;
  Check('local-outer-throw', 'I1;OI;F1;caught;');

  { happy standalone local still pairs I/F }
  Boom := 0;
  LocalNested;
  Check('local-happy', 'I1;I2;I3;F3;F2;F1;');

  { open-array copy: happy path unchanged }
  Boom := 0;
  AssignBoom := False;
  CallOpenArray;
  Check('openarray-happy', 'i;i;|i;i;a;a;y2;f11;f21;|f10;f20;');

  { open-array copy: the second Assign raises -> both constructed copies
    are finalized (assigned prefix and initialized tail) and the raw
    buffer is released; the source locals die normally }
  Boom := 0;
  for Round := 1 to 50 do
    begin
      AssignBoom := True;
      try
        CallOpenArray;
      except
        Trail := Trail + 'caught;';
      end;
      Check('openarray-assign-throw', 'i;i;|i;i;a;A!;f11;f100;f10;f20;caught;');
    end;
  AssignBoom := False;

  { scalar pre-call construction (C-003): a copy's Assign raises before
    the call - every already constructed copy is finalized through its
    guard local during unwind instead of leaking (the old pinned DCC64
    behavior leaked everything built). Real-call copies are built in
    argument evaluation order, which walks the paranode chain
    last-to-first: the SECOND parameter's copy is built first, its Assign
    (source slot 20) raises, so the first parameter's copy is never
    started - the guard finalizes the one initialized copy (slot 100) }
  AssignBoom := True;
  Trail := '';
  InitSeq := 0;
  try
    CallTwoRes;
  except
    Trail := Trail + 'caught;';
  end;
  Check('scalar-precall-throw', 'i;i;|i;A!;f100;f20;f10;caught;');
  AssignBoom := False;

  { the same through the inliner: copies and their guards live in the
    caller's frame. The frame is phased (every copy's Init, then the
    Assigns), and the Assign phase walks the paranode chain last-to-first:
    the SECOND parameter's Assign (source slot 20) runs first and raises,
    so both copies still hold their Init value and both are finalized
    through their guards }
  AssignBoom := True;
  Trail := '';
  try
    CallTwoResInline;
  except
    Trail := Trail + 'caught;';
  end;
  Check('inline-precall-throw', 'i;i;|i;i;A!;f100;f100;f20;f10;caught;');
  AssignBoom := False;

  { happy inline copies still pair and die inside the frame }
  Trail := '';
  CallTwoResInline;
  Check('inline-happy', 'i;i;|i;i;a;a;z11:21;f21;f11;|f20;f10;');

  { two inlined custom-Initialize locals: the second Init raises, the
    first local is finalized through its guard instead of leaking }
  Boom := 2;
  Trail := '';
  InitSeq := 0;
  try
    TwoLocalsInline;
  except
    Trail := Trail + 'caught;';
  end;
  Check('inline-locals-throw', 'I1;I2;F1;caught;');
  Boom := 0;

  { a class instance field with a raising Initialize must not double
    finalize: the record unwound its own state, the failed instance is
    released without running user Finalize on never-constructed state }
  Boom := 1;
  H := nil;
  try
    H := THolder.Create;
  except
    Trail := Trail + 'caught;';
  end;
  if H <> nil then
    begin
      WriteLn('FAIL holder instance survived');
      Halt(1);
    end;
  Check('class-field-throw', 'I1;caught;');

  Boom := 0;
  H := THolder.Create;
  H.Free;
  Check('class-field-happy', 'I1;F1;');

  WriteLn('RECORD_INIT_UNWIND_PATHS_OK');
end.
