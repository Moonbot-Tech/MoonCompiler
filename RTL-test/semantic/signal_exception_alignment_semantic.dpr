program signal_exception_alignment_semantic;

{ %TARGET=linux }

{ Hardware-trap to Pascal-exception conversion must survive ANY stack
  parity at the faulting instruction.  A routine compiled without a stack
  frame traps at rsp = 8 (mod 16), a framed one at rsp = 0; the signal
  trampoline synthesizes a call into the raise machinery and must restore
  the ABI alignment for both parities, or the aligned SSE spills inside
  libgcc's unwinder die with SIGSEGV (the historic shape: -O2 frameless
  `div` inside try/except crashed, -O- worked).  The forms below pin the
  conversion across frame shapes, call depth, signal kinds, nested
  try/finally, repeated raises and managed locals. }

{$mode delphi}

uses
  SysUtils;

var
  TotalScore: Integer;

{ frameless under -O2: compiles to bare mov/idiv/ret }
function FramelessDiv(d: Integer): Integer;
begin
  Result := 100 div d;
end;

{ forced frame: local array keeps the frame alive on every O-level }
function FramedDiv(d: Integer): Integer;
var
  pad: array[0..15] of Integer;
begin
  pad[0] := 100;
  pad[15] := d;
  Result := pad[0] div pad[15];
end;

{ trap two frameless calls deep: the unwinder walks the full chain }
function DeepInner(d: Integer): Integer;
begin
  Result := 1000 div d;
end;

function DeepOuter(d: Integer): Integer;
begin
  Result := DeepInner(d) + 1;
end;

{ SIGSEGV conversion (nil dereference) in a frameless routine }
function NilRead(p: PInteger): Integer;
begin
  Result := p^;
end;

procedure Check(name: string; got, want: Integer);
begin
  if got = want then
    Inc(TotalScore)
  else
    WriteLn('FAIL ', name, ': got ', got, ' want ', want);
end;

function TryFramelessDiv(d: Integer): Integer;
begin
  try
    Result := FramelessDiv(d);
  except
    Result := 7;
  end;
end;

function TryFramedDiv(d: Integer): Integer;
begin
  try
    Result := FramedDiv(d);
  except
    Result := 8;
  end;
end;

function TryDeep(d: Integer): Integer;
begin
  try
    Result := DeepOuter(d);
  except
    Result := 9;
  end;
end;

function TryNil(p: PInteger): Integer;
begin
  try
    Result := NilRead(p);
  except
    Result := 10;
  end;
end;

function TryNestedWithFinally(d: Integer): Integer;
var
  cleaned: Integer;
begin
  cleaned := 0;
  Result := 0;
  try
    try
      try
        Result := FramelessDiv(d);
      finally
        Inc(cleaned);
      end;
    except
      Result := 11;
    end;
  finally
    Inc(cleaned, 10);
  end;
  Result := Result + cleaned * 100;
end;

function TryReraise(d: Integer): Integer;
begin
  Result := 0;
  try
    try
      Result := FramelessDiv(d);
    except
      raise;
    end;
  except
    Result := 12;
  end;
end;

{ a managed local must survive the unwind untouched }
function TryManagedLocal(d: Integer): Integer;
var
  s: AnsiString;
begin
  s := 'abc';
  try
    Result := FramelessDiv(d);
  except
    Result := Length(s) + 20;
  end;
end;

var
  i, acc, zero: Integer;
begin
  TotalScore := 0;
  zero := ParamCount;  { runtime zero: keep the traps out of const folding }

  Check('frameless-ok', TryFramelessDiv(zero + 5), 20);
  Check('frameless-trap', TryFramelessDiv(zero), 7);
  Check('framed-ok', TryFramedDiv(zero + 4), 25);
  Check('framed-trap', TryFramedDiv(zero), 8);
  Check('deep-trap', TryDeep(zero), 9);
  Check('nil-trap', TryNil(nil), 10);
  Check('nested-finally-trap', TryNestedWithFinally(zero), 11 + 11 * 100);
  Check('nested-finally-ok', TryNestedWithFinally(zero + 4), 25 + 11 * 100);
  Check('reraise-trap', TryReraise(zero), 12);
  Check('managed-local-trap', TryManagedLocal(zero), 23);

  { repeated conversions in a loop: the fault stack state must not decay }
  acc := 0;
  for i := 1 to 5 do
    acc := acc + TryFramelessDiv(zero);
  Check('repeated-traps', acc, 35);

  if TotalScore = 11 then
    WriteLn('SIGEXC_ALIGN_PASS')
  else
    WriteLn('SIGEXC_ALIGN_FAILED ', TotalScore, '/11');
end.
