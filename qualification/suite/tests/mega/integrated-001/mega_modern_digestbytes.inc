{$ifdef BREADTH_HAS_PRODUCT_IO}
{ Preserve stream boundaries and independently continue two copies of an incremental digest. }

procedure RunBreadthHashStreamWindow;
const
  Prefix: Byte = $BB;
  ByteCycles = 17;
  Expected = '20bec5fa17e100187ba9d1fecf7c81743e24f4c3b49f28d8843089a8995f20ae39b4ded6cbd1243e44ba95136e2eb155'
    + '19e496ee553ff50d410980a5842d9223';
var
  Frame: array[0..ByteCycles * 256 + 1] of Byte;
  Source: TMemoryStream;
  I: Integer;
  Digest: string;
begin
  for I := 0 to High(Frame) - 2 do
    Frame[I] := Byte(I and $FF);
  Frame[High(Frame) - 1] := $FB;
  Frame[High(Frame)] := $FF;
  Source := TMemoryStream.Create;
  try
    Source.WriteBuffer(Prefix, 1);
    Source.WriteBuffer(Frame, SizeOf(Frame));
    Source.Position := OpaqueI(1);
    Digest := THashSHA2.GetHashString(Source, THashSHA2.TSHA2Version.SHA512);
    Check((Source.Position = SizeOf(Frame) + 1) and (Digest = Expected),
      'breadth-sha512-stream-consumes-only-body-across-read-buffer');
  finally
    Source.Free;
  end;
end;

procedure RunBreadthHashSnapshots;
const
  FirstReceipt = '1c06e9d08db634ed7d0c5db70733d8bbf7b11f70aa4f2f40d467a5ae270a88cc';
  ArchiveReceipt = '3717ba4789566cdd8e540dc6feb8fb84bdcd86c6639410abb017f6a1e292805e';
  FreshReceipt = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';
var
  Hasher, Archive: THashSHA2;
  Digest: TBytes;
begin
  Hasher := THashSHA2.Create;
  Hasher.Update(UnicodeString('label') + #0);
  Archive := Hasher;
  Hasher.Update(UnicodeString(#$03BB) + #$D83D + #$DE80);
  Archive.Update(UnicodeString('archive'));
  Check(Hasher.HashAsString = FirstReceipt, 'breadth-sha256-updates-unicode-utf8-with-embedded-nul');
  Check(Archive.HashAsString = ArchiveReceipt, 'breadth-sha256-copy-retains-independent-partial-state');
  Digest := Hasher.HashAsBytes;
  Check((Length(Digest) = 32) and (Digest[0] = $1C) and (Digest[31] = $CC),
    'breadth-sha256-finalized-state-can-be-read-as-binary');
  Hasher.Reset;
  Hasher.Update(UnicodeString('abc'));
  Check(Hasher.HashAsString = FreshReceipt, 'breadth-sha256-reset-discards-previous-record-state');
end;
{$endif}
