program managed_out_forwarding_semantic;

{$ifdef FPC}
  {$mode delphi}
{$endif}

{ Semantic pin for managed out-parameter forwarding: the out slot is
  finalized exactly once on entry, survives exceptions raised inside the
  callee chain without double release, and interface refcounts balance.
  Covers string, interface and dynamic array through a forwarding
  wrapper (audit pack A, item 2). }

uses
  {$ifdef FPC}
  mormot.core.fpcx64mm,
  {$endif}
  SysUtils;

type
  ICounted = interface
    ['{1D2F5C3A-8B41-4E8E-9C77-2A61F0B4D9E1}']
    function Id: Integer;
  end;

  TCounted = class(TInterfacedObject, ICounted)
  private
    FId: Integer;
  public
    constructor Create(AId: Integer);
    destructor Destroy; override;
    function Id: Integer;
  end;

var
  LiveCount: Integer;

procedure Fail(const Msg: string);
begin
  WriteLn('FAIL ', Msg);
  Halt(1);
end;

constructor TCounted.Create(AId: Integer);
begin
  inherited Create;
  FId := AId;
  Inc(LiveCount);
end;

destructor TCounted.Destroy;
begin
  Dec(LiveCount);
  inherited;
end;

function TCounted.Id: Integer;
begin
  Result := FId;
end;

{ string chain }

procedure GetStrInner(out R: UnicodeString; RaiseIt: Boolean);
begin
  if RaiseIt then
    raise EAbort.Create('boom');
  R := 'fresh-' + IntToStr(42);
end;

procedure GetStrForward(out R: UnicodeString; RaiseIt: Boolean);
begin
  GetStrInner(R, RaiseIt);
end;

{ interface chain }

procedure GetIntfInner(out R: ICounted; RaiseIt: Boolean);
begin
  if RaiseIt then
    raise EAbort.Create('boom');
  R := TCounted.Create(7);
end;

procedure GetIntfForward(out R: ICounted; RaiseIt: Boolean);
begin
  GetIntfInner(R, RaiseIt);
end;

{ dynamic array chain }

procedure GetArrInner(out R: TBytes; RaiseIt: Boolean);
begin
  if RaiseIt then
    raise EAbort.Create('boom');
  SetLength(R, 3);
  R[0] := 1; R[1] := 2; R[2] := 3;
end;

procedure GetArrForward(out R: TBytes; RaiseIt: Boolean);
begin
  GetArrInner(R, RaiseIt);
end;

var
  S, SAlias: UnicodeString;
  V: ICounted;
  B, BAlias: TBytes;
  Raised: Boolean;

begin
  { string: prefilled shared value must be released exactly once }
  S := 'prefilled-' + IntToStr(1);
  SAlias := S;
  GetStrForward(S, False);
  If S <> 'fresh-42' then
    Fail('string forwarding result');
  If SAlias <> 'prefilled-1' then
    Fail('string alias corrupted');

  { string: exception inside the chain must not double-release }
  S := 'prefilled-' + IntToStr(2);
  SAlias := S;
  Raised := False;
  try
    GetStrForward(S, True);
  except
    on EAbort do
      Raised := True;
  end;
  If not Raised then
    Fail('string exception not raised');
  If SAlias <> 'prefilled-2' then
    Fail('string alias corrupted after exception');
  { S itself is in a valid (finalized or unchanged) state: assigning to
    it must be safe }
  S := 'after';
  If S <> 'after' then
    Fail('string slot unusable after exception');

  { interface: prefilled reference released exactly once }
  LiveCount := 0;
  V := TCounted.Create(1);
  If LiveCount <> 1 then
    Fail('interface live baseline');
  GetIntfForward(V, False);
  If (V = nil) or (V.Id <> 7) then
    Fail('interface forwarding result');
  If LiveCount <> 1 then
    Fail(Format('interface live after success: %d', [LiveCount]));

  Raised := False;
  try
    GetIntfForward(V, True);
  except
    on EAbort do
      Raised := True;
  end;
  If not Raised then
    Fail('interface exception not raised');
  V := nil;
  If LiveCount <> 0 then
    Fail(Format('interface live after exception: %d', [LiveCount]));

  { dynamic array: shared value survives, slot reusable }
  SetLength(B, 2);
  B[0] := 9; B[1] := 8;
  BAlias := B;
  GetArrForward(B, False);
  If (Length(B) <> 3) or (B[2] <> 3) then
    Fail('array forwarding result');
  If (Length(BAlias) <> 2) or (BAlias[0] <> 9) then
    Fail('array alias corrupted');
  Raised := False;
  try
    GetArrForward(B, True);
  except
    on EAbort do
      Raised := True;
  end;
  If not Raised then
    Fail('array exception not raised');
  SetLength(B, 1);
  If Length(B) <> 1 then
    Fail('array slot unusable after exception');

  WriteLn('MANAGED_OUT_FORWARDING_PASS');
end.
