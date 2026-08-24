program inline_const_alias_semantic;

{ The const-parameter inliner gate distinguishes storage owned by the callee
  from captured/non-local storage.  Pure readers over a global are admitted;
  a nested routine which writes the argument's source must preserve the real
  call's value, whether by retaining the call or by materializing a safe temp.
  This matters for both ABI forms: Win64 aliases this record through a const
  reference, while Linux x86-64 passes its snapshot by value. }

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
  TBig = record
    A, B, C, D: Integer;
  end;

var
  GBig: TBig;

function SumBig(const V: TBig): Integer; inline;
begin
  Result := V.A + V.B + V.C + V.D;
end;

procedure PureGlobalRead;
begin
  GBig.A := 10;
  GBig.B := 20;
  GBig.C := 30;
  GBig.D := 40;
  If SumBig(GBig) <> 100 then
    raise Exception.Create('pure global read');
end;

procedure CapturedAlias;
var
  X: TBig;
  Actual: Integer;

  function ReadAfterWrite(const V: TBig): Integer; inline;
  begin
    X.A := X.A + 1;
    Result := V.A;
  end;

begin
  X.A := 41;
  Actual := ReadAfterWrite(X);
  {$ifdef WINDOWS}
  If Actual <> 42 then
  {$else WINDOWS}
  If Actual <> 41 then
  {$endif WINDOWS}
    raise Exception.CreateFmt('captured const record: result=%d, source=%d',
      [Actual, X.A]);
  If X.A <> 42 then
    raise Exception.CreateFmt('captured record mutation: result=%d, source=%d',
      [Actual, X.A]);
end;

procedure CapturedScalar;
var
  X: Integer;
  Actual: Integer;

  function ReadScalarAfterWrite(const V: Integer): Integer; inline;
  begin
    X := X + 1;
    Result := V;
  end;

begin
  X := 41;
  Actual := ReadScalarAfterWrite(X);
  If Actual <> 41 then
    raise Exception.CreateFmt('captured const scalar: result=%d, source=%d',
      [Actual, X]);
  If X <> 42 then
    raise Exception.CreateFmt('captured scalar mutation: result=%d, source=%d',
      [Actual, X]);
end;

begin
  try
    PureGlobalRead;
    CapturedAlias;
    CapturedScalar;
    WriteLn('INLINE_CONST_ALIAS_OK');
  except
    on E: Exception do begin
      WriteLn('INLINE_CONST_ALIAS_FAIL ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
