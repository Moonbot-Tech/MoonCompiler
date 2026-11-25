{$ifdef BREADTH_HAS_PRODUCT_IO}
{ A parser receives one application message from a larger byte buffer. }

procedure RunBreadthJsonSpan;
const
  MessageText: UnicodeString =
    '{"id":9007199254740993,"price":-1.125,"note":"A\u0000\u03bb\ud83d\ude00",' +
    '"legs":[null,{"id":-9007199254740989,"ready":true}]}';
  Prefix = 'tail->';
  Suffix = '<-header';
var
  Wire: TBytes;
  Root, Leg: TJSONObject;
  Legs: TJSONArray;
  Price: Double;
  Id: TJSONNumber;
  Start, Stop: Integer;
begin
  Wire := TEncoding.UTF8.GetBytes(Prefix + MessageText + Suffix);
  Start := Integer(OpaqueI(Length(Prefix)));
  Stop := Length(Wire) - Integer(OpaqueI(Length(Suffix)));
  Root := TJSONObject.ParseJSONValue(Wire, Start, Stop,
    [TJSONValue.TJSONParseOption.IsUTF8, TJSONValue.TJSONParseOption.UseBool]) as TJSONObject;
  try
    Check(Root <> nil, 'breadth-json-span-parses-only-the-requested-message');
    If Root = nil then
      Exit;
    Id := Root.GetValue('id') as TJSONNumber;
    Price := (Root.GetValue('price') as TJSONNumber).AsDouble;
    Check((Id.Value = '9007199254740993') and (Price = -1.125),
      'breadth-json-span-preserves-exact-decimal-token-and-fraction');
    Check(Root.GetValue('note').Value = 'A'#0#$03BB#$D83D#$DE00, 'breadth-json-span-decodes-nul-and-surrogate-pair');
    Legs := Root.GetValue('legs') as TJSONArray;
    Check((Legs.Count = 2) and Legs.Items[0].Null, 'breadth-json-span-keeps-null-in-array');
    Leg := Legs.Items[1] as TJSONObject;
    Check(((Leg.GetValue('id') as TJSONNumber).Value = '-9007199254740989')
      and (Leg.GetValue('ready') as TJSONBool).AsBoolean, 'breadth-json-span-keeps-nested-signed-number-and-boolean');
    Mix(UInt64(Length(Id.Value)));
    Mix(DoubleBits(Price));
  finally
    Root.Free;
  end;
end;

procedure RunBreadthJsonClone;
const
  LabelText: UnicodeString = 'line'#10'quote"\';
  Expected: UnicodeString = '{"id":-930000000017,"text":"line\nquote\"\\","ready":false}';
var
  Root, Snapshot: TJSONObject;
  Removed: TJSONPair;
  Tags, CopyTags: TJSONArray;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('id', OpaqueI(-930000000017));
    Root.AddPair('text', LabelText);
    Root.AddPair('ready', False);
    Check(Root.ToJSON = Expected, 'breadth-json-build-produces-exact-ascii-escapes-and-decimal-id');
    Tags := TJSONArray.Create;
    Root.AddPair('tags', Tags);
    Tags.Add(UnicodeString('origin'));
    Snapshot := Root.Clone as TJSONObject;
    try
      CopyTags := Snapshot.GetValue('tags') as TJSONArray;
      CopyTags.Add(UnicodeString('extra'));
      Removed := Snapshot.RemovePair('text');
      try
        Check((Removed <> nil) and (Removed.JsonValue.Value = LabelText) and (Snapshot.GetValue('text') = nil),
          'breadth-json-remove-transfers-pair-out-of-clone');
      finally
        Removed.Free;
      end;
      Check((Tags.Count = 1) and (CopyTags.Count = 2) and (CopyTags.Items[1].Value = 'extra')
        and (Root.GetValue('text').Value = LabelText), 'breadth-json-clone-keeps-original-nested-values-independent');
      Mix(UInt64(Root.Count * 10 + Snapshot.Count));
    finally
      Snapshot.Free;
    end;
  finally
    Root.Free;
  end;
end;
{$endif}
