program hash_regex_iso_boundaries_semantic;
{$APPTYPE CONSOLE}
{$IFDEF FPC}{$mode delphiunicode}{$ENDIF}
uses {$IFDEF UNIX}cwstring,{$ENDIF} SysUtils, DateUtils, System.Hash, System.RegularExpressions;
procedure Check(Value: Boolean; const Context: string);
begin
  if not Value then raise Exception.Create(Context);
end;
var
  MD5: THashMD5;
  SHA1: THashSHA1;
  SHA2: THashSHA2;
  I, Kind: Integer;
  Raised: Boolean;
  Bytes: TBytes;
  Text: string;
  Match: TMatch;
  Date: TDateTime;
const
  BadDates: array[0..6] of string = ('2024x01x02T03:04:05Z','2024-01-02T03:04:05x123Z',
    '2024-01-02T03:04:05.1e999Z','2024-01-02T03:04:05.12.3Z',
    '2024-01-02T03:04:05.Z','2024-01-02T+3:04:05Z','2024-01-02T03:04:05+27:99');
begin
  Bytes:=TBytes.Create(Ord('a'));
  MD5:=THashMD5.Create;
  SHA1:=THashSHA1.Create;
  SHA2:=THashSHA2.Create;
  for I:=0 to 1 do
  begin
    MD5.Reset; SHA1.Reset; SHA2.Reset;
    MD5.Update(string('abc')); SHA1.Update(string('abc')); SHA2.Update(string('abc'));
    Check(MD5.HashAsString='900150983cd24fb0d6963f7d28e17f72','MD5 reset');
    Check(SHA1.HashAsString='a9993e364706816aba3e25717850c26c9cd0d89d','SHA1 reset');
    Check(SHA2.HashAsString='ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad','SHA256 reset');
    for Kind:=0 to 8 do
    begin
      Raised:=False;
      try
        case Kind of
          0: MD5.Update(string('x'));
          1: MD5.Update(Bytes);
          2: MD5.Update(Bytes[0],1);
          3: SHA1.Update(string('x'));
          4: SHA1.Update(Bytes);
          5: SHA1.Update(Bytes[0],1);
          6: SHA2.Update(string('x'));
          7: SHA2.Update(Bytes);
          8: SHA2.Update(Bytes[0],1);
        end;
      except on E: EHashException do Raised:=True; end;
      Check(Raised,'update after hash finalization');
    end;
  end;
  Match:=TRegEx.Match('abcd','(a)(?<Left>b)(c)(?<Right>d)');
  Check(Match.Success and (Match.Groups['Left'].Value='b') and (Match.Groups['Right'].Value='d'),
    'named groups separated by unnamed groups');
  Check(Match.Groups[3].Value='c','indexed group control');
  for I:=0 to 1 do
  begin
    Raised:=False;
    try
      if I=0 then Text:=Match.Groups['left'].Value
      else Text:=Match.Groups['missing'].Value;
    except on E: Exception do Raised:=True; end;
    Check(Raised,'group names exact lookup');
  end;
  Check(TryISO8601ToDate('2024-01-02T03:04:05.123Z',Date),'valid ISO fraction');
  Check(TryISO8601ToDate('2024-01-02T03:04:05+03:00',Date),'valid ISO offset');
  for Text in BadDates do
    Check(not TryISO8601ToDate(Text,Date),'malformed ISO accepted: '+Text);
  WriteLn('HASH_REGEX_ISO_BOUNDARIES_PASS');
end.
