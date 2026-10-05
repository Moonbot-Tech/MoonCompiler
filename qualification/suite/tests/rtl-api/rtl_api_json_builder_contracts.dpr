program rtl_api_json_builder_contracts;

{$mode delphiunicode}
{$modeswitch anonymousfunctions}

uses
  {$ifdef unix}cwstring,{$endif}
  SysUtils, Classes, Rtti, Variants, StreamEx, System.JSON, System.JSON.Types,
  System.JSON.Writers, System.JSON.Readers, System.JSON.Builders;

procedure Check(Condition: Boolean; const Name: string);
begin
  If not Condition then
    raise Exception.Create(Name);
end;

procedure Build;
var
  Text: TStringWriter;
  Writer: TJsonTextWriter;
  Builder: TJSONObjectBuilder;
  Root: TJSONCollectionBuilder.TPairs;
  Sub: TJSONCollectionBuilder.TElements;
  Value: TJSONValue;
  JSON: string;
  Binary, Items, Nested: Variant;
begin
  Text := TStringWriter.Create;
  Writer := TJsonTextWriter.Create(Text, False);
  Builder := TJSONObjectBuilder.Create(Writer);
  try
    Root := Builder.BeginObject;
    Sub := Root.BeginArray('items').Add(1).AsRoot;
    Sub.AddElements('[2,{"x":3}]');
    Sub.EndAll;
    Check(Sub.Ended, 'scoped EndAll');
    Check(Builder.ParentType = TJSONCollectionBuilder.TParentType.Pairs, 'parent survives scoped EndAll');
    Builder.ParentObject.Add('tail', True);
    Root.Add('quoted', 'a"b\c' + #10 + #$0416);
    Binary := VarArrayCreate([5, 7], varByte);
    Binary[5] := 1;
    Binary[6] := 2;
    Binary[7] := 255;
    Root.Add('bytes', Binary);
    Items := VarArrayCreate([5, 6], varVariant);
    Nested := VarArrayCreate([-1, 0], varVariant);
    Nested[-1] := 'inner';
    Nested[0] := 42;
    Items[5] := 7;
    Items[6] := Nested;
    Root.Add('array', Items);
    Root.AddPairs('{"extra":"value"}');
    Root.EndObject;
    JSON := Builder.AsJSON;
    Value := TJSONValue.ParseJSONValue(UnicodeString(JSON), True, True);
    try
      Check(Value.FindValue('items[2].x').Value = '3', 'nested raw JSON elements');
      Check(Value.FindValue('extra').Value = 'value', 'raw JSON pairs');
      Check(Value.FindValue('tail').Value = 'true', 'parent fluent continuation');
      Check(Value.FindValue('quoted').Value = 'a"b\c' + #10 + #$0416, 'string escaping and Unicode');
      Check(Value.FindValue('bytes').Value = 'AQL/', 'variant byte array with nonzero lower bound');
      Check((Value.FindValue('array[0]').Value = '7') and
        (Value.FindValue('array[1][0]').Value = 'inner') and
        (Value.FindValue('array[1][1]').Value = '42'), 'nested Variant arrays as property values');
    finally
      Value.Free;
    end;
    try
      Root.Add('closed', 1);
      Check(False, 'closed builder accepts a value');
    except
      on EJSONCollectionBuilderError do ;
    end;
    Builder.Clear.BeginObject.Add('fresh', 7).EndObject;
    Check(Builder.AsJSON = '{"fresh":7}', 'Clear resets writer and content');
    Builder.Clear.BeginObject.BeginArray('unfinished').BeginObject.Add('discarded', 1);
    Builder.Clear.BeginObject.Add('after', 2).EndObject;
    Check(Builder.AsJSON = '{"after":2}', 'Clear discards unfinished containers');
    Builder.Clear;
    Root := Builder.BeginObject;
    try
      Root.AddPairs('{"bad":');
      Check(False, 'invalid raw JSON accepted');
    except
      on E: Exception do
        Check(E.Message <> 'invalid raw JSON accepted', 'raw JSON validation');
    end;
    Root.Add('good', 2).EndObject;
    Check(Builder.AsJSON = '{"good":2}', 'invalid raw JSON did not write a partial value');
  finally
    Builder.Free;
    Writer.Free;
  end;
  Check(Text.ToString = '{"good":2}', 'caller writer is still alive');
  Text.Free;
end;

procedure IterateReader(Reader: TJsonReader);
var
  Iter: TJSONIterator;
begin
  Iter := TJSONIterator.Create(Reader,
    procedure(R: TJsonReader)
    begin
      R.Rewind;
    end);
  try
    Check(Iter.Next and (Iter.&Type = TJsonToken.StartObject) and (Iter.Depth = 0), 'root token');
    Check(Iter.Recurse and (Iter.Depth = 1), 'enter root');
    Check(Iter.Next('items') and (Iter.&Type = TJsonToken.StartArray), 'Next exact key');
    Check(Iter.Recurse, 'enter array');
    Check(Iter.Next('1') and (Iter.Index = 1) and (Iter.AsInteger = 22), 'Next array index');
    Check(Iter.Path = 'items[1]', 'array path');
    Check(Iter.GetPath(1) = 'items[1]', 'relative root path');
    Check(Iter.GetPath(2) = '[1]', 'relative array path');
    Iter.Return;
    Check(Iter.Depth = 1, 'return parent depth');
    Check(Iter.Next('end') and Iter.AsBoolean, 'return did not consume next property');
    Check(not Iter.Next, 'end of root level');
    Iter.Return;
    Check(not Iter.InRecurse, 'out of root');
    Check(Iter.Find('nested["name"]') and (Iter.AsString = #$0416#$D83D#$DE80), 'quoted Unicode lookup');
    Check(Iter.AsValue.AsString = Iter.AsString, 'AsValue retains actual value');
    Check(not Iter.Find('nested.Name'), 'keys are case sensitive');
    Iter.Rewind;
    Iter.Recurse;
    Check(Iter.Next('nested') and (Iter.&Type = TJsonToken.StartObject), 'armed root recursion');
    Check(Iter.Next('end') and Iter.AsBoolean, 'Next skips nested container');
  finally
    Iter.Free;
  end;
end;

procedure Readers;
var
  Reader: TJsonTextReader;
  ObjectReader: TJsonObjectReader;
  Root: TJSONValue;
  Iter: TJSONIterator;
  Data: string;
begin
  Data := '{"items":[11,22,{"ignored":0}],"nested":{"name":"\u0416\ud83d\ude80"},"end":true}';
  Reader := TJsonTextReader.Create(TStringReader.Create(Data));
  try
    IterateReader(Reader);
  finally
    Reader.Free;
  end;
  Root := TJSONValue.ParseJSONValue(UnicodeString(Data), True, True);
  ObjectReader := TJsonObjectReader.Create(Root);
  try
    IterateReader(ObjectReader);
  finally
    ObjectReader.Free;
    Root.Free;
  end;
  Reader := TJsonTextReader.Create(TStringReader.Create('[1]'));
  Iter := TJSONIterator.Create(Reader);
  try
    try
      Iter.Rewind;
      Check(False, 'Rewind without callback');
    except
      on EJSONIteratorError do ;
    end;
  finally
    Iter.Free;
    Reader.Free;
  end;
  Reader := TJsonTextReader.Create(TStringReader.Create('[18446744073709551615,1e2]'));
  try
    Check(Reader.Read and Reader.Read and (Reader.Value.AsUInt64 = High(UInt64)), 'UInt64 token');
    Check(Reader.Read and (Reader.Value.AsDouble = 100), 'exponent number');
  finally
    Reader.Free;
  end;
end;

procedure QuotedPaths;
const
  Data = '{"other":1,"":2," x":3,"a\"b":4,"a\\b":5,"\u0000":6}';
var
  Reader: TJsonReader;
  Root: TJSONValue;
  Iter: TJSONIterator;
  Paths: array[0..5] of string;
  I, Backend: Integer;
begin
  for Backend := 0 to 1 do begin
    Root := nil;
    If Backend = 0 then
      Reader := TJsonTextReader.Create(TStringReader.Create(Data))
    else begin
      Root := TJSONValue.ParseJSONValue(UnicodeString(Data), True, True);
      Reader := TJsonObjectReader.Create(Root);
    end;
    Iter := TJSONIterator.Create(Reader, procedure(R: TJsonReader) begin R.Rewind; end);
    try
      Check(Iter.Next and Iter.Recurse, 'quoted paths root');
      for I := 0 to High(Paths) do begin
        Check(Iter.Next, 'quoted paths item');
        Paths[I] := Iter.Path;
      end;
      for I := 0 to High(Paths) do
        Check(Iter.Find(Paths[I]) and (Iter.AsInteger = I + 1), 'Find(Path) preserves exact JSON key');
    finally
      Iter.Free;
      Reader.Free;
      Root.Free;
    end;
  end;
end;

procedure ObjectWriter;
var
  Writer: TJsonObjectWriter;
  Builder: TJSONObjectBuilder;
begin
  Writer := TJsonObjectWriter.Create(True);
  Builder := TJSONObjectBuilder.Create(Writer);
  try
    Builder.BeginObject.Add('', 1).EndObject;
    Check(Builder.AsJSON = '{"":1}', 'object writer empty scalar key');
    Builder.Clear.BeginObject.BeginArray('').Add(1).EndArray.EndObject;
    Check(Builder.AsJSON = '{"":[1]}', 'object writer empty array key');
    Builder.Clear.BeginObject.BeginObject('').Add('x', 2).EndObject.EndObject;
    Check(Builder.AsJSON = '{"":{"x":2}}', 'object writer empty object key');
  finally
    Builder.Free;
    Writer.Free;
  end;
end;

begin
  Build;
  Readers;
  ObjectWriter;
  QuotedPaths;
  WriteLn('RTL_API_JSON_BUILDER_CONTRACTS_OK');
end.
