{$ifdef BREADTH_HAS_PRODUCT_IO}
{ A buffered writer alternates read, overwrite, truncate and append. }

procedure RunBreadthBufferedFileWindow;
const
  Initial: array[0..12] of Byte = ($11, $22, $33, $44, 0, $66, $77, $88, $99, $AA, $BB, $CC, $DD);
  Replace: array[0..3] of Byte = ($A0, 0, $B2, $F3);
  Trailer: array[0..2] of Byte = ($FD, $E2, 0);
  Expected: array[0..11] of Byte = ($11, $22, $33, $A0, 0, $B2, $F3, $88, $99, $FD, $E2, 0);
var
  Path: string;
  Buffered: TBufferedFileStream;
  Direct: TFileStream;
  Readback: array[0..11] of Byte;
begin
  Path := TPath.GetTempFileName;
  try
    Buffered := TBufferedFileStream.Create(Path, fmCreate, 4);
    try
      Buffered.WriteBuffer(Initial, SizeOf(Initial));
      Check((Buffered.Size = 13) and (Buffered.Position = 13), 'breadth-buffered-file-size-includes-unflushed-data');
      Buffered.Position := OpaqueI(3);
      Buffered.WriteBuffer(Replace, SizeOf(Replace));
      Buffered.Seek(-2, soCurrent);
      Buffered.ReadBuffer(Readback[1], 4);
      Check((Buffered.Position = 9) and CompareMem(@Readback[1], @Expected[5], 4),
        'breadth-buffered-file-overwrite-visible-through-next-read');
      Buffered.Size := OpaqueI(9);
      Check((Buffered.Size = 9) and (Buffered.Position = 9), 'breadth-buffered-file-truncates-at-current-position');
      Buffered.Seek(0, soEnd);
      Buffered.WriteBuffer(Trailer, SizeOf(Trailer));
      Check((Buffered.Size = 12) and (Buffered.Position = 12), 'breadth-buffered-file-append-after-truncate-restores-new-tail');
    finally
      Buffered.Free;
    end;
    Direct := TFileStream.Create(Path, fmOpenRead or fmShareDenyWrite);
    try
      Direct.ReadBuffer(Readback, SizeOf(Readback));
      Check((Direct.Size = SizeOf(Expected)) and CompareMem(@Readback[0], @Expected[0], SizeOf(Expected)),
        'breadth-buffered-file-reopen-reads-the-exact-new-record');
      Mix(UInt64(Direct.Position));
    finally
      Direct.Free;
    end;
  finally
    Check(DeleteFile(Path), 'breadth-buffered-file-releases-native-handle-before-removal');
  end;
end;
{$endif}
