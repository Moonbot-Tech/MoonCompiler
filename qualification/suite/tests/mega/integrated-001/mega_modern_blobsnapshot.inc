{$ifdef BREADTH_HAS_PRODUCT_IO}
{ Binding an attachment copies only its bytes and gives the database driver the binary variant type. }

procedure RunBreadthBlobSnapshot;
const
  Expected: array[0..3] of Byte = (0, $FB, $43, $DE);
var
  Packet, Snapshot: TBytes;
  Parameters: TParams;
  Attachment: TParam;
begin
  Packet := [$A2, 0, $FB, $43, $DE, $E1];
  Parameters := TParams.Create(nil);
  try
    Attachment := Parameters.CreateParam(ftBlob, 'Attachment', ptInput);
    Attachment.SetBlobData(@Packet[Integer(OpaqueI(1))], SizeOf(Expected));
    Check((Attachment.DataType = ftBlob) and Attachment.Bound and not Attachment.IsNull,
      'breadth-blob-snapshot-binds-populated-attachment');
    Check(VarIsArray(Attachment.Value) and ((VarType(Attachment.Value) and varTypeMask) = varByte),
      'breadth-blob-snapshot-retains-binary-variant-for-driver');
    Packet[1] := $8A;
    Packet := nil;
    Snapshot := Attachment.AsBytes;
    Check((Length(Snapshot) = SizeOf(Expected)) and CompareMem(Pointer(Snapshot), @Expected[0], SizeOf(Expected)),
      'breadth-blob-snapshot-keeps-payload-after-source-release-without-framing');
    Mix(UInt64(Length(Snapshot)));
  finally
    Parameters.Free;
  end;
end;
{$endif}
