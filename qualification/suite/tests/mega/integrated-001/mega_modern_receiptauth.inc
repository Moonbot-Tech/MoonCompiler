{$ifdef BREADTH_HAS_PRODUCT_IO}
{ An exported receipt must match the verifier's HMAC over exactly the encoded payload. }

procedure RunBreadthReceiptAuth;
const
  MessageText: UnicodeString = 'receipt' + #0 + #$03BB + #$D83D#$DE80;
  Sha256 = '719eca9b15339c807e001c55ddb4685d3df76dd7dec6976dac14bc875898ced0';
  Sha512 = '73ff25694199767541d2ac3db21e393b5057b784cd3c1b9fb614b4276397632e'
    + 'f01cf738e738bd8aecc29f7a912ce7d09ac2d80f7381b2056fb13268b78ad820';
var
  Key: string;
  Body, Digest: TBytes;
begin
  Key := StringOfChar('K', Integer(OpaqueI(90))) + #0 + #$03BB;
  Check(THashSHA2.GetHMAC(MessageText, Key) = Sha256, 'breadth-receipt-auth-hashes-long-utf8-key-before-sha256');
  Body := TEncoding.UTF8.GetBytes(MessageText);
  Digest := THashSHA2.GetHMACAsBytes(Body, Key);
  Check((Length(Digest) = 32) and (THash.DigestAsString(Digest) = Sha256),
    'breadth-receipt-auth-binary-message-agrees-with-external-verifier');
  Digest := THashSHA2.GetHMACAsBytes(MessageText, TEncoding.UTF8.GetBytes(Key), THashSHA2.TSHA2Version.SHA512);
  Check((Length(Digest) = 64) and (THash.DigestAsString(Digest) = Sha512),
    'breadth-receipt-auth-selects-sha512-for-binary-key-with-embedded-nul');
  Mix(UInt64(Length(Body) * 100 + Length(Digest)));
end;
{$endif}
