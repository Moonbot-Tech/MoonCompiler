program mormot_variant_bson_probe;

{$mode delphi}

uses
  mormot.core.fpcx64mm,
{$ifdef unix}
  cthreads,
{$endif}
  SysUtils,
  Variants,
  mormot.core.base,
  mormot.core.data,
  mormot.core.text,
  mormot.core.variants,
  mormot.core.json,
  mormot.db.nosql.bson;

var
  Doc: Variant;
  Dict: IDocDict;
  Value: Variant;
  Bin: RawByteString;

begin
  GetVariantFromJsonField('0.123', False, Value, nil);
  If (TVarData(Value).VType <> varString) or
     (VariantTypeName(Value)^ <> 'String') or
     (VariantSaveJson(Value) <> '"0.123"') then
    Halt(1);
  Value := VariantLoadJson('123.1234');
  If (TVarData(Value).VType <> varString) or
     (VariantTypeName(Value)^ <> 'String') or
     (VariantSaveJson(Value) <> '"123.1234"') then
    Halt(2);
  Doc := _Json('{"FloatVal":24.4}');
  Value := Doc.FloatVal;
  If (VariantTypeName(Value)^ <> 'String') or
     (VariantSaveJson(Doc) <> '{"FloatVal":"24.4"}') then
    Halt(3);
  Dict := DocDict('{"FloatVal":24.4}');
  Value := Dict['FloatVal'];
  If (TVarData(Value).VType <> varDouble) or
     (VariantTypeName(Value)^ <> 'Double') or
     (Dict.ToJson(jsonCompact) <> '{"FloatVal":24.4}') then
    Halt(4);
  Doc := _Json('{"BSON":["awesome",5.05,1986]}');
  Bin := Bson(TDocVariantData(Doc));
  If (VariantSaveJson(Doc) <> '{"BSON":["awesome","5.05",1986]}') or
     (Length(Bin) <> 50) or
     (PInteger(Pointer(Bin))^ <> 50) or
     (BinToHex(Bin) <>
       '320000000442534F4E002700000002300008000000617765736F6D6500' +
       '02310005000000352E303500103200C20700000000') then
    Halt(5);
  Writeln('PASS moonbot-json-decimal-default-as-string');
end.
