{$ifdef BREADTH_HAS_PRODUCT_IO}
{ Import a gzip attachment made by an external service, with the original filename in its header. }

procedure RunBreadthGzipAttachment;
const
  Gzip: array[0..49] of Byte = (
    $1F, $8B, $08, $08, $39, $30, 0, 0, $02, $FF, $73, $6E, $61, $70, $73, $68, $6F, $74, $2E, $63, $73, $76, 0,
    $33, $32, $30, $32, $D3, $35, $34, $D4, $35, $32, $D5, $39, $B7, $9B, $21, $3F, $9B, $0B, 0, $0B, $AA, $C0,
    $66, $11, 0, 0, 0);
  Expected: array[0..16] of Byte = (
    $32, $30, $32, $36, $2D, $31, $31, $2D, $32, $35, $2C, $CE, $BB, 0, $6F, $6B, $0A);
var
  Wire: TMemoryStream;
  Reader: TZDecompressionStream;
  Bytes: array[0..18] of Byte;
  AtEnd: Byte;
begin
  Wire := TMemoryStream.Create;
  try
    Wire.WriteBuffer(Gzip, SizeOf(Gzip));
    Wire.Position := 0;
    Reader := TZDecompressionStream.Create(Wire, 31);
    try
      FillChar(Bytes, SizeOf(Bytes), $AB);
      Reader.ReadBuffer(Bytes[1], Integer(OpaqueI(5)));
      Reader.ReadBuffer(Bytes[6], SizeOf(Expected) - 5);
      Check(CompareMem(@Bytes[1], @Expected[0], SizeOf(Expected)) and (Bytes[0] = $AB) and (Bytes[18] = $AB),
        'breadth-gzip-attachment-decodes-external-header-and-exact-body');
      AtEnd := $BA;
      Check((Reader.Read(AtEnd, 1) = 0) and (AtEnd = $BA) and (Reader.Position = SizeOf(Expected)),
        'breadth-gzip-attachment-stops-at-checksummed-end');
    finally
      Reader.Free;
    end;
    Check(Wire.Position = SizeOf(Gzip), 'breadth-gzip-attachment-consumes-entire-archive');
    Mix(UInt64(Length(Gzip) * 100 + SizeOf(Expected)));
  finally
    Wire.Free;
  end;
end;
{$endif}
