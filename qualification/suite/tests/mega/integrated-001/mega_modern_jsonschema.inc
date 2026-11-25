{$ifdef BREADTH_HAS_PRODUCT_IO}
{ Use the JSON schema to import one strategy and export a separate set of values. }

type
  {$RTTI EXPLICIT FIELDS([vcPublic])}
  TBreadthJsonStrategy = record
  public
    [JsonName('strategy_id')]
    ID: Int64;
    Title: UnicodeString;
    Limits: TArray<Integer>;
    [JsonIgnore]
    LocalLabel: UnicodeString;
  end;
  {$RTTI INHERIT}

procedure RunBreadthJsonStrategySchema;
const
  Wire = '{"strategy_id":9007199254740993,"Title":"val\u0000\u03bb\ud83d\ude80","Limits":[5,17,-23],"LocalLabel":"foreign"}';
var
  Serializer: TJsonSerializer;
  Incoming, Outgoing: TBreadthJsonStrategy;
  Payload, ID, Title, Limits: TJSONValue;
  Obj: TJSONObject;
begin
  Serializer := TJsonSerializer.Create;
  try
    Serializer.ContractResolver := TJsonDefaultContractResolver.Create(TJsonMemberSerialization.Fields);
    Incoming := Serializer.Deserialize<TBreadthJsonStrategy>(Wire);
    Check(Incoming.ID = 9007199254740993, 'breadth-json-schema-import-renames-wide-integer-field');
    Check(Incoming.Title = 'val' + #0 + #$03BB + #$D83D + #$DE80, 'breadth-json-schema-import-keeps-unicode-and-nul');
    Check((Length(Incoming.Limits) = 3) and (Incoming.Limits[0] = 5) and (Incoming.Limits[1] = 17)
      and (Incoming.Limits[2] = -23), 'breadth-json-schema-import-builds-a-typed-array');
    Check(Incoming.LocalLabel = '', 'breadth-json-schema-import-excludes-local-field');

    Outgoing.ID := OpaqueI(-9007199254740989);
    Outgoing.Title := 'out' + #$20AC + #0 + 'x';
    Outgoing.Limits := [71, -9];
    Outgoing.LocalLabel := 'local only';
    Payload := TJSONObject.ParseJSONValue(Serializer.Serialize<TBreadthJsonStrategy>(Outgoing));
    try
      Check(Payload is TJSONObject, 'breadth-json-schema-export-produces-object');
      If not (Payload is TJSONObject) then
        Exit;
      Obj := TJSONObject(Payload);
      ID := Obj.GetValue('strategy_id');
      Title := Obj.GetValue('Title');
      Limits := Obj.GetValue('Limits');
      Check((ID is TJSONNumber) and (ID.Value = '-9007199254740989') and (Obj.GetValue('ID') = nil),
        'breadth-json-schema-export-writes-exact-renamed-numeric-token');
      Check((Title is TJSONString) and (Title.Value = 'out' + #$20AC + #0 + 'x'),
        'breadth-json-schema-export-retains-visible-unicode-and-tail-after-nul');
      Check((Limits is TJSONArray) and (TJSONArray(Limits).Count = 2) and (TJSONArray(Limits).Items[0].Value = '71')
        and (TJSONArray(Limits).Items[1].Value = '-9'), 'breadth-json-schema-export-uses-independent-outgoing-array');
      Check(Obj.GetValue('LocalLabel') = nil, 'breadth-json-schema-export-excludes-local-field');
      Mix(UInt64(Incoming.ID) xor UInt64(Outgoing.ID));
    finally
      Payload.Free;
    end;
  finally
    Serializer.Free;
  end;
end;
{$endif}
