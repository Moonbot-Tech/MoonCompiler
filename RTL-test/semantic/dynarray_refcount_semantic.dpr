program dynarray_refcount_semantic;

{$ifdef FPC}
  {$mode delphi}
{$endif}

uses
  {$ifdef FPC}
  mormot.core.fpcx64mm,
  {$ifdef UNIX}cthreads,cwstring,{$endif UNIX}
  {$endif}
  SysUtils;

type
  TTracked = record
    Value: Integer;
    class var Initialized: Integer;
    class var Finalized: Integer;
    class operator Initialize(out Dest: TTracked);
    class operator Finalize(var Dest: TTracked);
  end;
  TTrackedArray = array of TTracked;

class operator TTracked.Initialize(out Dest: TTracked);
begin
  Inc(Initialized);
  Dest.Value:=0;
end;

class operator TTracked.Finalize(var Dest: TTracked);
begin
  Inc(Finalized);
end;

procedure Fail(const Name: UnicodeString);
begin
  WriteLn('FAIL ',Name);
  Halt(1);
end;

procedure ReadByValue(Value: TTrackedArray); noinline;
begin
  If Value=nil then
    exit;
  If (Length(Value)<>4) or (Value[2].Value<>42) then
    Fail('by-value contents');
end;

procedure ReleaseLocal(Value: TTrackedArray); noinline;
begin
  Value:=nil;
end;

procedure RaiseWithValue(Value: TTrackedArray); noinline;
begin
  If Length(Value)<>4 then
    Fail('exception value length');
  raise Exception.Create('expected');
end;

var
  Values: TTrackedArray;
begin
  TTracked.Initialized:=0;
  TTracked.Finalized:=0;
  SetLength(Values,4);
  Values[2].Value:=42;
  If TTracked.Initialized<>4 then
    Fail('element initialization');

  ReadByValue(Values);
  If (TTracked.Initialized<>4) or (TTracked.Finalized<>0) then
    Fail('ordinary by-value lifetime');

  ReleaseLocal(Values);
  If (Length(Values)<>4) or (Values[2].Value<>42) or
     (TTracked.Finalized<>0) then
    Fail('local reassignment keeps caller alive');

  try
    RaiseWithValue(Values);
    Fail('exception missing');
  except
    on E: Exception do
      If E.Message<>'expected' then
        Fail('exception identity');
  end;
  If (Length(Values)<>4) or (Values[2].Value<>42) or
     (TTracked.Finalized<>0) then
    Fail('exception cleanup keeps caller alive');

  Values:=Values;
  If (Length(Values)<>4) or (TTracked.Finalized<>0) then
    Fail('self assignment');
  Values:=nil;
  If TTracked.Finalized<>4 then
    Fail('last reference finalizes once');

  ReadByValue(nil);
  WriteLn('DYNARRAY_REFCOUNT_SEMANTIC_OK');
end.
