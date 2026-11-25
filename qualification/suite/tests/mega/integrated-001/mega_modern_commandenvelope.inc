{$ifdef BREADTH_HAS_PRODUCT_IO}
{ A command envelope is built in two scopes and has an exact external JSON schema. }

procedure RunBreadthCommandEnvelope;
const
  Expected = '{"batch":9007199254740993,"emit":[17,"x\u0000",null],"pending":true}';
var
  Text: TStringWriter;
  Writer: TJsonTextWriter;
  Builder: TJSONObjectBuilder;
  Root: TJSONCollectionBuilder.TPairs;
  Items: TJSONCollectionBuilder.TElements;
  Wire: string;
begin
  Text := TStringWriter.Create;
  try
    Writer := TJsonTextWriter.Create(Text, False);
    try
      Builder := TJSONObjectBuilder.Create(Writer);
      try
        Root := Builder.BeginObject.Add('batch', OpaqueI(9007199254740993));
        Items := Root.BeginArray('emit');
        Items.AddElements([Integer(OpaqueI(17)), string('x' + #0)]).AddNull.EndArray;
        Root.Add('pending', True).EndObject;
        Wire := Text.ToString;
        Check(Wire = Expected, 'breadth-command-envelope-keeps-wide-token-manages-array-and-resumes-parent');
        Mix(UInt64(Length(Wire)));
      finally
        Builder.Free;
      end;
    finally
      Writer.Free;
    end;
    Check(Text.ToString = Expected, 'breadth-command-envelope-retains-buffer-after-fluent-builder-shutdown');
  finally
    Text.Free;
  end;
end;
{$endif}
