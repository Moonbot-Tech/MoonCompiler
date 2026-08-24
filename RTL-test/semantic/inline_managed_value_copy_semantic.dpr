program inline_managed_value_copy_semantic;

{ The inliner materializes a private copy for ANY managed by-value
  parameter the body writes - the dvl-0057 contour extended from
  Delphi-assign records to every managed carrier (deep-layer audit,
  journal 6).  The copy's release is observable: a refcounted death must
  land at the end of the inlined body, exactly where a real call's
  callee epilogue is - not at the caller's epilogue (the motive of the
  original doinlining guard, kept only for open arrays of managed).
  DCC64 inlines all of these; the O3 assembly oracle in run.py proves
  ours stay inlined too. }

{$APPTYPE CONSOLE}

uses
  {$ifdef FPC}
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  {$endif UNIX}
  {$endif FPC}
  SysUtils;

type
  TGuard = class(TInterfacedObject)
  public
    class var Alive: Integer;
    constructor Create;
    destructor Destroy; override;
  end;

  TManagedRec = record
    Intf: IInterface;
    Tag: Integer;
  end;

constructor TGuard.Create;
begin
  inherited Create;
  Inc(Alive);
end;

destructor TGuard.Destroy;
begin
  Dec(Alive);
  inherited Destroy;
end;

function ModifyRecByValue(R: TManagedRec): Integer; inline;
begin
  R.Tag := R.Tag + 1;
  Result := R.Tag;
end;

function ModifyStrByValue(S: string): Integer; inline;
begin
  S := S + 'x';
  Result := Length(S);
end;

function ReplaceAndRaise(R: TManagedRec): Integer; inline;
begin
  R.Intf := TGuard.Create;
  Result := R.Tag;
  raise Exception.Create('boom');
end;

procedure InterfaceCopyDiesWithBody;
var
  R: TManagedRec;
begin
  R.Intf := TGuard.Create;
  R.Tag := 41;
  If ModifyRecByValue(R) <> 42 then
    raise Exception.Create('rec copy value');
  If R.Tag <> 41 then
    raise Exception.Create('rec source modified');
  { the copy died at the end of the inlined body, so this release is the
    LAST reference - a caller-epilogue temp would keep the object alive }
  If TGuard.Alive <> 1 then
    raise Exception.CreateFmt('alive after call: %d', [TGuard.Alive]);
  R.Intf := nil;
  If TGuard.Alive <> 0 then
    raise Exception.CreateFmt('alive after nil: %d', [TGuard.Alive]);
end;

procedure StringCopyLeavesSource;
var
  L: string;
begin
  L := 'abc';
  If ModifyStrByValue(L) <> 4 then
    raise Exception.Create('str copy value');
  If L <> 'abc' then
    raise Exception.Create('str source modified');
end;

procedure UnwindBuriesTheCopy;
var
  R: TManagedRec;
  LCaught: Boolean;
begin
  R.Intf := TGuard.Create;
  R.Tag := 7;
  LCaught := False;
  try
    ReplaceAndRaise(R);
  except
    on E: Exception do
      LCaught := E.Message = 'boom';
  end;
  If not LCaught then
    raise Exception.Create('unwind: wrong exception');
  { the body replaced the COPY's reference with a fresh guard and raised:
    the unwind must bury the copy (and with it the fresh guard) before
    the handler runs - only the caller's original survives }
  If TGuard.Alive <> 1 then
    raise Exception.CreateFmt('alive after unwind: %d', [TGuard.Alive]);
  R.Intf := nil;
  If TGuard.Alive <> 0 then
    raise Exception.CreateFmt('alive after unwind nil: %d', [TGuard.Alive]);
end;

begin
  try
    InterfaceCopyDiesWithBody;
    StringCopyLeavesSource;
    UnwindBuriesTheCopy;
    WriteLn('INLINE_MANAGED_VALUE_COPY_OK');
  except
    on E: Exception do begin
      WriteLn('INLINE_MANAGED_VALUE_COPY_FAIL ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
