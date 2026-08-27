program aggregate_init_unwind_semantic;

{$mode delphiunicode}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}cthreads,cwstring,{$endif UNIX}
  SysUtils;

var
  Trail: AnsiString = '';
  InitSeq: Integer = 0;
  Boom: Integer = 2;

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

var
  Direct: array of TProbe;
  Nested: array of TNested;
  Outer: array of TOuter;
begin
  Boom := 2;
  try
    SetLength(Direct, 3);
  except
    Trail := Trail + 'caught;';
  end;
  Check('direct-second', 'I1;I2;F1;caught;');

  Boom := 2;
  try
    SetLength(Nested, 3);
  except
    Trail := Trail + 'caught;';
  end;
  Check('nested-first', 'I1;I2;F1;caught;');

  Boom := 4;
  try
    SetLength(Nested, 3);
  except
    Trail := Trail + 'caught;';
  end;
  Check('nested-second', 'I1;I2;I3;I4;F3;F2;F1;caught;');

  { C-003: a failing custom Initialize owns only its own partial state.
    The automatically constructed fields are finalized by the RTL in
    reverse order; the record's own Finalize is not run - its Initialize
    never completed. This is a deliberate stronger contract than DCC64,
    which leaks the fields here. }
  Boom := 99;
  try
    SetLength(Outer, 2);
  except
    Trail := Trail + 'caught;';
  end;
  Check('custom-record-op', 'I1;OI;F1;caught;');

  Boom := 0;
  SetLength(Nested, 1);
  Nested := nil;
  Check('happy', 'I1;I2;I3;F3;F2;F1;');

  WriteLn('AGGREGATE_INIT_UNWIND_OK');
end.
