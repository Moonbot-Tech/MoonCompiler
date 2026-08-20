program generic_ctor_constraint_semantic;

{ The `constructor` constraint accepts a concrete class (every class has the
  inherited public parameterless Create) and a forwarded generic parameter
  that carries the constraint itself; a forward without it is rejected at
  declaration time (tests/webtbs/tw41770a.pp, DCC E2513 parity - the red
  form of audit b359f605: the previous compiler accepted the forward and
  produced a specialization no constraint had ever proven). }

{$mode delphiunicode}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}cthreads,cwstring,{$endif UNIX}
  SysUtils;

type
  TBase = class
  public
    Tag: Integer;
  end;

  TThing = class(TBase)
  public
    constructor Create;
  end;

  TNeedCtor<X: TBase, constructor> = class
    function Make: X;
  end;

  TForward<T: TBase, constructor> = class
    FInner: TNeedCtor<T>;
    function MakeInner: T;
  end;

constructor TThing.Create;
begin
  inherited Create;
  Tag := 42;
end;

function TNeedCtor<X>.Make: X;
begin
  Result := X.Create;
end;

function TForward<T>.MakeInner: T;
begin
  FInner := TNeedCtor<T>.Create;
  Result := FInner.Make;
  FInner.Free;
end;

var
  Direct: TNeedCtor<TThing>;
  Fwd: TForward<TThing>;
  Made: TThing;
  Fails: Integer = 0;
begin
  Direct := TNeedCtor<TThing>.Create;
  Made := Direct.Make;
  if Made.Tag <> 42 then
  begin
    WriteLn('FAIL direct Tag=', Made.Tag);
    Inc(Fails);
  end;
  Made.Free;
  Direct.Free;
  Fwd := TForward<TThing>.Create;
  Made := Fwd.MakeInner;
  if Made.Tag <> 42 then
  begin
    WriteLn('FAIL forwarded Tag=', Made.Tag);
    Inc(Fails);
  end;
  Made.Free;
  Fwd.Free;
  if Fails <> 0 then
    Halt(1);
  WriteLn('GENERIC_CTOR_SEMANTIC_OK');
end.
