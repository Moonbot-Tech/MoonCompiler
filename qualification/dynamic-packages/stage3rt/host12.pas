program host12;

{ Verifies the move into the RTL - uses SysUtils' LoadPackage /
  UnloadPackage as-is instead of 40 lines of user code.

  LazyPkg is a "lazy" package that deliberately omits UnRegisterClass in
  finalization. UnloadPackage's module-unload hook (UnRegisterModuleClasses,
  registered by Classes) must clear leftover registrations belonging to the
  departing image for a GetClass walk after unload to be safe.

  Expected:
    before unload  GetClass(TLazyPlugin) = TRUE
    after unload   GetClass(TLazyPlugin) = FALSE  (cleared by the hook)
    after unload   GetClass(TPersistent) = TRUE   (other images untouched)
    exit 0 (clean, including the exit path)

  Every expectation is machine-checked with Require. If values were only
  printed, over-removal (a regression where TPersistent becomes FALSE)
  would pass silently with exit 0 - which is exactly why this guard exists. }

{$mode delphi}

uses
  Windows,
  SysUtils,
  Classes;

var
  GFailed: Boolean = False;

{ Prints nothing on success - to keep the output format above unchanged.
  Speaks up only on a mismatch, and calls Halt(1) at the end. }
procedure Require(const AWhat: string; AActual, AExpected: Boolean);
const
  NAMES: array[Boolean] of string = ('FALSE', 'TRUE');
begin
  if AActual <> AExpected then
  begin
    WriteLn('  [FAIL] ', AWhat, ' = ', NAMES[AActual], ' (expected ', NAMES[AExpected], ')');
    GFailed := True;
  end;
end;

{ Isolated so the temporary AnsiStrings (package literals) are released before unload - unload contract }
procedure RunPlugin;
var
  LCls: TPersistentClass;
  LObj: TPersistent;
begin
  LCls := GetClass('TLazyPlugin');
  WriteLn('GetClass loaded    : ', Assigned(LCls));
  Require('TLazyPlugin after load', Assigned(LCls), True);
  if not Assigned(LCls) then
  begin
    Exit;
  end;

  LObj := LCls.Create;
  try
    WriteLn('ClassName         : ', LObj.ClassName);
    WriteLn('Parent            : ', LObj.ClassParent.ClassName);
  finally
    LObj.Free;
  end;
end;

var
  GLib: HMODULE;
  GLazy: Boolean;
  GPersist: Boolean;
begin
  GLazy := Assigned(GetClass('TLazyPlugin'));
  WriteLn('GetClass pre-load  : ', GLazy);
  Require('TLazyPlugin before load', GLazy, False);

  GLib := LoadPackage('LazyPkg.fpl');
  WriteLn('LoadPackage       : ', GLib <> 0);

  RunPlugin;

  UnloadPackage(GLib);
  GLazy := Assigned(GetClass('TLazyPlugin'));
  WriteLn('Lazy unloaded      : ', GLazy, ' (expected FALSE - cleared by hook)');
  Require('TLazyPlugin after unload', GLazy, False);

  GPersist := Assigned(GetClass('TPersistent'));
  WriteLn('Persist unloaded   : ', GPersist, ' (expected TRUE - no over-removal)');
  Require('TPersistent after unload (over-removal)', GPersist, True);

  { Second cycle - check that reloading still works }
  GLib := LoadPackage('LazyPkg.fpl');
  GLazy := Assigned(GetClass('TLazyPlugin'));
  WriteLn('GetClass reloaded  : ', GLazy);
  Require('TLazyPlugin after reload', GLazy, True);

  UnloadPackage(GLib);
  GLazy := Assigned(GetClass('TLazyPlugin'));
  WriteLn('Lazy re-unloaded   : ', GLazy);
  Require('TLazyPlugin after re-unload', GLazy, False);

  if GFailed then
  begin
    WriteLn('host12 FAILED');
    Halt(1);
  end;

  WriteLn('host12 ok');
end.
