program mormot_record_fields_rtti_probe;

{$ifdef FPC}
  {$mode delphi}
{$endif FPC}

uses
  {$ifdef FPC}
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  {$endif UNIX}
  {$endif FPC}
  mormot.core.rtti;

type
  TNumericSet = set of 0..15;
  TEnumValue = (evFirst, evSecond, evThird);
  TEnumSet = set of TEnumValue;

  {$RTTI EXPLICIT FIELDS([vcPublic]) METHODS([]) PROPERTIES([])}
  TNumericSetRecord = record
  public
    Values: TNumericSet;
  end;

  TEnumSetRecord = record
  public
    Values: TEnumSet;
  end;

var
  Fields: TRttiRecordAllFields;
  Failure: Integer;
  RecordSize: NativeInt;
begin
  Failure:=0;
  RecordSize:=-1;
  Fields:=PRttiInfo(TypeInfo(TNumericSetRecord))^.RecordAllFields(RecordSize);
  if RecordSize<>SizeOf(TNumericSetRecord) then
    Failure:=Failure or 1;
  if Fields<>nil then
    Failure:=Failure or 2;

  RecordSize:=-1;
  Fields:=PRttiInfo(TypeInfo(TEnumSetRecord))^.RecordAllFields(RecordSize);
  if RecordSize<>SizeOf(TEnumSetRecord) then
    Failure:=Failure or 4;
  if Length(Fields)<>1 then
    Failure:=Failure or 8
  else
  begin
    if Fields[0].TypeInfo<>PRttiInfo(TypeInfo(TEnumSet)) then
      Failure:=Failure or 16;
    if Fields[0].Offset<>0 then
      Failure:=Failure or 32;
  end;

  if Failure<>0 then
  begin
    WriteLn('FAIL ',Failure);
    Halt(Failure);
  end;

  WriteLn('MORMOT_RECORD_FIELDS_RTTI_PASS');
end.
