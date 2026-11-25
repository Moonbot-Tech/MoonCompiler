{$ifdef BREADTH_HAS_PRODUCT_IO}
{ An import collision keeps the previous archive until the caller explicitly retries with overwrite. }

procedure RunBreadthArchiveCopyRetry;
var
  Source, Target: string;
  Incoming, Existing, OnDisk: TBytes;
  Rejected: Boolean;
  I: Integer;
begin
  SetLength(Incoming, Integer(OpaqueI(4671)));
  for I := 0 to High(Incoming) do
    Incoming[I] := Byte((I * 37 + 23) and $FF);
  SetLength(Existing, 5000);
  FillChar(Existing[0], Length(Existing), $BA);
  Source := TPath.GetTempFileName;
  try
    Target := TPath.GetTempFileName;
    try
      TFile.WriteAllBytes(Source, Incoming);
      TFile.WriteAllBytes(Target, Existing);
      Rejected := False;
      try
        TFile.Copy(Source, Target, False);
      except
        on EInOutError do Rejected := True;
      end;
      OnDisk := TFile.ReadAllBytes(Target);
      Check(Rejected and (Length(OnDisk) = Length(Existing)) and CompareMem(Pointer(OnDisk), Pointer(Existing), Length(Existing)),
        'breadth-archive-copy-refusal-keeps-existing-bytes');
      TFile.Copy(Source, Target, True);
      OnDisk := TFile.ReadAllBytes(Target);
      Check((Length(OnDisk) = Length(Incoming)) and CompareMem(Pointer(OnDisk), Pointer(Incoming), Length(Incoming)),
        'breadth-archive-copy-retry-replaces-with-all-chunks-and-truncates-old-tail');
      OnDisk := TFile.ReadAllBytes(Source);
      Check((Length(OnDisk) = Length(Incoming)) and CompareMem(Pointer(OnDisk), Pointer(Incoming), Length(Incoming)),
        'breadth-archive-copy-retry-leaves-source-available');
      Mix(UInt64(Length(OnDisk)));
    finally
      DeleteFile(Target);
    end;
  finally
    DeleteFile(Source);
  end;
end;
{$endif}
