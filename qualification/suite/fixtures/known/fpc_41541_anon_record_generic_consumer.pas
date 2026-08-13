program Fpc41541AnonRecordGenericConsumer;

{$mode objfpc}

uses
  fpc_41541_anon_record_generic_unit;

type
  TFoo = class end;
  TTest = specialize TKeywordDictionary<TFoo>;

begin
end.
